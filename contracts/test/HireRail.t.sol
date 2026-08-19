// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HireRail} from "../src/HireRail.sol";
import {IAgenticCommerce} from "../src/interfaces/IAgenticCommerce.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSD is ERC20 {
    constructor() ERC20("United Stables", "U") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// Mock of the ERC-8183 kernel matching the verified ABI's behaviour for
/// the paths HireRail touches: createJob, setBudget, fund (pulls the exact
/// budget from the caller), claimRefund after expiry back to the client.
contract MockKernel {
    MockUSD public immutable usd;
    uint256 public jobCounter;

    struct J {
        address client;
        address provider;
        address evaluator;
        uint256 budget;
        uint256 expiredAt;
        IAgenticCommerce.JobStatus status;
        string description;
    }

    mapping(uint256 => J) public jobsById;

    constructor(MockUSD usd_) {
        usd = usd_;
    }

    function paymentToken() external view returns (address) {
        return address(usd);
    }

    function createJob(address provider, address evaluator, uint256 expiredAt, string calldata description, address)
        external
        returns (uint256 jobId)
    {
        jobId = ++jobCounter;
        jobsById[jobId] = J({
            client: msg.sender,
            provider: provider,
            evaluator: evaluator,
            budget: 0,
            expiredAt: expiredAt,
            status: IAgenticCommerce.JobStatus.Open,
            description: description
        });
    }

    function setBudget(uint256 jobId, uint256 amount, bytes calldata) external {
        require(jobsById[jobId].client == msg.sender, "not client");
        jobsById[jobId].budget = amount;
    }

    function fund(uint256 jobId, uint256 expectedBudget, bytes calldata) external {
        J storage j = jobsById[jobId];
        require(j.budget == expectedBudget, "budget mismatch");
        require(j.status == IAgenticCommerce.JobStatus.Open, "not open");
        usd.transferFrom(msg.sender, address(this), expectedBudget);
        j.status = IAgenticCommerce.JobStatus.Funded;
    }

    function claimRefund(uint256 jobId) external {
        J storage j = jobsById[jobId];
        require(j.client == msg.sender, "not client");
        require(block.timestamp > j.expiredAt, "not expired");
        require(j.status == IAgenticCommerce.JobStatus.Funded, "not refundable");
        j.status = IAgenticCommerce.JobStatus.Expired;
        usd.transfer(j.client, j.budget);
    }

    function getJob(uint256 jobId) external view returns (IAgenticCommerce.Job memory job) {
        J storage j = jobsById[jobId];
        job.id = jobId;
        job.client = j.client;
        job.provider = j.provider;
        job.evaluator = j.evaluator;
        job.budget = j.budget;
        job.expiredAt = j.expiredAt;
        job.status = j.status;
        job.description = j.description;
    }
}

contract HireRailTest is Test {
    MockUSD usd;
    MockKernel kernel;
    HireRail rail;

    address hirer = makeAddr("hirer");
    address provider = makeAddr("provider");
    address evaluator = makeAddr("evaluator");

    function setUp() public {
        usd = new MockUSD();
        kernel = new MockKernel(usd);
        rail = new HireRail(address(kernel), evaluator);
        usd.mint(hirer, 1_000e18);
    }

    function hireOnce(uint256 budget) internal returns (uint256 jobId) {
        vm.startPrank(hirer);
        usd.approve(address(rail), budget);
        jobId = rail.hire(7, provider, budget, uint64(block.timestamp + 1 days), keccak256("spec"), "do the thing");
        vm.stopPrank();
    }

    function test_hire_opens_budgets_and_funds_in_one_tx() public {
        uint256 jobId = hireOnce(5e18);
        IAgenticCommerce.Job memory job = kernel.getJob(jobId);
        assertEq(uint8(job.status), uint8(IAgenticCommerce.JobStatus.Funded));
        assertEq(job.budget, 5e18);
        assertEq(job.provider, provider);
        assertEq(job.evaluator, evaluator);
        assertEq(rail.hirerOf(jobId), hirer);
        assertEq(rail.agentOf(jobId), 7);
        // The rail never keeps funds.
        assertEq(usd.balanceOf(address(rail)), 0);
        assertEq(usd.balanceOf(hirer), 995e18);
    }

    function test_hire_reverts_when_deadline_in_past() public {
        vm.startPrank(hirer);
        usd.approve(address(rail), 1e18);
        vm.expectRevert(HireRail.DeadlineInPast.selector);
        rail.hire(1, provider, 1e18, uint64(block.timestamp), keccak256("s"), "d");
        vm.stopPrank();
    }

    function test_hire_reverts_when_allowance_short() public {
        vm.startPrank(hirer);
        usd.approve(address(rail), 1e18 - 1);
        vm.expectRevert();
        rail.hire(1, provider, 1e18, uint64(block.timestamp + 1), keccak256("s"), "d");
        vm.stopPrank();
    }

    function test_hire_reverts_when_paused() public {
        rail.pause();
        vm.startPrank(hirer);
        usd.approve(address(rail), 1e18);
        vm.expectRevert();
        rail.hire(1, provider, 1e18, uint64(block.timestamp + 1), keccak256("s"), "d");
        vm.stopPrank();
    }

    function test_hire_reverts_on_zero_budget_and_zero_provider() public {
        vm.startPrank(hirer);
        vm.expectRevert(HireRail.ZeroBudget.selector);
        rail.hire(1, provider, 0, uint64(block.timestamp + 1), keccak256("s"), "d");
        vm.expectRevert(HireRail.ZeroProvider.selector);
        rail.hire(1, address(0), 1e18, uint64(block.timestamp + 1), keccak256("s"), "d");
        vm.stopPrank();
    }

    function test_reclaim_refunds_the_hirer_after_expiry() public {
        uint256 jobId = hireOnce(5e18);
        vm.warp(block.timestamp + 2 days);
        // Permissionless: a third party can trigger, funds go to the hirer.
        rail.reclaim(jobId);
        assertEq(usd.balanceOf(hirer), 1_000e18);
        assertEq(usd.balanceOf(address(rail)), 0);
    }

    function test_reclaim_reverts_for_unknown_job() public {
        vm.expectRevert(HireRail.NotHirer.selector);
        rail.reclaim(999);
    }

    function test_reclaim_reverts_before_expiry() public {
        uint256 jobId = hireOnce(5e18);
        vm.expectRevert();
        rail.reclaim(jobId);
    }

    /// Fuzz: any valid hire leaves the rail with a zero token balance and
    /// exact escrow in the kernel.
    function testFuzz_rail_balance_always_zero(uint96 budget, uint32 ttl) public {
        budget = uint96(bound(budget, 1, 1_000e18));
        ttl = uint32(bound(ttl, 1, 365 days));
        vm.startPrank(hirer);
        usd.approve(address(rail), budget);
        rail.hire(3, provider, budget, uint64(block.timestamp + ttl), keccak256("z"), "fuzz");
        vm.stopPrank();
        assertEq(usd.balanceOf(address(rail)), 0);
        assertEq(usd.balanceOf(address(kernel)), budget);
    }

    function test_pause_is_owner_only() public {
        vm.prank(hirer);
        vm.expectRevert();
        rail.pause();
    }
}

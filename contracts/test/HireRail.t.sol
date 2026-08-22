// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HireRail} from "../src/HireRail.sol";
import {IAgenticCommerce} from "../src/interfaces/IAgenticCommerce.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSD is ERC20 {
    constructor() ERC20("United Stables", "U") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// Mock of the ERC-8183 kernel matching the verified ABI's behaviour for the
/// paths HireRail touches. The fork test in HireRailFork.t.sol exercises the
/// same paths against the real deployed bytecode; this mock exists so the
/// unit suite runs with no network.
contract MockKernel {
    MockUSD public immutable usd;
    uint256 public jobCounter;

    struct J {
        address client;
        address provider;
        address evaluator;
        address hook;
        uint256 budget;
        uint256 expiredAt;
        IAgenticCommerce.JobStatus status;
    }

    mapping(uint256 => J) public jobsById;

    constructor(MockUSD usd_) {
        usd = usd_;
    }

    function paymentToken() external view returns (address) {
        return address(usd);
    }

    function createJob(address provider, address evaluator, uint256 expiredAt, string calldata, address hook)
        external
        returns (uint256 jobId)
    {
        jobId = ++jobCounter;
        jobsById[jobId] = J({
            client: msg.sender,
            provider: provider,
            evaluator: evaluator,
            hook: hook,
            budget: 0,
            expiredAt: expiredAt,
            status: IAgenticCommerce.JobStatus.Open
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
        require(j.status == IAgenticCommerce.JobStatus.Expired, "not expired");
        j.status = IAgenticCommerce.JobStatus.Expired;
        uint256 amount = j.budget;
        j.budget = 0;
        usd.transfer(j.client, amount);
    }

    function expire(uint256 jobId) external {
        J storage j = jobsById[jobId];
        require(block.timestamp > j.expiredAt, "not expired");
        j.status = IAgenticCommerce.JobStatus.Expired;
    }

    function getJob(uint256 jobId) external view returns (IAgenticCommerce.Job memory job) {
        J storage j = jobsById[jobId];
        job.id = jobId;
        job.client = j.client;
        job.provider = j.provider;
        job.evaluator = j.evaluator;
        job.hook = j.hook;
        job.budget = j.budget;
        job.expiredAt = j.expiredAt;
        job.status = j.status;
    }
}

/// Mock router enforcing the same rules the real one does: the router must be
/// the job's evaluator and hook, only the client may register, and the policy
/// must be whitelisted.
contract MockRouter {
    MockKernel public immutable kernel;
    mapping(uint256 => address) public jobPolicy;
    mapping(address => bool) public policyWhitelist;
    bool public settleShouldRevert;

    error RouterNotEvaluator();
    error RouterNotHook();
    error NotJobClient();
    error PolicyNotWhitelisted();

    constructor(MockKernel kernel_, address policy_) {
        kernel = kernel_;
        policyWhitelist[policy_] = true;
    }

    function registerJob(uint256 jobId, address policy) external {
        IAgenticCommerce.Job memory j = kernel.getJob(jobId);
        if (j.evaluator != address(this)) revert RouterNotEvaluator();
        if (j.hook != address(this)) revert RouterNotHook();
        if (j.client != msg.sender) revert NotJobClient();
        if (!policyWhitelist[policy]) revert PolicyNotWhitelisted();
        jobPolicy[jobId] = policy;
    }

    function settle(uint256, bytes calldata) external view {
        require(!settleShouldRevert, "not decided");
    }

    function markExpired(uint256 jobId) external {
        kernel.expire(jobId);
    }

    function setSettleShouldRevert(bool v) external {
        settleShouldRevert = v;
    }
}

contract HireRailTest is Test {
    MockUSD usd;
    MockKernel kernel;
    MockRouter router;
    HireRail rail;

    address hirer = makeAddr("hirer");
    address provider = makeAddr("provider");
    address stranger = makeAddr("stranger");
    address policy = makeAddr("policy");

    function setUp() public {
        usd = new MockUSD();
        kernel = new MockKernel(usd);
        router = new MockRouter(kernel, policy);
        rail = new HireRail(address(kernel), address(router), policy);
        usd.mint(hirer, 1_000e18);
    }

    function hireOnce(uint256 budget) internal returns (uint256 jobId) {
        vm.startPrank(hirer);
        usd.approve(address(rail), budget);
        jobId = rail.hire(7, provider, budget, uint64(block.timestamp + 1 days), keccak256("spec"), "do the thing");
        vm.stopPrank();
    }

    function test_hire_opens_binds_budgets_and_funds_in_one_tx() public {
        uint256 jobId = hireOnce(5e18);
        IAgenticCommerce.Job memory job = kernel.getJob(jobId);
        assertEq(uint8(job.status), uint8(IAgenticCommerce.JobStatus.Funded));
        assertEq(job.budget, 5e18);
        assertEq(job.provider, provider);
        // The router must be both evaluator and hook or the real kernel path
        // reverts; assert we always satisfy that.
        assertEq(job.evaluator, address(router));
        assertEq(job.hook, address(router));
        // The dispute policy is bound, so settle can decide later.
        assertEq(router.jobPolicy(jobId), policy);
        assertEq(rail.hirerOf(jobId), hirer);
        assertEq(rail.agentOf(jobId), 7);
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

    function test_settle_forwards_to_router() public {
        uint256 jobId = hireOnce(5e18);
        vm.prank(stranger);
        rail.settle(jobId, "");
    }

    function test_settle_reverts_for_unknown_job() public {
        vm.expectRevert(HireRail.UnknownJob.selector);
        rail.settle(999, "");
    }

    function test_settle_bubbles_router_revert() public {
        uint256 jobId = hireOnce(5e18);
        router.setSettleShouldRevert(true);
        vm.expectRevert();
        rail.settle(jobId, "");
    }

    function test_reclaim_refunds_the_hirer_after_expiry() public {
        uint256 jobId = hireOnce(5e18);
        vm.warp(block.timestamp + 2 days);
        // Permissionless: a stranger triggers it, funds go to the hirer.
        vm.prank(stranger);
        rail.reclaim(jobId);
        assertEq(usd.balanceOf(hirer), 1_000e18);
        assertEq(usd.balanceOf(address(rail)), 0);
    }

    function test_reclaim_reverts_for_unknown_job() public {
        vm.expectRevert(HireRail.UnknownJob.selector);
        rail.reclaim(999);
    }

    function test_reclaim_reverts_before_expiry() public {
        uint256 jobId = hireOnce(5e18);
        vm.expectRevert();
        rail.reclaim(jobId);
    }

    function test_reclaim_twice_reverts() public {
        uint256 jobId = hireOnce(5e18);
        vm.warp(block.timestamp + 2 days);
        rail.reclaim(jobId);
        vm.expectRevert();
        rail.reclaim(jobId);
    }

    /// Any valid hire leaves the rail holding nothing and the escrow exact.
    function testFuzz_rail_balance_always_zero(uint96 budget, uint32 ttl) public {
        budget = uint96(bound(budget, 1, 1_000e18));
        ttl = uint32(bound(ttl, 1, 365 days));
        vm.startPrank(hirer);
        usd.approve(address(rail), budget);
        rail.hire(3, provider, budget, uint64(block.timestamp + ttl), keccak256("z"), "fuzz");
        vm.stopPrank();
        assertEq(usd.balanceOf(address(rail)), 0);
        assertEq(usd.balanceOf(address(kernel)), budget);
        assertEq(usd.allowance(address(rail), address(kernel)), 0);
    }

    function test_pause_and_unpause_are_owner_only() public {
        vm.prank(hirer);
        vm.expectRevert();
        rail.pause();
        rail.pause();
        vm.prank(hirer);
        vm.expectRevert();
        rail.unpause();
        rail.unpause();
    }

    function test_pausing_does_not_trap_an_existing_job() public {
        uint256 jobId = hireOnce(5e18);
        rail.pause();
        vm.warp(block.timestamp + 2 days);
        rail.reclaim(jobId);
        assertEq(usd.balanceOf(hirer), 1_000e18);
    }
}

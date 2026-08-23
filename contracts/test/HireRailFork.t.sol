// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HireRail} from "../src/HireRail.sol";
import {TrustListHook} from "../src/TrustListHook.sol";
import {IAgenticCommerce} from "../src/interfaces/IAgenticCommerce.sol";
import {IEvaluatorRouter} from "../src/interfaces/IEvaluatorRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// Integration tests against the REAL ERC-8183 deployment on BSC mainnet,
/// run over a fork. Only the live contracts enforce the kernel's hook gate
/// and the router's evaluator rules, so this is the only place those are
/// genuinely proven.
///
/// Run with:
///   BSC_FORK_RPC=<rpc> forge test --match-contract HireRailFork
/// Skipped when BSC_FORK_RPC is unset, so the default suite stays offline.
contract HireRailForkTest is Test {
    address constant KERNEL = 0xEa4DAa3100A767e86FDed867729ae7446476EBA6;
    address constant ROUTER = 0x51895229E12F9876011789B04f8698af06cCD6DA;
    address constant POLICY = 0x9C01845705b3078Aa2e8cfF7520a6376FD766dE5;
    address constant U_TOKEN = 0xcE24439F2D9C6a2289F741120FE202248B666666;

    /// Read off the live policy: seven days, baked in as an immutable.
    uint64 constant LIVE_DISPUTE_WINDOW = 604800;

    HireRail rail;
    TrustListHook hook;
    IERC20 u;
    address hirer = makeAddr("hirer");
    address provider = makeAddr("provider");

    bool forked;

    function setUp() public {
        string memory rpc = vm.envOr("BSC_FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        forked = true;

        hook = new TrustListHook();
        rail = new HireRail(KERNEL, ROUTER, POLICY, address(hook));
        u = IERC20(U_TOKEN);
        deal(U_TOKEN, hirer, 100e18);
    }

    modifier onlyForked() {
        if (!forked) return;
        _;
    }

    /// Protected jobs must outlast the live seven day window; direct jobs
    /// settle on acceptance so a short deadline is fine.
    function hireIn(HireRail.Mode mode, uint256 budget) internal returns (uint256 jobId) {
        uint64 ttl = mode == HireRail.Mode.Protected ? 14 days : 1 days;
        vm.startPrank(hirer);
        u.approve(address(rail), budget);
        jobId = rail.hire(12345, provider, budget, uint64(block.timestamp + ttl), keccak256("spec"), "fork test", mode);
        vm.stopPrank();
    }

    function test_fork_wiring_matches_the_live_deployment() public view onlyForked {
        assertEq(address(rail.token()), U_TOKEN, "payment token");
        assertEq(address(rail.kernel()), KERNEL, "kernel");
        assertEq(address(rail.router()), ROUTER, "router");
        // Binding an unwhitelisted policy would revert every protected hire.
        assertTrue(IEvaluatorRouter(ROUTER).policyWhitelist(POLICY), "policy whitelisted");
    }

    /// The seven day window is an immutable in the deployed policy. If this
    /// ever changes, our copy is stale and the demo timing is wrong.
    function test_fork_live_dispute_window_is_still_seven_days() public view onlyForked {
        assertEq(rail.disputeWindow(), LIVE_DISPUTE_WINDOW, "live policy window");
    }

    function test_fork_protected_hire_funds_a_real_job_and_binds_the_policy() public onlyForked {
        uint256 counterBefore = IAgenticCommerce(KERNEL).jobCounter();
        uint256 jobId = hireIn(HireRail.Mode.Protected, 5e18);

        assertEq(jobId, counterBefore + 1, "job id follows the live counter");
        IAgenticCommerce.Job memory job = IAgenticCommerce(KERNEL).getJob(jobId);
        assertEq(uint8(job.status), uint8(IAgenticCommerce.JobStatus.Funded), "funded");
        assertEq(job.budget, 5e18, "budget");
        assertEq(job.client, address(rail), "rail is the client");
        // The live router enforces both of these or the hire reverts.
        assertEq(job.evaluator, ROUTER, "router evaluates");
        assertEq(job.hook, ROUTER, "router hooks");
        assertEq(IEvaluatorRouter(ROUTER).jobPolicy(jobId), POLICY, "policy bound");

        assertEq(u.balanceOf(address(rail)), 0, "rail holds nothing");
        assertEq(u.allowance(address(rail), KERNEL), 0, "no standing approval");
        assertEq(u.balanceOf(hirer), 95e18, "hirer debited exactly");
    }

    /// The live policy will not approve before its window, and the window is
    /// an immutable in the deployed bytecode. This pins that behaviour so a
    /// change upstream fails our tests rather than our demo.
    function test_fork_protected_settlement_waits_the_full_live_window() public onlyForked {
        uint256 jobId = hireIn(HireRail.Mode.Protected, 5e18);
        vm.prank(provider);
        IAgenticCommerce(KERNEL).submit(jobId, keccak256("delivered"), "");

        vm.warp(block.timestamp + LIVE_DISPUTE_WINDOW - 1);
        vm.expectRevert();
        rail.settle(jobId, "");

        vm.warp(block.timestamp + 2);
        rail.settle(jobId, "");
        assertEq(
            uint8(IAgenticCommerce(KERNEL).getJob(jobId).status),
            uint8(IAgenticCommerce.JobStatus.Completed),
            "completed once the window closed"
        );
        assertEq(u.balanceOf(provider), 5e18, "provider paid in full");
    }

    /// Direct mode against the real kernel: the hook gate is only enforced
    /// here, and payout lands in the same block.
    function test_fork_direct_hire_pays_the_provider_in_the_same_block() public onlyForked {
        uint256 jobId = hireIn(HireRail.Mode.Direct, 5e18);

        IAgenticCommerce.Job memory job = IAgenticCommerce(KERNEL).getJob(jobId);
        assertEq(job.evaluator, address(rail), "rail evaluates");
        assertEq(job.hook, address(hook), "our own hook satisfied the kernel");

        uint256 startTime = block.timestamp;
        vm.prank(provider);
        IAgenticCommerce(KERNEL).submit(jobId, keccak256("delivered"), "");
        vm.prank(hirer);
        rail.accept(jobId);

        assertEq(block.timestamp, startTime, "no time passed");
        assertEq(
            uint8(IAgenticCommerce(KERNEL).getJob(jobId).status),
            uint8(IAgenticCommerce.JobStatus.Completed),
            "completed"
        );
        assertEq(u.balanceOf(provider), 5e18, "provider paid in full, no fee taken");
        assertEq(u.balanceOf(address(rail)), 0, "rail holds nothing");
    }

    function test_fork_direct_escrow_cannot_be_released_by_anyone_else() public onlyForked {
        uint256 jobId = hireIn(HireRail.Mode.Direct, 5e18);
        vm.prank(provider);
        IAgenticCommerce(KERNEL).submit(jobId, keccak256("delivered"), "");

        // Not the owner of the rail.
        vm.expectRevert(HireRail.NotHirer.selector);
        rail.accept(jobId);
        // Not the agent being paid, and not straight on the kernel either.
        vm.prank(provider);
        vm.expectRevert(HireRail.NotHirer.selector);
        rail.accept(jobId);
        vm.prank(provider);
        vm.expectRevert();
        IAgenticCommerce(KERNEL).complete(jobId, bytes32(0), "");

        assertEq(u.balanceOf(provider), 0, "escrow untouched");
    }

    function test_fork_reclaim_returns_escrow_to_the_hirer_after_expiry() public onlyForked {
        vm.startPrank(hirer);
        u.approve(address(rail), 3e18);
        uint256 jobId = rail.hire(
            7, provider, 3e18, uint64(block.timestamp + 1 hours), keccak256("spec"), "expiry", HireRail.Mode.Direct
        );
        vm.stopPrank();
        assertEq(u.balanceOf(hirer), 97e18, "escrowed");

        vm.warp(block.timestamp + 2 hours);
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        rail.reclaim(jobId);

        assertEq(u.balanceOf(hirer), 100e18, "hirer made whole");
        assertEq(u.balanceOf(address(rail)), 0, "rail holds nothing");
        assertEq(u.balanceOf(stranger), 0, "caller gains nothing");
    }
}

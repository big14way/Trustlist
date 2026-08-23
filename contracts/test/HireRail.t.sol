// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HireRail} from "../src/HireRail.sol";
import {TrustListHook} from "../src/TrustListHook.sol";
import {IAgenticCommerce} from "../src/interfaces/IAgenticCommerce.sol";
import {MockKernel, MockPolicy, MockRouter, MockUSD} from "./mocks/Mocks.sol";

contract HireRailTest is Test {
    MockUSD usd;
    MockKernel kernel;
    MockPolicy policyContract;
    MockRouter router;
    TrustListHook hook;
    HireRail rail;

    uint64 constant DISPUTE_WINDOW = 1 hours;
    uint64 constant TTL = 3 days;

    address hirer = makeAddr("hirer");
    address provider = makeAddr("provider");
    address stranger = makeAddr("stranger");
    address policy;

    function setUp() public {
        usd = new MockUSD();
        kernel = new MockKernel(usd);
        policyContract = new MockPolicy(DISPUTE_WINDOW);
        policy = address(policyContract);
        router = new MockRouter(kernel, policyContract);
        hook = new TrustListHook();
        rail = new HireRail(address(kernel), address(router), policy, address(hook));
        usd.mint(hirer, 1_000e18);
    }

    function hireIn(HireRail.Mode mode, uint256 budget) internal returns (uint256 jobId) {
        vm.startPrank(hirer);
        usd.approve(address(rail), budget);
        jobId = rail.hire(7, provider, budget, uint64(block.timestamp + TTL), keccak256("spec"), "do the thing", mode);
        vm.stopPrank();
    }

    function deliver(uint256 jobId) internal {
        vm.prank(provider);
        kernel.submit(jobId, keccak256("deliverable"), "");
    }

    // ---------------------------------------------------------------
    // Opening and funding
    // ---------------------------------------------------------------

    function test_protected_hire_uses_the_router_as_evaluator_and_hook() public {
        uint256 jobId = hireIn(HireRail.Mode.Protected, 5e18);
        IAgenticCommerce.Job memory job = kernel.getJob(jobId);
        assertEq(uint8(job.status), uint8(IAgenticCommerce.JobStatus.Funded));
        assertEq(job.evaluator, address(router), "router evaluates");
        assertEq(job.hook, address(router), "router hooks");
        assertEq(router.jobPolicy(jobId), policy, "policy bound");
        assertEq(usd.balanceOf(address(rail)), 0);
        assertEq(usd.balanceOf(hirer), 995e18);
    }

    function test_direct_hire_makes_the_rail_the_evaluator_with_its_own_hook() public {
        uint256 jobId = hireIn(HireRail.Mode.Direct, 5e18);
        IAgenticCommerce.Job memory job = kernel.getJob(jobId);
        assertEq(uint8(job.status), uint8(IAgenticCommerce.JobStatus.Funded));
        assertEq(job.evaluator, address(rail), "rail evaluates");
        assertEq(job.hook, address(hook), "our own hook");
        // Direct jobs are deliberately not registered with the router.
        assertEq(router.jobPolicy(jobId), address(0), "no policy bound");
        assertEq(uint8(rail.modeOf(jobId)), uint8(HireRail.Mode.Direct));
    }

    function test_hire_reverts_when_the_deadline_is_too_soon() public {
        vm.startPrank(hirer);
        usd.approve(address(rail), 1e18);
        vm.expectRevert(HireRail.DeadlineTooSoon.selector);
        rail.hire(1, provider, 1e18, uint64(block.timestamp + 60), keccak256("s"), "d", HireRail.Mode.Direct);
        vm.stopPrank();
    }

    function test_hire_reverts_on_short_allowance_zero_budget_and_zero_provider() public {
        vm.startPrank(hirer);
        usd.approve(address(rail), 1e18 - 1);
        vm.expectRevert();
        rail.hire(1, provider, 1e18, uint64(block.timestamp + TTL), keccak256("s"), "d", HireRail.Mode.Direct);
        vm.expectRevert(HireRail.ZeroBudget.selector);
        rail.hire(1, provider, 0, uint64(block.timestamp + TTL), keccak256("s"), "d", HireRail.Mode.Direct);
        vm.expectRevert(HireRail.ZeroProvider.selector);
        rail.hire(1, address(0), 1e18, uint64(block.timestamp + TTL), keccak256("s"), "d", HireRail.Mode.Direct);
        vm.stopPrank();
    }

    function test_hire_reverts_when_paused_but_escrow_never_gets_trapped() public {
        uint256 jobId = hireIn(HireRail.Mode.Direct, 5e18);
        rail.pause();
        vm.startPrank(hirer);
        usd.approve(address(rail), 1e18);
        vm.expectRevert();
        rail.hire(1, provider, 1e18, uint64(block.timestamp + TTL), keccak256("s"), "d", HireRail.Mode.Direct);
        vm.stopPrank();
        // Accepting and reclaiming stay open while paused.
        deliver(jobId);
        vm.prank(hirer);
        rail.accept(jobId);
        assertEq(usd.balanceOf(provider), 5e18);
    }

    // ---------------------------------------------------------------
    // Direct mode: the rail is the evaluator, the hirer holds the authority
    // ---------------------------------------------------------------

    function test_accept_pays_the_provider_in_the_same_call() public {
        uint256 jobId = hireIn(HireRail.Mode.Direct, 5e18);
        deliver(jobId);
        vm.prank(hirer);
        rail.accept(jobId);
        assertEq(uint8(kernel.getJob(jobId).status), uint8(IAgenticCommerce.JobStatus.Completed));
        assertEq(usd.balanceOf(provider), 5e18, "provider paid in full");
        assertEq(usd.balanceOf(address(rail)), 0, "rail holds nothing");
    }

    /// The whole trust claim of Direct mode is this test: being the
    /// evaluator gives this contract the power to release escrow, and the
    /// only code path that uses it demands the hirer.
    function test_nobody_but_the_hirer_can_release_a_direct_escrow() public {
        uint256 jobId = hireIn(HireRail.Mode.Direct, 5e18);
        deliver(jobId);

        // The contract owner is not privileged here.
        vm.expectRevert(HireRail.NotHirer.selector);
        rail.accept(jobId);

        vm.prank(stranger);
        vm.expectRevert(HireRail.NotHirer.selector);
        rail.accept(jobId);

        // Not even the agent being paid can trigger its own payout.
        vm.prank(provider);
        vm.expectRevert(HireRail.NotHirer.selector);
        rail.accept(jobId);

        // And calling the kernel directly does not work either, because the
        // kernel only listens to the evaluator, which is this contract.
        vm.prank(provider);
        vm.expectRevert();
        kernel.complete(jobId, bytes32(0), "");

        assertEq(usd.balanceOf(provider), 0, "escrow untouched");
    }

    function test_rejectWork_returns_the_escrow_to_the_hirer() public {
        uint256 jobId = hireIn(HireRail.Mode.Direct, 5e18);
        deliver(jobId);
        vm.prank(hirer);
        rail.rejectWork(jobId);
        assertEq(uint8(kernel.getJob(jobId).status), uint8(IAgenticCommerce.JobStatus.Rejected));
        assertEq(usd.balanceOf(hirer), 1_000e18, "hirer made whole");
        assertEq(usd.balanceOf(provider), 0, "provider paid nothing");
        assertEq(usd.balanceOf(address(rail)), 0, "rail holds nothing");
    }

    function test_only_the_hirer_can_reject_work() public {
        uint256 jobId = hireIn(HireRail.Mode.Direct, 5e18);
        deliver(jobId);
        vm.prank(stranger);
        vm.expectRevert(HireRail.NotHirer.selector);
        rail.rejectWork(jobId);
    }

    function test_accept_and_reject_reject_unknown_jobs_and_wrong_mode() public {
        vm.expectRevert(HireRail.UnknownJob.selector);
        rail.accept(999);
        vm.expectRevert(HireRail.UnknownJob.selector);
        rail.rejectWork(999);

        uint256 protectedJob = hireIn(HireRail.Mode.Protected, 5e18);
        deliver(protectedJob);
        vm.prank(hirer);
        vm.expectRevert(HireRail.WrongMode.selector);
        rail.accept(protectedJob);
        vm.prank(hirer);
        vm.expectRevert(HireRail.WrongMode.selector);
        rail.rejectWork(protectedJob);
    }

    // ---------------------------------------------------------------
    // Protected mode: nobody decides unilaterally
    // ---------------------------------------------------------------

    function test_settle_completes_the_job_and_pays_the_provider() public {
        uint256 jobId = hireIn(HireRail.Mode.Protected, 5e18);
        deliver(jobId);
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        // Permissionless: a stranger can push the payout through.
        vm.prank(stranger);
        rail.settle(jobId, "");
        assertEq(uint8(kernel.getJob(jobId).status), uint8(IAgenticCommerce.JobStatus.Completed));
        assertEq(usd.balanceOf(provider), 5e18);
    }

    function test_disputed_job_settles_back_to_the_hirer() public {
        uint256 jobId = hireIn(HireRail.Mode.Protected, 5e18);
        deliver(jobId);
        policyContract.dispute(jobId);
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        rail.settle(jobId, "");
        assertEq(uint8(kernel.getJob(jobId).status), uint8(IAgenticCommerce.JobStatus.Rejected));
        assertEq(usd.balanceOf(hirer), 1_000e18, "hirer made whole in one step");
        assertEq(usd.balanceOf(address(rail)), 0);
        assertTrue(rail.refundForwarded(jobId));
    }

    function test_settle_reverts_before_the_window_closes_and_for_direct_jobs() public {
        uint256 jobId = hireIn(HireRail.Mode.Protected, 5e18);
        deliver(jobId);
        vm.expectRevert();
        rail.settle(jobId, "");

        uint256 directJob = hireIn(HireRail.Mode.Direct, 5e18);
        vm.expectRevert(HireRail.WrongMode.selector);
        rail.settle(directJob, "");

        vm.expectRevert(HireRail.UnknownJob.selector);
        rail.settle(999, "");
    }

    // ---------------------------------------------------------------
    // Expiry and stranded refunds
    // ---------------------------------------------------------------

    function test_reclaim_refunds_the_hirer_after_expiry() public {
        uint256 jobId = hireIn(HireRail.Mode.Direct, 5e18);
        vm.warp(block.timestamp + TTL + 1);
        vm.prank(stranger);
        rail.reclaim(jobId);
        assertEq(usd.balanceOf(hirer), 1_000e18);
        assertEq(usd.balanceOf(address(rail)), 0);
        assertEq(usd.balanceOf(stranger), 0, "caller gains nothing");
    }

    function test_reclaim_rejects_unknown_early_and_repeat_calls() public {
        vm.expectRevert(HireRail.UnknownJob.selector);
        rail.reclaim(999);

        uint256 jobId = hireIn(HireRail.Mode.Direct, 5e18);
        vm.expectRevert();
        rail.reclaim(jobId);

        vm.warp(block.timestamp + TTL + 1);
        rail.reclaim(jobId);
        vm.expectRevert();
        rail.reclaim(jobId);
    }

    function test_forwardRefund_rescues_a_rejection_settled_outside_the_rail() public {
        uint256 jobId = hireIn(HireRail.Mode.Protected, 5e18);
        deliver(jobId);
        policyContract.dispute(jobId);
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);

        // Settled straight on the router, bypassing our rail. The kernel
        // refunds its client, which is the rail, so it lands here.
        router.settle(jobId, "");
        assertEq(usd.balanceOf(address(rail)), 5e18, "stranded on the rail");

        vm.prank(stranger);
        rail.forwardRefund(jobId);
        assertEq(usd.balanceOf(hirer), 1_000e18, "pushed to the hirer");
        assertEq(usd.balanceOf(address(rail)), 0, "rail empty");
        assertEq(usd.balanceOf(stranger), 0, "caller gains nothing");

        vm.expectRevert(HireRail.NothingToRefund.selector);
        rail.forwardRefund(jobId);
    }

    function test_forwardRefund_rejects_unknown_and_unfinished_jobs() public {
        vm.expectRevert(HireRail.UnknownJob.selector);
        rail.forwardRefund(999);
        uint256 jobId = hireIn(HireRail.Mode.Direct, 5e18);
        vm.expectRevert(HireRail.JobNotRefundable.selector);
        rail.forwardRefund(jobId);
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

    // ---------------------------------------------------------------
    // Invariants
    // ---------------------------------------------------------------

    /// The rail is a conduit, never a vault.
    function testFuzz_rail_never_holds_funds_at_rest(uint96 budget, uint8 pathPick) public {
        budget = uint96(bound(budget, 1, 1_000e18));
        uint8 path = pathPick % 4;

        HireRail.Mode mode = path < 2 ? HireRail.Mode.Direct : HireRail.Mode.Protected;
        vm.startPrank(hirer);
        usd.approve(address(rail), budget);
        uint256 jobId = rail.hire(1, provider, budget, uint64(block.timestamp + TTL), keccak256("f"), "fuzz", mode);
        vm.stopPrank();
        deliver(jobId);

        if (path == 0) {
            vm.prank(hirer);
            rail.accept(jobId);
            assertEq(usd.balanceOf(provider), budget, "provider paid in full");
        } else if (path == 1) {
            vm.prank(hirer);
            rail.rejectWork(jobId);
            assertEq(usd.balanceOf(hirer), 1_000e18, "refunded in full");
        } else if (path == 2) {
            vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
            rail.settle(jobId, "");
            assertEq(usd.balanceOf(provider), budget, "provider paid in full");
        } else {
            policyContract.dispute(jobId);
            vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
            rail.settle(jobId, "");
            assertEq(usd.balanceOf(hirer), 1_000e18, "refunded in full");
        }

        assertEq(usd.balanceOf(address(rail)), 0, "rail empty");
        assertEq(usd.allowance(address(rail), address(kernel)), 0, "no standing approval");
    }

    function test_protected_hire_refuses_a_deadline_inside_the_dispute_window() public {
        // The mock policy uses a one hour window, so a thirty minute job
        // could never settle: it would expire first.
        vm.startPrank(hirer);
        usd.approve(address(rail), 1e18);
        vm.expectRevert(HireRail.DeadlineTooSoon.selector);
        rail.hire(1, provider, 1e18, uint64(block.timestamp + 30 minutes), keccak256("s"), "d", HireRail.Mode.Protected);
        // The same deadline is fine for a direct job, which settles on
        // acceptance rather than on a timer.
        rail.hire(1, provider, 1e18, uint64(block.timestamp + 30 minutes), keccak256("s"), "d", HireRail.Mode.Direct);
        vm.stopPrank();
    }

    function test_rail_reports_the_window_it_is_bound_to() public view {
        assertEq(rail.disputeWindow(), DISPUTE_WINDOW, "window read from the policy at deploy");
    }
}

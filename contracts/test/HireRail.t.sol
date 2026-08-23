// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HireRail} from "../src/HireRail.sol";
import {IAgenticCommerce} from "../src/interfaces/IAgenticCommerce.sol";
import {MockKernel, MockPolicy, MockRouter, MockUSD} from "./mocks/Mocks.sol";

contract HireRailTest is Test {
    MockUSD usd;
    MockKernel kernel;
    MockPolicy policyContract;
    MockRouter router;
    HireRail rail;

    uint64 constant DISPUTE_WINDOW = 1 hours;

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

    function test_settle_completes_the_job_and_pays_the_provider() public {
        uint256 jobId = hireOnce(5e18);
        vm.prank(provider);
        kernel.submit(jobId, keccak256("deliverable"), "");
        assertEq(uint8(kernel.getJob(jobId).status), uint8(IAgenticCommerce.JobStatus.Submitted));

        // Silence past the dispute window is approval.
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        // Permissionless: a stranger can push the payout through.
        vm.prank(stranger);
        rail.settle(jobId, "");

        assertEq(uint8(kernel.getJob(jobId).status), uint8(IAgenticCommerce.JobStatus.Completed));
        assertEq(usd.balanceOf(provider), 5e18, "provider paid from escrow");
        assertEq(usd.balanceOf(address(rail)), 0, "rail holds nothing");
    }

    function test_disputed_job_settles_back_to_the_hirer() public {
        uint256 jobId = hireOnce(5e18);
        vm.prank(provider);
        kernel.submit(jobId, keccak256("junk"), "");
        policyContract.dispute(jobId);
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        rail.settle(jobId, "");
        assertEq(uint8(kernel.getJob(jobId).status), uint8(IAgenticCommerce.JobStatus.Rejected));
        assertEq(usd.balanceOf(hirer), 1_000e18, "hirer made whole on rejection");
        assertEq(usd.balanceOf(provider), 0, "provider paid nothing");
    }

    function test_settle_reverts_before_the_dispute_window_closes() public {
        uint256 jobId = hireOnce(5e18);
        vm.prank(provider);
        kernel.submit(jobId, keccak256("d"), "");
        vm.expectRevert();
        rail.settle(jobId, "");
    }

    function test_settle_reverts_for_unknown_job() public {
        vm.expectRevert(HireRail.UnknownJob.selector);
        rail.settle(999, "");
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

    function test_forwardRefund_rescues_a_rejection_settled_outside_the_rail() public {
        uint256 jobId = hireOnce(5e18);
        vm.prank(provider);
        kernel.submit(jobId, keccak256("junk"), "");
        policyContract.dispute(jobId);
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);

        // Someone settles straight on the router, bypassing our rail. The
        // kernel refunds its client, which is the rail, so the money lands
        // here instead of with the person who paid.
        router.settle(jobId, "");
        assertEq(usd.balanceOf(address(rail)), 5e18, "escrow stranded on the rail");
        assertEq(usd.balanceOf(hirer), 995e18, "hirer not yet made whole");

        // Anyone may push it to the hirer, and only to the hirer.
        vm.prank(stranger);
        rail.forwardRefund(jobId);
        assertEq(usd.balanceOf(hirer), 1_000e18, "hirer made whole");
        assertEq(usd.balanceOf(address(rail)), 0, "rail holds nothing at rest");
        assertEq(usd.balanceOf(stranger), 0, "caller gains nothing");
    }

    function test_forwardRefund_cannot_run_twice() public {
        uint256 jobId = hireOnce(5e18);
        vm.prank(provider);
        kernel.submit(jobId, keccak256("junk"), "");
        policyContract.dispute(jobId);
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        router.settle(jobId, "");
        rail.forwardRefund(jobId);
        vm.expectRevert(HireRail.NothingToRefund.selector);
        rail.forwardRefund(jobId);
    }

    function test_forwardRefund_rejects_unknown_and_unfinished_jobs() public {
        vm.expectRevert(HireRail.UnknownJob.selector);
        rail.forwardRefund(999);

        uint256 jobId = hireOnce(5e18);
        // Still funded, so there is nothing to refund and no right to take.
        vm.expectRevert(HireRail.JobNotRefundable.selector);
        rail.forwardRefund(jobId);
    }

    function test_settle_after_rejection_returns_escrow_to_the_hirer() public {
        uint256 jobId = hireOnce(5e18);
        vm.prank(provider);
        kernel.submit(jobId, keccak256("junk"), "");
        policyContract.dispute(jobId);
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        // Through our rail this happens in one transaction, no rescue needed.
        rail.settle(jobId, "");
        assertEq(usd.balanceOf(hirer), 1_000e18, "hirer made whole in one step");
        assertEq(usd.balanceOf(address(rail)), 0, "rail holds nothing");
        assertTrue(rail.refundForwarded(jobId), "marked as forwarded");
    }

    /// The rail is a conduit, never a vault: whatever sequence runs, it must
    /// not be holding tokens once the transaction ends.
    function testFuzz_rail_never_holds_funds_at_rest(uint96 budget, bool disputeIt) public {
        budget = uint96(bound(budget, 1, 1_000e18));
        vm.startPrank(hirer);
        usd.approve(address(rail), budget);
        uint256 jobId =
            rail.hire(1, provider, budget, uint64(block.timestamp + 1 days), keccak256("f"), "fuzz");
        vm.stopPrank();

        vm.prank(provider);
        kernel.submit(jobId, keccak256("d"), "");
        if (disputeIt) policyContract.dispute(jobId);
        vm.warp(block.timestamp + DISPUTE_WINDOW + 1);
        rail.settle(jobId, "");

        assertEq(usd.balanceOf(address(rail)), 0, "rail empty");
        if (disputeIt) {
            assertEq(usd.balanceOf(hirer), 1_000e18, "refunded in full");
        } else {
            assertEq(usd.balanceOf(provider), budget, "provider paid in full");
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HireRail} from "../src/HireRail.sol";
import {IAgenticCommerce} from "../src/interfaces/IAgenticCommerce.sol";
import {IEvaluatorRouter} from "../src/interfaces/IEvaluatorRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// Integration tests against the REAL ERC-8183 deployment on BSC mainnet,
/// run over a fork. These prove HireRail works against actual deployed
/// bytecode rather than a mock, which is the only way to catch the kernel's
/// undocumented requirements (the router must be both evaluator and hook,
/// and only the job's client may bind the policy).
///
/// Run with:
///   BSC_FORK_RPC=<archive capable rpc> forge test --match-contract HireRailFork
/// Skipped automatically when BSC_FORK_RPC is not set, so the default suite
/// and CI stay offline.
contract HireRailForkTest is Test {
    address constant KERNEL = 0xEa4DAa3100A767e86FDed867729ae7446476EBA6;
    address constant ROUTER = 0x51895229E12F9876011789B04f8698af06cCD6DA;
    address constant POLICY = 0x9C01845705b3078Aa2e8cfF7520a6376FD766dE5;
    address constant U_TOKEN = 0xcE24439F2D9C6a2289F741120FE202248B666666;

    HireRail rail;
    IERC20 u;
    address hirer = makeAddr("hirer");
    address provider = makeAddr("provider");

    bool forked;

    function setUp() public {
        string memory rpc = vm.envOr("BSC_FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        forked = true;

        rail = new HireRail(KERNEL, ROUTER, POLICY);
        u = IERC20(U_TOKEN);
        deal(U_TOKEN, hirer, 100e18);
    }

    modifier onlyForked() {
        if (!forked) return;
        _;
    }

    function test_fork_wiring_matches_the_live_deployment() public view onlyForked {
        // The rail reads the payment token straight off the kernel.
        assertEq(address(rail.token()), U_TOKEN, "payment token");
        assertEq(address(rail.kernel()), KERNEL, "kernel");
        assertEq(address(rail.router()), ROUTER, "router");
        // The policy we bind must actually be whitelisted on the live router,
        // or every hire would revert with PolicyNotWhitelisted.
        assertTrue(IEvaluatorRouter(ROUTER).policyWhitelist(POLICY), "policy whitelisted");
    }

    function test_fork_hire_funds_a_real_job_on_the_live_kernel() public onlyForked {
        uint256 counterBefore = IAgenticCommerce(KERNEL).jobCounter();

        vm.startPrank(hirer);
        u.approve(address(rail), 5e18);
        uint256 jobId =
            rail.hire(12345, provider, 5e18, uint64(block.timestamp + 1 days), keccak256("spec"), "fork test hire");
        vm.stopPrank();

        // The live kernel minted the next job id in sequence.
        assertEq(jobId, counterBefore + 1, "job id follows the live counter");

        IAgenticCommerce.Job memory job = IAgenticCommerce(KERNEL).getJob(jobId);
        assertEq(uint8(job.status), uint8(IAgenticCommerce.JobStatus.Funded), "funded");
        assertEq(job.budget, 5e18, "budget");
        assertEq(job.provider, provider, "provider");
        assertEq(job.client, address(rail), "rail is the client");
        // The live router enforces both of these; if either drifts, hire reverts.
        assertEq(job.evaluator, ROUTER, "router is evaluator");
        assertEq(job.hook, ROUTER, "router is hook");

        // The policy is bound on the live router, so settlement can decide.
        assertEq(IEvaluatorRouter(ROUTER).jobPolicy(jobId), POLICY, "policy bound");

        // The rail keeps nothing and leaves no standing approval.
        assertEq(u.balanceOf(address(rail)), 0, "rail holds no funds");
        assertEq(u.allowance(address(rail), KERNEL), 0, "no standing approval");

        // The hirer paid exactly the budget.
        assertEq(u.balanceOf(hirer), 95e18, "hirer debited exactly");

        // Our own bookkeeping survives.
        assertEq(rail.hirerOf(jobId), hirer, "hirer recorded");
        assertEq(rail.agentOf(jobId), 12345, "agent id recorded");
    }

    function test_fork_reclaim_returns_escrow_to_the_hirer_after_expiry() public onlyForked {
        vm.startPrank(hirer);
        u.approve(address(rail), 3e18);
        uint256 jobId =
            rail.hire(7, provider, 3e18, uint64(block.timestamp + 1 hours), keccak256("spec"), "fork expiry test");
        vm.stopPrank();

        assertEq(u.balanceOf(hirer), 97e18, "escrowed");

        // Past the deadline, anyone may push the reclaim and only the hirer
        // can receive the funds.
        vm.warp(block.timestamp + 2 hours);
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        rail.reclaim(jobId);

        assertEq(u.balanceOf(hirer), 100e18, "hirer made whole");
        assertEq(u.balanceOf(address(rail)), 0, "rail holds nothing");
        assertEq(u.balanceOf(stranger), 0, "caller gains nothing");
    }

    function test_fork_hire_reverts_when_paused_and_reclaim_still_works() public onlyForked {
        vm.startPrank(hirer);
        u.approve(address(rail), 2e18);
        uint256 jobId = rail.hire(9, provider, 2e18, uint64(block.timestamp + 1 hours), keccak256("s"), "pause test");
        vm.stopPrank();

        rail.pause();

        vm.startPrank(hirer);
        u.approve(address(rail), 1e18);
        vm.expectRevert();
        rail.hire(9, provider, 1e18, uint64(block.timestamp + 1 hours), keccak256("s"), "blocked");
        vm.stopPrank();

        // Pausing must never trap an existing escrow.
        vm.warp(block.timestamp + 2 hours);
        rail.reclaim(jobId);
        assertEq(u.balanceOf(hirer), 100e18, "escrow recoverable while paused");
    }
}

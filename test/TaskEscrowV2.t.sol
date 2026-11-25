// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { TaskEscrowV2 } from "../src/TaskEscrowV2.sol";
import { MockProxy } from "./Mocks.sol";

contract TaskEscrowV2Test is Test {
    TaskEscrowV2 esc;
    MockProxy proxy;
    address reactive = address(0xBEEF);
    address oracle = address(0x0A);
    address poster = address(0x1);
    address worker = address(0x2);
    uint64 dl;

    function setUp() public {
        proxy = new MockProxy();
        esc = new TaskEscrowV2(IPayable(payable(address(proxy))), reactive, oracle);
        vm.deal(poster, 10 ether);
        dl = uint64(block.timestamp + 1 days);
    }

    function _post() internal returns (uint256 id) {
        vm.prank(poster);
        id = esc.postTask{ value: 1 ether }("case", dl);
    }

    function test_approveAndPayout() public {
        uint256 id = _post();
        vm.prank(worker); esc.submitProof(id, "ipfs://proof");
        vm.prank(oracle); esc.postVerdict(id, true, "ok");
        vm.prank(address(proxy)); esc.releaseCallback(reactive, id);
        assertEq(worker.balance, 1 ether);
    }

    function test_rejectRefundsPoster() public {
        uint256 id = _post();
        vm.prank(worker); esc.submitProof(id, "x");
        vm.prank(oracle); esc.postVerdict(id, false, "no");
        uint256 before = poster.balance;
        vm.prank(address(proxy)); esc.releaseCallback(reactive, id);
        assertEq(poster.balance, before + 1 ether);
    }

    function test_onlyOracleCanPostVerdict() public {
        uint256 id = _post();
        vm.prank(worker); esc.submitProof(id, "x");
        vm.expectRevert("not oracle");
        vm.prank(worker); esc.postVerdict(id, true, "I approve myself");
    }

    function test_releaseOnlyViaProxyAndAuthorizedReactive() public {
        uint256 id = _post();
        vm.prank(worker); esc.submitProof(id, "x");
        vm.prank(oracle); esc.postVerdict(id, true, "ok");
        vm.expectRevert(); // not the proxy
        esc.releaseCallback(reactive, id);
        vm.expectRevert(); // proxy, but a foreign reactive contract
        vm.prank(address(proxy)); esc.releaseCallback(address(0xBAD), id);
    }

    function test_noDoubleSettle() public {
        uint256 id = _post();
        vm.prank(worker); esc.submitProof(id, "x");
        vm.prank(oracle); esc.postVerdict(id, true, "ok");
        vm.startPrank(address(proxy));
        esc.releaseCallback(reactive, id);
        vm.expectRevert("already settled");
        esc.releaseCallback(reactive, id);
        vm.stopPrank();
    }

    function test_oversizedProofRejected() public {
        uint256 id = _post();
        bytes memory big = new bytes(513);
        for (uint256 i = 0; i < big.length; i++) big[i] = "a";
        vm.expectRevert("proof too long");
        vm.prank(worker); esc.submitProof(id, string(big));
    }

    function test_oversizedRationaleRejected() public {
        uint256 id = _post();
        vm.prank(worker); esc.submitProof(id, "x");
        bytes memory big = new bytes(281);
        for (uint256 i = 0; i < big.length; i++) big[i] = "a";
        vm.expectRevert("rationale too long");
        vm.prank(oracle); esc.postVerdict(id, true, string(big));
    }

    function test_reclaimAfterDeadlineRefundsPoster() public {
        uint256 id = _post();
        vm.warp(dl + 1);
        uint256 before = poster.balance;
        vm.prank(address(proxy)); esc.reclaimCallback(reactive, id);
        assertEq(poster.balance, before + 1 ether);
        (, , , , , bool settled, , ) = esc.tasks(id);
        assertTrue(settled);
    }

    function test_reclaimBeforeDeadlineReverts() public {
        uint256 id = _post();
        vm.expectRevert("not expired");
        vm.prank(address(proxy)); esc.reclaimCallback(reactive, id);
    }

    function test_reclaimBlockedWhenVerdictExists() public {
        uint256 id = _post();
        vm.prank(worker); esc.submitProof(id, "x");
        vm.prank(oracle); esc.postVerdict(id, true, "ok");
        vm.warp(dl + 1);
        vm.expectRevert("verdict exists");
        vm.prank(address(proxy)); esc.reclaimCallback(reactive, id);
    }

    function test_reclaimOnlyViaProxy() public {
        uint256 id = _post();
        vm.warp(dl + 1);
        vm.expectRevert();
        esc.reclaimCallback(reactive, id);
    }

    function test_noProofAfterDeadlineAndNoReclaimDoubleSpend() public {
        uint256 id = _post();
        vm.warp(dl + 1);
        vm.expectRevert("past deadline");
        vm.prank(worker); esc.submitProof(id, "late");
        vm.startPrank(address(proxy));
        esc.reclaimCallback(reactive, id);
        vm.expectRevert("already settled");
        esc.reclaimCallback(reactive, id);
        vm.stopPrank();
    }

    function test_deadlineMustBeFuture() public {
        vm.expectRevert("deadline in past");
        vm.prank(poster); esc.postTask{ value: 1 }("c", uint64(block.timestamp));
    }
}

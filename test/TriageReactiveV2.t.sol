// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { TriageReactiveV2 } from "../src/TriageReactiveV2.sol";
import { MockSystem } from "./Mocks.sol";

contract TriageReactiveV2Test is Test {
    address constant SYS = 0x8888888888888888888888888888888888888888;
    uint256 constant CRON_CHAIN = 5318007;
    address constant CRON_SRC = 0x0000000000000000000000000000000000fffFfF;
    address origin = address(0x0123);
    uint256 constant TASK_POSTED = 0x07a7ad2995feeb03a572f005b634b4c456fc4128cafd3ba8ee2b6d4f36e56732;
    uint256 constant VERDICT = 0x412180369940e41621d1853ecfbe63371cbe9a11d01c1101ea27452efb50edfd;
    uint256 constant CRON1000 = 0xe20b31294d84c3661ddc8f423abb9c70310d0cf172aa2714ead78029b325e3f4;

    TriageReactiveV2 r;
    MockSystem sys;

    function setUp() public {
        vm.etch(SYS, address(new MockSystem()).code);
        sys = MockSystem(payable(SYS));
        r = new TriageReactiveV2(origin, CRON_CHAIN);
    }

    function _log(uint256 chain, address src, uint256 t0, uint256 t1, bytes memory data)
        internal pure returns (IReactive.LogRecord memory)
    {
        return IReactive.LogRecord(chain, src, t0, t1, 0, 0, data, 1, 0, 0, 0, 0);
    }

    function _posted(uint256 id, uint64 dl) internal {
        vm.prank(SYS);
        r.react(_log(84532, origin, TASK_POSTED, id, abi.encode(uint256(1 ether), dl, "case")));
    }

    function _cron() internal {
        vm.prank(SYS);
        r.react(_log(CRON_CHAIN, CRON_SRC, CRON1000, 0, abi.encode(block.number)));
    }

    function test_subscribesToFourTopics() public view {
        assertEq(sys.subscriptions(), 4);
    }

    function test_reactOnlyFromSystem() public {
        vm.expectRevert();
        r.react(_log(84532, origin, TASK_POSTED, 0, abi.encode(uint256(1), uint64(1), "c")));
    }

    function test_tracksTaskAndReclaimsOnCronAfterDeadline() public {
        _posted(0, uint64(block.timestamp + 1 hours));
        assertEq(r.openCount(), 1);
        _cron(); // before deadline: nothing
        assertEq(sys.cbCount(), 0);
        vm.warp(block.timestamp + 2 hours);
        _cron();
        assertEq(sys.cbCount(), 1);
        bytes memory p = sys.payloadAt(0);
        bytes4 sel; assembly { sel := mload(add(p, 32)) }
        assertEq(sel, bytes4(keccak256("reclaimCallback(address,uint256)")));
        assertEq(r.openCount(), 0);
        _cron(); // no repeat
        assertEq(sys.cbCount(), 1);
    }

    function test_verdictClosesTaskSoNoReclaim() public {
        _posted(7, uint64(block.timestamp + 1 hours));
        vm.prank(SYS);
        r.react(_log(84532, origin, VERDICT, 7, abi.encode(uint8(1), "ok")));
        assertEq(sys.cbCount(), 1); // settlement callback
        assertEq(r.openCount(), 0);
        vm.warp(block.timestamp + 2 hours);
        _cron();
        assertEq(sys.cbCount(), 1); // still just the settlement
    }

    function test_ignoresForeignOriginAndWrongCronSource() public {
        vm.prank(SYS);
        r.react(_log(84532, address(0x999), TASK_POSTED, 1, abi.encode(uint256(1), uint64(5), "c")));
        assertEq(r.openCount(), 0);
        _posted(1, uint64(block.timestamp + 1));
        vm.warp(block.timestamp + 10);
        vm.prank(SYS);
        r.react(_log(1, address(0x1), CRON1000, 0, "")); // wrong chain and source
        assertEq(sys.cbCount(), 0);
    }

    function test_scanIsBoundedPerTick() public {
        for (uint256 i = 0; i < 25; i++) _posted(i, uint64(block.timestamp + 1));
        vm.warp(block.timestamp + 10);
        _cron();
        assertEq(sys.cbCount(), r.MAX_SCAN());
        _cron(); _cron();
        assertEq(sys.cbCount(), 25);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title TriageReactiveV2 - V1 flow plus a cron-driven deadline reclaim.
/// @notice Same ProofSubmitted -> CaseFiled and VerdictPosted -> settlement
///         callback as V1. Adds: it learns each task's deadline from
///         TaskPosted, and on every Cron1000 tick (about 17 minutes on Lasna)
///         scans a bounded batch of open tasks and requests
///         `reclaimCallback` for any whose deadline passed with no verdict.
contract TriageReactiveV2 is AbstractReactive {
    uint256 public constant ORIGIN_CHAIN_ID = 84532; // Base Sepolia
    uint256 public constant DEST_CHAIN_ID = 84532;
    /// @dev The system contract that emits Cron events on Lasna.
    address public constant CRON_SOURCE = 0x0000000000000000000000000000000000fffFfF;

    uint256 private constant TASK_POSTED_TOPIC =
        0x07a7ad2995feeb03a572f005b634b4c456fc4128cafd3ba8ee2b6d4f36e56732;
    uint256 private constant PROOF_SUBMITTED_TOPIC =
        0xb2217a1ebc8d6435d328a4607aa9709269fe4cb393535a1675721d8431a54018;
    uint256 private constant VERDICT_POSTED_TOPIC =
        0x412180369940e41621d1853ecfbe63371cbe9a11d01c1101ea27452efb50edfd;
    uint256 private constant CRON1000_TOPIC =
        0xe20b31294d84c3661ddc8f423abb9c70310d0cf172aa2714ead78029b325e3f4;

    uint64 private constant CALLBACK_GAS_LIMIT = 1_000_000;
    uint256 public constant MAX_SCAN = 10; // bounded work per cron tick

    address public immutable ORIGIN;
    uint256 public immutable CRON_CHAIN_ID;

    mapping(uint256 => uint64) public deadlineOf;
    uint256[] public openIds;
    uint256 public cursor;

    event CaseFiled(uint256 indexed taskId, address indexed worker, string proofRef);
    event SettlementRequested(uint256 indexed taskId);
    event ReclaimRequested(uint256 indexed taskId, uint64 deadline);

    constructor(address origin_, uint256 cronChainId_) payable {
        ORIGIN = origin_;
        CRON_CHAIN_ID = cronChainId_;
        SYSTEM.subscribe(ORIGIN_CHAIN_ID, origin_, TASK_POSTED_TOPIC, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
        SYSTEM.subscribe(ORIGIN_CHAIN_ID, origin_, PROOF_SUBMITTED_TOPIC, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
        SYSTEM.subscribe(ORIGIN_CHAIN_ID, origin_, VERDICT_POSTED_TOPIC, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
        SYSTEM.subscribe(cronChainId_, CRON_SOURCE, CRON1000_TOPIC, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE);
    }

    function openCount() external view returns (uint256) {
        return openIds.length;
    }

    /// @inheritdoc IReactive
    function react(LogRecord calldata log_) external onlySystem {
        if (log_.topic0 == CRON1000_TOPIC) {
            if (log_.chainId == CRON_CHAIN_ID && log_.contractAddress == CRON_SOURCE) {
                _scan();
            }
        } else if (log_.chainId == ORIGIN_CHAIN_ID && log_.contractAddress == ORIGIN) {
            if (log_.topic0 == TASK_POSTED_TOPIC) {
                (, uint64 deadline) = abi.decode(log_.data, (uint256, uint64));
                deadlineOf[log_.topic1] = deadline;
                openIds.push(log_.topic1);
            } else if (log_.topic0 == PROOF_SUBMITTED_TOPIC) {
                address worker = address(uint160(log_.topic2));
                string memory proofRef = abi.decode(log_.data, (string));
                emit CaseFiled(log_.topic1, worker, proofRef);
            } else if (log_.topic0 == VERDICT_POSTED_TOPIC) {
                uint256 taskId = log_.topic1;
                _close(taskId); // a verdict exists: reclaim no longer applies
                _callback("releaseCallback(address,uint256)", taskId);
                emit SettlementRequested(taskId);
            }
        }
        _coverDebt();
    }

    function _scan() internal {
        uint256 n = openIds.length;
        if (n == 0) return;
        uint256 steps = n < MAX_SCAN ? n : MAX_SCAN;
        for (uint256 i = 0; i < steps; i++) {
            n = openIds.length;
            if (n == 0) break;
            if (cursor >= n) cursor = 0;
            uint256 taskId = openIds[cursor];
            uint64 dl = deadlineOf[taskId];
            if (dl != 0 && block.timestamp >= dl) {
                _close(taskId); // swap-removes, so the same cursor slot holds a new id
                _callback("reclaimCallback(address,uint256)", taskId);
                emit ReclaimRequested(taskId, dl);
            } else {
                cursor++;
            }
        }
    }

    function _close(uint256 taskId) internal {
        if (deadlineOf[taskId] == 0) return;
        deadlineOf[taskId] = 0;
        uint256 n = openIds.length;
        for (uint256 i = 0; i < n; i++) {
            if (openIds[i] == taskId) {
                openIds[i] = openIds[n - 1];
                openIds.pop();
                return;
            }
        }
    }

    function _callback(string memory sig, uint256 taskId) internal {
        bytes memory payload = abi.encodeWithSelector(bytes4(keccak256(bytes(sig))), address(this), taskId);
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: DEST_CHAIN_ID,
                recipient: ORIGIN,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title TriageReactive - reactive contract on Reactive Lasna testnet.
/// @notice Watches TaskEscrow on Base Sepolia. Every ProofSubmitted event
///         becomes a CaseFiled record on Lasna that the off-chain AI triage
///         agent picks up. When the oracle's VerdictPosted event lands, this
///         contract requests the settlement callback back on Base Sepolia.
contract TriageReactive is AbstractReactive {
    uint256 public constant ORIGIN_CHAIN_ID = 84532; // Base Sepolia
    uint256 public constant DEST_CHAIN_ID = 84532;

    uint256 private constant PROOF_SUBMITTED_TOPIC =
        0xb2217a1ebc8d6435d328a4607aa9709269fe4cb393535a1675721d8431a54018;
    uint256 private constant VERDICT_POSTED_TOPIC =
        0x412180369940e41621d1853ecfbe63371cbe9a11d01c1101ea27452efb50edfd;

    uint64 private constant CALLBACK_GAS_LIMIT = 1_000_000;

    /// @notice TaskEscrow address on Base Sepolia.
    address public immutable ORIGIN;

    /// @notice Filed on Lasna for each submitted proof; consumed by the AI agent.
    event CaseFiled(uint256 indexed taskId, address indexed worker, string proofRef);

    /// @notice Marks that settlement was requested for a task.
    event SettlementRequested(uint256 indexed taskId);

    constructor(address origin_) payable {
        ORIGIN = origin_;
        SYSTEM.subscribe(
            ORIGIN_CHAIN_ID,
            origin_,
            PROOF_SUBMITTED_TOPIC,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        SYSTEM.subscribe(
            ORIGIN_CHAIN_ID,
            origin_,
            VERDICT_POSTED_TOPIC,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /// @inheritdoc IReactive
    function react(LogRecord calldata log_) external onlySystem {
        if (log_.chainId != ORIGIN_CHAIN_ID || log_.contractAddress != ORIGIN) {
            return;
        }
        if (log_.topic0 == PROOF_SUBMITTED_TOPIC) {
            uint256 taskId = log_.topic1;
            address worker = address(uint160(log_.topic2));
            string memory proofRef = abi.decode(log_.data, (string));
            emit CaseFiled(taskId, worker, proofRef);
        } else if (log_.topic0 == VERDICT_POSTED_TOPIC) {
            uint256 taskId = log_.topic1;
            bytes memory payload = abi.encodeWithSelector(
                bytes4(keccak256("releaseCallback(address,uint256)")),
                address(this),
                taskId
            );
            SYSTEM.requestCallbackV_1_0(
                ISystemContract.CallbackConfiguration_V_1_0({
                    chainId: DEST_CHAIN_ID,
                    recipient: ORIGIN,
                    gasLimit: CALLBACK_GAS_LIMIT,
                    payload: payload
                })
            );
            emit SettlementRequested(taskId);
        }
        _coverDebt();
    }
}

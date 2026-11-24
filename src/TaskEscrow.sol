// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

/// @title TaskEscrow - origin/callback contract on Base Sepolia.
/// @notice Posters escrow funds for small work tasks. Workers submit proof.
///         An off-chain AI oracle posts a verdict; the Reactive Network
///         callback then settles the escrow autonomously.
contract TaskEscrow is AbstractCallback {
    enum Verdict { Pending, Approved, Rejected }

    struct Task {
        address poster;
        address worker;
        uint256 amount;
        Verdict verdict;
        bool settled;
        string caseRef;
        string proofRef;
    }

    uint256 public nextTaskId;
    mapping(uint256 => Task) public tasks;

    /// @notice EOA of the off-chain AI agent allowed to post verdicts.
    address public immutable ORACLE;

    event TaskPosted(uint256 indexed taskId, address indexed poster, uint256 amount, string caseRef);
    event ProofSubmitted(uint256 indexed taskId, address indexed worker, string proofRef);
    event VerdictPosted(uint256 indexed taskId, uint8 verdict, string rationale);
    event PayoutReleased(uint256 indexed taskId, address indexed worker, uint256 amount);
    event RefundReleased(uint256 indexed taskId, address indexed poster, uint256 amount);

    constructor(IPayable callbackProxy_, address callbackSender_, address oracle_)
        payable
        AbstractCallback(callbackProxy_, callbackSender_)
    {
        ORACLE = oracle_;
    }

    function postTask(string calldata caseRef_) external payable returns (uint256 taskId) {
        require(msg.value > 0, "no escrow");
        taskId = nextTaskId++;
        tasks[taskId] = Task({
            poster: msg.sender,
            worker: address(0),
            amount: msg.value,
            verdict: Verdict.Pending,
            settled: false,
            caseRef: caseRef_,
            proofRef: ""
        });
        emit TaskPosted(taskId, msg.sender, msg.value, caseRef_);
    }

    function submitProof(uint256 taskId_, string calldata proofRef_) external {
        Task storage t = tasks[taskId_];
        require(t.poster != address(0), "unknown task");
        require(!t.settled && t.verdict == Verdict.Pending, "task closed");
        t.worker = msg.sender;
        t.proofRef = proofRef_;
        emit ProofSubmitted(taskId_, msg.sender, proofRef_);
    }

    function postVerdict(uint256 taskId_, bool approved_, string calldata rationale_) external {
        require(msg.sender == ORACLE, "not oracle");
        Task storage t = tasks[taskId_];
        require(t.poster != address(0), "unknown task");
        require(t.worker != address(0), "no proof yet");
        require(!t.settled && t.verdict == Verdict.Pending, "task closed");
        t.verdict = approved_ ? Verdict.Approved : Verdict.Rejected;
        emit VerdictPosted(taskId_, approved_ ? 1 : 2, rationale_);
    }

    /// @notice Settlement entry point, driven exclusively by the Reactive
    ///         Network callback proxy on behalf of the authorized reactive
    ///         contract. First argument is overwritten by the proxy with the
    ///         reactive contract address.
    function releaseCallback(address reactive_, uint256 taskId_)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        Task storage t = tasks[taskId_];
        require(t.poster != address(0), "unknown task");
        require(!t.settled, "already settled");
        require(t.verdict != Verdict.Pending, "no verdict");
        t.settled = true;
        if (t.verdict == Verdict.Approved) {
            (bool ok, ) = payable(t.worker).call{ value: t.amount }("");
            require(ok, "payout failed");
            emit PayoutReleased(taskId_, t.worker, t.amount);
        } else {
            (bool ok, ) = payable(t.poster).call{ value: t.amount }("");
            require(ok, "refund failed");
            emit RefundReleased(taskId_, t.poster, t.amount);
        }
        _coverDebt();
    }
}

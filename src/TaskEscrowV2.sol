// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

/// @title TaskEscrowV2 - escrow with a deadline and an autonomous reclaim path.
/// @notice V1 settles only when the AI oracle posts a verdict. V2 adds:
///         - a per-task deadline,
///         - `reclaimCallback`, driven by a Reactive cron, which refunds the
///           poster if no verdict arrived in time (a dead or stalled oracle
///           can no longer lock funds),
///         - hard size limits on untrusted text (proof reference, rationale),
///           part of the prompt-injection defense: oversized payloads are
///           rejected on-chain before any AI ever sees them.
contract TaskEscrowV2 is AbstractCallback {
    enum Verdict { Pending, Approved, Rejected }

    struct Task {
        address poster;
        address worker;
        uint256 amount;
        uint64 deadline;
        Verdict verdict;
        bool settled;
        string caseRef;
        string proofRef;
    }

    uint256 public constant MAX_PROOF_BYTES = 512;
    uint256 public constant MAX_RATIONALE_BYTES = 280;

    uint256 public nextTaskId;
    mapping(uint256 => Task) public tasks;

    address public immutable ORACLE;

    event TaskPosted(uint256 indexed taskId, address indexed poster, uint256 amount, uint64 deadline, string caseRef);
    event ProofSubmitted(uint256 indexed taskId, address indexed worker, string proofRef);
    event VerdictPosted(uint256 indexed taskId, uint8 verdict, string rationale);
    event PayoutReleased(uint256 indexed taskId, address indexed worker, uint256 amount);
    event RefundReleased(uint256 indexed taskId, address indexed poster, uint256 amount);
    event DeadlineReclaimed(uint256 indexed taskId, address indexed poster, uint256 amount);

    constructor(IPayable callbackProxy_, address callbackSender_, address oracle_)
        payable
        AbstractCallback(callbackProxy_, callbackSender_)
    {
        ORACLE = oracle_;
    }

    function postTask(string calldata caseRef_, uint64 deadline_) external payable returns (uint256 taskId) {
        require(msg.value > 0, "no escrow");
        require(deadline_ > block.timestamp, "deadline in past");
        taskId = nextTaskId++;
        tasks[taskId] = Task({
            poster: msg.sender,
            worker: address(0),
            amount: msg.value,
            deadline: deadline_,
            verdict: Verdict.Pending,
            settled: false,
            caseRef: caseRef_,
            proofRef: ""
        });
        emit TaskPosted(taskId, msg.sender, msg.value, deadline_, caseRef_);
    }

    function submitProof(uint256 taskId_, string calldata proofRef_) external {
        Task storage t = tasks[taskId_];
        require(t.poster != address(0), "unknown task");
        require(!t.settled && t.verdict == Verdict.Pending, "task closed");
        require(block.timestamp < t.deadline, "past deadline");
        require(bytes(proofRef_).length <= MAX_PROOF_BYTES, "proof too long");
        t.worker = msg.sender;
        t.proofRef = proofRef_;
        emit ProofSubmitted(taskId_, msg.sender, proofRef_);
    }

    function postVerdict(uint256 taskId_, bool approved_, string calldata rationale_) external {
        require(msg.sender == ORACLE, "not oracle");
        require(bytes(rationale_).length <= MAX_RATIONALE_BYTES, "rationale too long");
        Task storage t = tasks[taskId_];
        require(t.poster != address(0), "unknown task");
        require(t.worker != address(0), "no proof yet");
        require(!t.settled && t.verdict == Verdict.Pending, "task closed");
        t.verdict = approved_ ? Verdict.Approved : Verdict.Rejected;
        emit VerdictPosted(taskId_, approved_ ? 1 : 2, rationale_);
    }

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

    /// @notice Refund the poster when the deadline passed with no verdict.
    ///         Driven by the Reactive cron, never by a human.
    function reclaimCallback(address reactive_, uint256 taskId_)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        Task storage t = tasks[taskId_];
        require(t.poster != address(0), "unknown task");
        require(!t.settled, "already settled");
        require(t.verdict == Verdict.Pending, "verdict exists");
        require(block.timestamp >= t.deadline, "not expired");
        t.settled = true;
        (bool ok, ) = payable(t.poster).call{ value: t.amount }("");
        require(ok, "reclaim failed");
        emit DeadlineReclaimed(taskId_, t.poster, t.amount);
        _coverDebt();
    }
}

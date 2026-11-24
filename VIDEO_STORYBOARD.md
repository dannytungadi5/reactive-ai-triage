# Demo video storyboard (< 3 min) — AI Signal Triage

Target: 2:00-2:30. Screen recording, terminal + explorers side by side, voice-over or captions (English, judges are international).

1. (0:00-0:15) Problem: "Escrows and bounties need a human to judge work and click release. Here the judge is an AI, and its decision executes on-chain by itself via Reactive Network."
2. (0:15-0:35) Architecture on one slide/diagram (README loop diagram): TaskEscrow on Base Sepolia, TriageReactive on Lasna, off-chain AI agent (Gemma 4 31B). Emphasize: AI is IN the running system, not a build tool.
3. (0:35-1:20) APPROVED path live: terminal runs demo.sh (postTask + submitProof). Show agent log picking up CaseFiled from Lasna, LLM verdict APPROVE + rationale, postVerdict tx. Then reactscan/basescan: CaseFiled tx, SettlementRequested, PayoutReleased. Callout: "Nobody clicked release. The reactive contract saw the verdict and the callback proxy paid the worker."
4. (1:20-1:50) REJECTED path (sped up): junk proof -> AI REJECT -> RefundReleased. "Bad work gets refunded automatically."
5. (1:50-2:10) Numbers: 2 contracts, 2 chains, 6 txs per loop, all hashes in README, repo link. Close: "AI judges, Reactive executes."

Recording plan: run task #2 live during recording (faucet headroom needed for escrow; ~0.001 ETH left on origin — one more zalalena claim covers re-takes).

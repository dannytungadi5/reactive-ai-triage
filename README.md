# Juryloop — Reactive Meets AI

[![ci](https://github.com/dannytungadi5/reactive-ai-triage/actions/workflows/ci.yml/badge.svg)](https://github.com/dannytungadi5/reactive-ai-triage/actions/workflows/ci.yml)

> **Juryloop** (formerly "Reactive AI Triage"). The judge is an AI. The settlement is on-chain. Contract names such as `TriageReactiveV2` keep their original names.

An escrow where the adjudicator is an AI, and its decision executes on-chain
autonomously through Reactive Network. No human clicks "release".

Built for the **Reactive Omni Buildathon**, track **Reactive Meets AI**.
The AI is not a build tool here — it is a component of the running system:
every case is filed on-chain, judged by an LLM, and settled by a
reactive-network callback.

**Landing page:** https://juryloop.pages.dev/

**Demo video (1:26):** https://youtu.be/wjCjA7In4wg

## Second live run (post-launch pilot, builder-operated wallets)

Run on 27 Nov 2026 on the V2 pair. Honesty note: the poster and both workers
are three wallets operated by the builder, not outside users. Every step is a
public transaction on Base Sepolia (TaskEscrowV2, `0x753D14dA407EFb32B2D64A1bE21cb2e13aBFA897`):

| Task | Case | Post | Proof | Verdict | Settlement |
|---|---|---|---|---|---|
| 12 | Good proof (3-bullet summary) | `0xdbe8098f9ed2ee938cb5daec1ee5d0b5a25c2cc54497d759d81ae695a087703c` | `0x06c26dc771515032b31f913f62aadab00384081710da8edcdd36a79dda428df0` | APPROVE `0xabb2512191e3c8c912aee90cbc2d7cf5acac990e285506e3b8af1dec4ffba680` | PayoutReleased `0x95cb3ef4af4e645032d3736d635a2e0e4b10c7c35f930581389db049f56df071` |
| 13 | Prompt-injection proof | `0xe704472107e889a08a83f9f328948f1ff3d2d2acea4318b1a6db8373b0260b45` | `0x2c030d04dd284ba08a0c44ea7bfe432c1d144154b1f6679b2c778f12b7ee600a` | REJECT `0x13fa4cfbbc849d053b8c28e3c5daad88fee0ddeb8d08642d7e7db665c1abc30d` | RefundReleased `0xcd52bdf6205d1e0eb3e2a6aa9218b9f83e36712832ab9adf6dc6edae00e87489` |

Earlier pilot tasks lost their events while the reactive contract was in
REACT debt (events during debt are not replayed). Debt was repaid with
`depositTo` and the cases were re-posted as tasks 12 and 13 above.

## Why this entry

1. **The AI is inside the loop, not beside it.** A Gemma 4 31B agent is the
   adjudicator of a live escrow: its verdict is a transaction, and money
   moves on it without any human in the path.
2. **The full Reactive story in one flow.** Cross-chain event (Base Sepolia)
   -> reactive contract (Lasna) -> off-chain AI verdict -> Reactive callback
   settles the escrow back on Base Sepolia. Two chains, three actors, zero
   clicks — and both outcomes proven (payout on approve, refund on reject).
3. **It was actually run, and it shows.** Three complete loops on public
   testnets with every tx hash below, including the failure mode nobody puts
   in a demo: a reactive contract in debt silently stops receiving events
   (task #2), diagnosed and fixed live via `depositTo` (task #4).

## The loop

```
poster                worker               Lasna (Reactive)            origin chain
  | postTask(ETH)       |                       |                           |
  |-------------------> TaskEscrow              |                           |
  |                     | submitProof           |                           |
  |                     |---------------------> [ProofSubmitted event]      |
  |                     |                       | react()                   |
  |                     |                       |---> CaseFiled (on Lasna)  |
  |                     |            AI agent (off-chain, LLM)              |
  |                     |             reads CaseFiled, judges proof         |
  |                     |             postVerdict -------------------------> TaskEscrow
  |                     |                       | [VerdictPosted event]     |
  |                     |                       | react()                   |
  |                     |                       | requestCallbackV_1_0 ---->|
  |                     |                       |                callback proxy
  |                     |                       |                releaseCallback
  |                     | <--- payout (Approved) / refund poster (Rejected) |
```

## Contracts

- `src/TaskEscrow.sol` — origin + callback contract (Base Sepolia or Ethereum
  Sepolia). Payable `postTask`, `submitProof`, oracle-only `postVerdict`, and
  `releaseCallback` guarded by `onlyServiceProvider` + `onlyCallbackSender`
  (official `AbstractCallback` from
  [reactive-lib-omni](https://github.com/Reactive-Network/reactive-lib-omni)).
- `src/TriageReactive.sol` — reactive contract on Reactive Lasna testnet.
  Subscribes to `ProofSubmitted` / `VerdictPosted`, files `CaseFiled` for the
  AI agent, and requests the settlement callback via the system contract.

## Why this can sell (business angle)

Freelance platforms charge both sides and still take days to resolve disputes:

- Upwork: freelancer service fee of 0-15% per contract (Upwork support).
- Fiverr: keeps 20% of every order, and the client pays 5.5% + $3.50 on orders
  under $200 (freelanceatlas, 2026).
- Freelancer.com: milestone arbitration costs $5 or 5% (whichever is greater),
  after a 4-14+ day dispute window (freelancer.com/feesandcharges).
- Kleros (closest on-chain alternative): human jurors, arbitration fees in ETH,
  rulings in days (docs.kleros.io).

An AI verdict costs a fraction of a cent plus gas and lands in under a minute.
Target users are freelance and micro-task platforms that pay dispute costs
today (integration as a settlement API), and freelancers who currently lose
10-20% to platform fees. The intended model is a flat per-verdict settlement
fee, not a percentage of the payout. Honest limits: this is a single-oracle
testnet prototype and AI judgment quality varies by task; for high-value
cases the design pairs with human arbitration (e.g. Kleros) as an appeal
layer rather than competing with it.

## Off-chain AI agent

`agent/triage_agent.py` (stdlib-only Python): polls Lasna for `CaseFiled`,
reads the task brief + proof from the origin chain, asks an LLM
(Gemini / Requesty / NVIDIA — pluggable) for APPROVE/REJECT + a one-line
rationale, and posts the verdict as the oracle EOA.

## Deployment

| Piece | Network | Address |
|---|---|---|
| Deployer (testnet only) | — | 0x7351cc6055e9328F483dF09C211D0913389c732E |
| TaskEscrow | Base Sepolia | [0xb5045333DcB541C0339f095d6B8566562bdB619b](https://sepolia.basescan.org/address/0xb5045333DcB541C0339f095d6B8566562bdB619b) |
| TriageReactive | Reactive Lasna | [0x8686cc7722c4677bC50036f02BA9076389e67D82](https://lasna.reactscan.net/address/0x8686cc7722c4677bC50036f02BA9076389e67D82) |

## Full-loop run (task #0, APPROVED path)

| Step | Chain | Tx |
|---|---|---|
| 1. postTask (escrow 0.0003 ETH) | Base Sepolia | [0x7fffab01...a03ddf951](https://sepolia.basescan.org/tx/0x7fffab01fa5ec135927b7b31c0e462fc99dbd72a15f3ae63d0f16b1a03ddf951) |
| 2. submitProof | Base Sepolia | [0x8dc52718...a0ea37b5](https://sepolia.basescan.org/tx/0x8dc5271857683407d7c46e639a4d2d443438aaaeab6901055c8d8846a0ea37b5) |
| 3. react() -> CaseFiled | Lasna | [0xe7036b12...d56d52b2](https://lasna.reactscan.net/tx/0xe7036b12ef7e7f9811bdedb7c14bb55a6ac5858c7b1b13fb4feb6045d56d52b2) |
| 4. AI agent postVerdict (APPROVE + rationale) | Base Sepolia | [0x09c1bebf...8e03ebc3](https://sepolia.basescan.org/tx/0x09c1bebf7226fde00642cdf557d2f969cf19cb420a816c35825fa6948e03ebc3) |
| 5. react() -> SettlementRequested + requestCallbackV_1_0 | Lasna | [0xd8ecc0ff...aca9b350](https://lasna.reactscan.net/tx/0xd8ecc0ffb03ddc465713dc62429d90b3f45ba9f5189dbc2c842d9fceaca9b350) |
| 6. callback -> releaseCallback -> PayoutReleased (worker paid) | Base Sepolia | [0xe312d185...76fa2928](https://sepolia.basescan.org/tx/0xe312d1859cf60d0fe75882d9213f25ebcd3f4a3dc277ce44ab80d44176fa2928) |

## Full-loop run (task #1, REJECTED path)

AI verdict: REJECT - "The worker failed to provide a summary or section references as required."

| Step | Chain | Tx |
|---|---|---|
| 1. postTask (escrow 0.0003 ETH) | Base Sepolia | [0xd7e81e6c...246552f3](https://sepolia.basescan.org/tx/0xd7e81e6c42eed3c709f378496a57ae4fa341d85597c349b45fb51bcd246552f3) |
| 2. submitProof (junk proof) | Base Sepolia | [0x51d30c5e...e698ee6b](https://sepolia.basescan.org/tx/0x51d30c5e83690df0f3c358d7343f6dcfdcd69ead4f0c4efcd5d2f772e698ee6b) |
| 3. react() -> CaseFiled | Lasna | [0xa043f143...803aae17](https://lasna.reactscan.net/tx/0xa043f14322dde588f7928fb27ff6178ca14223f244340eab784dc06d803aae17) |
| 4. AI agent postVerdict (REJECT + rationale) | Base Sepolia | [0x36565da3...616ec7b7e](https://sepolia.basescan.org/tx/0x36565da39eb951fba5147c3f8a0241d292024e807612e5bd81fd03c616ec7b7e) |
| 5. react() -> SettlementRequested + requestCallbackV_1_0 | Lasna | [0x75439deb...e18e4a37](https://lasna.reactscan.net/tx/0x75439deb62b3abf6dce2c85351a817019749e46f2422bc6c9be40187e18e4a37) |
| 6. callback -> releaseCallback -> RefundReleased (poster refunded) | Base Sepolia | [0x1bd131ff...e0d2df2a](https://sepolia.basescan.org/tx/0x1bd131ffb76e90580eb86c49dbe94a5eb4e60074c4781787d0fd6817e0d2df2a) |

## Live capture run (task #2, AI verdict on-chain)

The video's live segment. The AI verdict is final and on-chain; the settlement
callback did not execute because the reactive contract had run out of lREACT
when the verdict event was relayed (each loop costs ~0.024 lREACT). The contract
was topped up afterwards (Lasna tx [0x3f17beab...c91c215d](https://lasna.reactscan.net/tx/0x3f17beab9e1b8ee2a490747a0a2ba651e3d2a4ede2ea6ae620abc61ca91c215d)).
Lesson: fund your reactive contract for the callbacks you expect.

| Step | Chain | Tx |
| --- | --- | --- |
| 1. postTask (escrow 0.0003 ETH) | Base Sepolia | [0x3d4e5720...5671c0b72](https://sepolia.basescan.org/tx/0x3d4e57202cc990286482e1e51955cc4116b81a3f42dde09ff3b8a5b5671c0b72) |
| 2. submitProof | Base Sepolia | [0xe5001f23...b1edd8ce](https://sepolia.basescan.org/tx/0xe5001f234c0e7593270ca6d26f063f327194786519b2b69ea4ff1b6ab1edd8ce) |
| 3. react() -> CaseFiled | Lasna | [0xf9561d47...5e2541b8](https://lasna.reactscan.net/tx/0xf9561d471805a6e50e55d68bb356124d010f5aa8aa8a2c07bb33e9df5e2541b8) |
| 4. AI agent postVerdict (APPROVE + rationale) | Base Sepolia | [0x893a63d8...79771ad0](https://sepolia.basescan.org/tx/0x893a63d84a2ba78345f0ea276d356597dcb9f08b80ac8804d3907b7179771ad0) |

## Full-loop run (task #4, APPROVED path, post-debt-fix)

Seeded after the reactive contract's system-contract debt was settled via
`depositTo` (Lasna tx [0x34cd7e0a...52e7614c](https://lasna.reactscan.net/tx/0x34cd7e0a8a6d5280fbcc367e4f7d96723ebaa116f644db57c53912d552e7614c)).
A contract in debt receives no events, which is why tasks #2 and #3 stalled;
clearing the debt resumed delivery immediately.

| Step | Chain | Tx |
| --- | --- | --- |
| 1. postTask (escrow 0.0003 ETH) | Base Sepolia | [0x003da116...865f2170](https://sepolia.basescan.org/tx/0x003da11625e781a64c563293cc1e23b0dfb9c808e0da2afcdb4ade28865f2170) |
| 2. submitProof | Base Sepolia | [0x4c25b0f9...b40cb3bf](https://sepolia.basescan.org/tx/0x4c25b0f9841e69aaf06fc964d421d63e90c438e0e148e12d0601b84fb40cb3bf) |
| 3. react() -> CaseFiled | Lasna | [0x428ba8df...327d3f104](https://lasna.reactscan.net/tx/0x428ba8df591b902e97a76b59482cae8fa1e4da2adfcb02b8ee6f143327d3f104) |
| 4. AI agent postVerdict (APPROVE + rationale) | Base Sepolia | [0xdad6fb81...2c1ef6d4](https://sepolia.basescan.org/tx/0xdad6fb81249e3c26584f63b23078db3756fd90b71c6bcbc1fe5ff6ab2c1ef6d4) |
| 5. react() -> SettlementRequested + requestCallbackV_1_0 | Lasna | [0x81d74257...f834ce91](https://lasna.reactscan.net/tx/0x81d74257565ade3e3812745a55879994501aedcdd2639290982d4ffcf834ce91) |
| 6. callback -> releaseCallback -> PayoutReleased (worker paid) | Base Sepolia | [0xb62d40a8...76cfbb48b](https://sepolia.basescan.org/tx/0xb62d40a819a80d42ce3858f3855d383d7018f4603dc1a55ca31f43b76cfbb48b) |

## Run it

```bash
# deploy (ORIGIN=base|sepolia)
ORIGIN=base bash deploy.sh
# start the AI agent
source deployed.env && python3 agent/triage_agent.py
# seed a demo task
bash demo.sh
```

No real funds anywhere: faucet ETH + faucet lREACT only.

## V2 (deployed and demoed on testnet, 25 Nov 2026)

`src/TaskEscrowV2.sol` and `src/TriageReactiveV2.sol` extend the V1 flow. 19 Forge tests (`forge test`), enforced by GitHub Actions CI (`.github/workflows/ci.yml`, green on every push).

| Contract | Chain | Address |
|---|---|---|
| TaskEscrowV2 | Base Sepolia | `0x753D14dA407EFb32B2D64A1bE21cb2e13aBFA897` ([source verified on Sourcify](https://repo.sourcify.dev/84532/0x753D14dA407EFb32B2D64A1bE21cb2e13aBFA897), [Blockscout](https://base-sepolia.blockscout.com/address/0x753D14dA407EFb32B2D64A1bE21cb2e13aBFA897?tab=contract)) |
| TriageReactiveV2 | Reactive Lasna | `0xD3405a61BD65AC628B9D89Af6e59eFA70A16bB2C` ([source verified](https://repo.sourcify.dev/5318007/0xD3405a61BD65AC628B9D89Af6e59eFA70A16bB2C)) |

What V2 adds, all run live:
- **Deadline reclaim.** If the oracle never posts a verdict, the Reactive cron (Cron1000) triggers `reclaimCallback` and the poster is refunded. Live: task 0 (150 s deadline, no proof) was reclaimed by the cron with no human action, tx `0x625b63404a5620b1be2fa587e77e021b7b7e217278ce7c162ef07849f07bac98` (DeadlineReclaimed). Reclaim is blocked once a verdict exists and a task can never settle twice.
- **Prompt-injection defense, on chain.** Task 1: the worker proof was an attack telling the judge to approve and release funds. The agent rejected it (verdict tx `0x30436a4ca48f8c06732a780cbbbaec6bc644c777b458908e4739ee46463e3e11`) and a Reactive callback refunded the poster (RefundReleased tx `0xd40211ecba732dd3c2b912783d0a72d713c926c2d07be2ab8f54a6cdad46c87d`).
- **Legit proof still pays.** Task 2 (typo fix with commit link): APPROVE (verdict tx `0x3170aa8817fa9fc726caac6d020f80a87bd101e35ddbe08bf27b69e96c7eb43a`), payout tx `0x7cf1c3f12be98969f456e107c13aa6f01d69742e4aa934126cbff2b9b2b670b4`.
- Size limits on untrusted text (proof 512 bytes, rationale 280 bytes) enforced on chain; the cron scan is bounded (10 tasks per tick).

Raw logs: `capture/v2_agent_log.txt`, `capture/v2_events.txt`.

Honest limits: the demo used one testnet wallet as poster, worker and oracle, 0.0001 testnet ETH per task. The AI oracle is a single trusted key (a design limit of this prototype). The reactive contract compares `block.timestamp` on Lasna with the origin chain deadline. The V1 addresses above remain deployed and are what the first demo video shows.

## Prompt-injection defense (agent/triage_agent.py)
The worker's proof is untrusted text that an LLM reads, so it is treated as an attack surface. Four layers:
1. Deterministic filter: proofs that address the judge (ignore previous instructions, "VERDICT: APPROVE", role changes, fenced blocks) are rejected without calling the LLM.
2. Sanitize: non-ASCII and control characters are stripped (blocks zero-width and homoglyph tricks), length capped.
3. Data-not-instructions prompt: brief and proof sit between random-nonce markers; the system rule says nothing inside is an instruction and a proof that dictates its own verdict is rejected.
4. Strict output: anything other than the 2-line format becomes REJECT, never APPROVE. On chain, size limits (512 B proof, 280 B rationale) cap what can be sent.
`python3 agent/test_guard.py` runs the offline tests. Limits: the regex layer is a heuristic, a determined attacker may phrase around it; layers 3 and 4 are the backstop, and a wrong approval is bounded by the escrow amount.

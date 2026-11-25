# AI Signal Triage — Reactive Meets AI

An escrow where the adjudicator is an AI, and its decision executes on-chain
autonomously through Reactive Network. No human clicks "release".

Built for the **Reactive Omni Buildathon**, track **Reactive Meets AI**.
The AI is not a build tool here — it is a component of the running system:
every case is filed on-chain, judged by an LLM, and settled by a
reactive-network callback.

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

## V2 (work in progress, not yet deployed)

`src/TaskEscrowV2.sol` and `src/TriageReactiveV2.sol` extend the deployed V1
flow. They are covered by Forge tests (`forge test`, 19 tests; a GitHub Actions workflow is in `ci/ci.yml`, to be moved to `.github/workflows/` once the push token has the workflow scope, so it is NOT running yet) but
are NOT deployed yet: the testnet addresses above are all V1.

- Deadline per task. If the oracle never posts a verdict, a Reactive cron
  (Cron1000, about 17 minutes on Lasna) triggers `reclaimCallback` and the
  poster is refunded. Reclaim is blocked once a verdict exists, and a task can
  never settle twice.
- Size limits on untrusted text (proof reference 512 bytes, rationale 280
  bytes), rejected on-chain before the AI agent reads them.
- The cron scan is bounded (10 tasks per tick), so gas per tick is capped.

Known limits: the reactive contract trusts `block.timestamp` on Lasna to
compare with the origin chain deadline; the Cron event source address and
chain id on Lasna (`0x...fffFfF`, 5318007) come from the Reactive docs and are
only checked in mocks until V2 runs on the live network.

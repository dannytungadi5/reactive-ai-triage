# AI Signal Triage — Reactive Meets AI

An escrow where the adjudicator is an AI, and its decision executes on-chain
autonomously through Reactive Network. No human clicks "release".

Built for the **Reactive Omni Buildathon**, track **Reactive Meets AI**.
The AI is not a build tool here — it is a component of the running system:
every case is filed on-chain, judged by an LLM, and settled by a
reactive-network callback.

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

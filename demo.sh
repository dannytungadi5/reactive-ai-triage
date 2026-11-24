#!/usr/bin/env bash
# Seed a demo task: poster escrows funds, worker submits proof.
# The AI agent (triage_agent.py) does the rest; TriageReactive settles via callback.
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
source deployed.env
KEY="$(cat "${KEYFILE:-/home/sandbox/.vault/reactive-buildathon-deployer-wallet-testnet-only-08eef9/password}")"

CASE_REF="${1:-Translate the project tagline into Indonesian}"
PROOF_REF="${2:-Translation: 'Sinyal AI, dieksekusi on-chain' - posted at ipfs://demo-proof}"

echo "== postTask (escrow 0.0005 ETH) =="
cast send "$TASK_ESCROW" "postTask(string)" "$CASE_REF" \
  --value 0.0003ether --rpc-url "$ORIGIN_RPC" --private-key "$KEY"

echo "== submitProof (task 0) =="
cast send "$TASK_ESCROW" "submitProof(uint256,string)" 0 "$PROOF_REF" \
  --rpc-url "$ORIGIN_RPC" --private-key "$KEY"

echo "seeded. Watch the agent log for the verdict, then:"
echo "  cast logs --rpc-url $ORIGIN_RPC --address $TASK_ESCROW"

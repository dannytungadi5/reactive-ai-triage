#!/usr/bin/env bash
# Deploy V2 (TaskEscrowV2 on Base Sepolia, TriageReactiveV2 on Reactive Lasna). Deployer already funded.
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
KEYFILE="${KEYFILE:-/home/sandbox/.vault/reactive-buildathon-deployer-wallet-testnet-only-08eef9/password}"
KEY="$(cat "$KEYFILE")"
ORIGIN_RPC="${ORIGIN_RPC:-https://sepolia.base.org}"
LASNA_RPC="https://lasna-rpc.rnk.dev/"
CALLBACK_PROXY="0x476F44b11F5C942c58f4c8E3d0300E5710743585"
ADDR="$(cast wallet address --private-key "$KEY")"
LASNA_CHAIN_ID="$(cast chain-id --rpc-url "$LASNA_RPC")"
N="$(cast nonce "$ADDR" --rpc-url "$LASNA_RPC")"
REACTIVE_ADDR="$(cast compute-address --nonce "$N" "$ADDR" | awk '{print $NF}')"
echo "precomputed TriageReactiveV2: $REACTIVE_ADDR (lasna chain $LASNA_CHAIN_ID)"
ESC="$(forge create src/TaskEscrowV2.sol:TaskEscrowV2 --rpc-url "$ORIGIN_RPC" --private-key "$KEY" --broadcast \
  --value "${ESCROW_FUNDS:-0.0002ether}" --constructor-args "$CALLBACK_PROXY" "$REACTIVE_ADDR" "$ADDR" --json | jq -r .deployedTo)"
echo "TaskEscrowV2: $ESC"
REA="$(forge create src/TriageReactiveV2.sol:TriageReactiveV2 --rpc-url "$LASNA_RPC" --private-key "$KEY" --broadcast \
  --value "${REACTIVE_FUNDS:-0.02ether}" --constructor-args "$ESC" "$LASNA_CHAIN_ID" --json | jq -r .deployedTo)"
echo "TriageReactiveV2: $REA"
[ "$REA" = "$REACTIVE_ADDR" ] || { echo "ADDRESS MISMATCH" >&2; exit 1; }
printf 'ORIGIN_RPC=%s\nLASNA_RPC=%s\nTASK_ESCROW=%s\nTRIAGE_REACTIVE=%s\nDEPLOYER=%s\n' "$ORIGIN_RPC" "$LASNA_RPC" "$ESC" "$REA" "$ADDR" > deployed_v2.env

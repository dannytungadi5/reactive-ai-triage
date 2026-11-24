#!/usr/bin/env bash
# Deploy AI Signal Triage: TaskEscrow (origin) then TriageReactive (Lasna).
# Usage: ORIGIN=base|sepolia bash deploy.sh
# Requires: KEYFILE (deployer private key file, from vault write-file)
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"

ORIGIN="${ORIGIN:-base}"
KEYFILE="${KEYFILE:-/home/sandbox/.vault/reactive-buildathon-deployer-wallet-testnet-only-08eef9/password}"
KEY="$(cat "$KEYFILE")"

if [ "$ORIGIN" = "base" ]; then
  ORIGIN_RPC="https://sepolia.base.org"
  ORIGIN_CHAIN_ID=84532
  CALLBACK_PROXY="0x476F44b11F5C942c58f4c8E3d0300E5710743585"
  FAUCET_L1="0x2afaFD298b23b62760711756088F75B7409f5967"
else
  ORIGIN_RPC="https://ethereum-sepolia-rpc.publicnode.com"
  ORIGIN_CHAIN_ID=11155111
  CALLBACK_PROXY="0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4"
  FAUCET_L1="0x9b9BB25f1A81078C544C829c5EB7822d747Cf434"
fi
LASNA_RPC="https://lasna-rpc.rnk.dev/"

ADDR="$(cast wallet address --private-key "$KEY")"
echo "deployer: $ADDR  origin: $ORIGIN ($ORIGIN_CHAIN_ID)"
echo "origin balance: $(cast balance "$ADDR" --rpc-url "$ORIGIN_RPC")"
echo "lasna balance:  $(cast balance "$ADDR" --rpc-url "$LASNA_RPC")"

# TriageReactive deploys on LASNA, so its address uses the deployer's LASNA nonce
# (receiving faucet funds does not increment it; the deploy must be the first Lasna tx).
LASNA_NONCE="$(cast nonce "$ADDR" --rpc-url "$LASNA_RPC")"
REACTIVE_ADDR="$(cast compute-address --nonce "$LASNA_NONCE" "$ADDR" | awk '{print $NF}')"
echo "lasna nonce: $LASNA_NONCE  precomputed TriageReactive: $REACTIVE_ADDR"

# 1) lREACT faucet: payout = min(payment, max_payout), paid 1:1 as lREACT on Lasna
FAUCET_PAYMENT="${FAUCET_PAYMENT:-0.003ether}"
echo "== calling lREACT faucet with $FAUCET_PAYMENT =="
cast send "$FAUCET_L1" "request(address)" "$ADDR" \
  --value "$FAUCET_PAYMENT" --rpc-url "$ORIGIN_RPC" --private-key "$KEY"
echo "waiting 60s for lREACT to land on Lasna..."; sleep 60
echo "lasna balance:  $(cast balance "$ADDR" --rpc-url "$LASNA_RPC")"

# 2) deploy TaskEscrow (funded with a little ETH for callback fees)
echo "== deploying TaskEscrow =="
TASK_ESCROW="$(forge create src/TaskEscrow.sol:TaskEscrow \
  --rpc-url "$ORIGIN_RPC" --private-key "$KEY" \
  --value 0.0003ether \
  --constructor-args "$CALLBACK_PROXY" "$REACTIVE_ADDR" "$ADDR" \
  --json | jq -r .deployedTo)"
echo "TaskEscrow: $TASK_ESCROW"

# 3) deploy TriageReactive on Lasna, funded with lREACT
echo "== deploying TriageReactive =="
TRIAGE_REACTIVE="$(forge create src/TriageReactive.sol:TriageReactive \
  --rpc-url "$LASNA_RPC" --private-key "$KEY" \
  --value 0.0015ether \
  --constructor-args "$TASK_ESCROW" \
  --json | jq -r .deployedTo)"
echo "TriageReactive: $TRIAGE_REACTIVE"

if [ "$TRIAGE_REACTIVE" != "$REACTIVE_ADDR" ]; then
  echo "WARNING: reactive address mismatch (expected $REACTIVE_ADDR) - TaskEscrow callbackSender is wrong, redeploy both" >&2
  exit 1
fi

cat > deployed.env <<EOF
ORIGIN=$ORIGIN
ORIGIN_RPC=$ORIGIN_RPC
ORIGIN_CHAIN_ID=$ORIGIN_CHAIN_ID
LASNA_RPC=$LASNA_RPC
TASK_ESCROW=$TASK_ESCROW
TRIAGE_REACTIVE=$TRIAGE_REACTIVE
DEPLOYER=$ADDR
EOF
echo "wrote deployed.env"

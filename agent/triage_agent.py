#!/usr/bin/env python3
"""AI Signal Triage agent - the AI in the running system.

Watches CaseFiled events emitted by TriageReactive on Reactive Lasna testnet,
reads the case + proof from TaskEscrow on the origin chain, asks an LLM for a
verdict, and posts it on-chain as the oracle. The reactive contract then
settles the escrow autonomously via a Reactive Network callback.

Stdlib only. Environment:
  ORIGIN_RPC          e.g. https://sepolia.base.org
  LASNA_RPC           e.g. https://lasna-rpc.rnk.dev/
  TASK_ESCROW         TaskEscrow address on origin chain
  TRIAGE_REACTIVE     TriageReactive address on Lasna
  ORACLE_KEY_FILE     file containing the oracle/deployer private key (from vault)
  LLM_PROVIDER        gemini | requesty | nvidia
  LLM_KEY_FILE        file containing the LLM API key (from vault)
  STATE_FILE          processed-task tracker (default ./processed.json)
  CAST                path to cast binary (default: cast)
"""
import json, os, subprocess, sys, time, urllib.request

ORIGIN_RPC = os.environ.get("ORIGIN_RPC", "https://sepolia.base.org")
LASNA_RPC = os.environ.get("LASNA_RPC", "https://lasna-rpc.rnk.dev/")
TASK_ESCROW = os.environ["TASK_ESCROW"]
TRIAGE_REACTIVE = os.environ["TRIAGE_REACTIVE"]
ORACLE_KEY_FILE = os.environ["ORACLE_KEY_FILE"]
LLM_PROVIDER = os.environ.get("LLM_PROVIDER", "gemini")
LLM_KEY_FILE = os.environ["LLM_KEY_FILE"]
STATE_FILE = os.environ.get("STATE_FILE", os.path.join(os.path.dirname(__file__), "processed.json"))
CAST = os.environ.get("CAST", "cast")
POLL_SECONDS = int(os.environ.get("POLL_SECONDS", "30"))

# keccak256("CaseFiled(uint256,address,string)")
CASE_FILED_TOPIC = None  # computed at startup via cast


def rpc(url, method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        out = json.load(r)
    if "error" in out:
        raise RuntimeError(f"{method}: {out['error']}")
    return out["result"]


def cast(*args):
    return subprocess.run([CAST, *args], capture_output=True, text=True, check=True).stdout.strip()


def keccak(sig):
    return cast("keccak", sig)


def load_state():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return {"processed": [], "last_block": 0}


def save_state(s):
    with open(STATE_FILE, "w") as f:
        json.dump(s, f)


def decode_case_filed(log):
    task_id = int(log["topics"][1], 16)
    worker = "0x" + log["topics"][2][-40:]
    data = bytes.fromhex(log["data"][2:])
    offset = int.from_bytes(data[0:32], "big")
    length = int.from_bytes(data[offset:offset + 32], "big")
    proof_ref = data[offset + 32:offset + 32 + length].decode()
    return task_id, worker, proof_ref


def read_task(task_id):
    """tasks(uint256) returns (poster, worker, amount, verdict, settled, caseRef, proofRef)."""
    sig = "tasks(uint256)(address,address,uint256,uint8,bool,string,string)"
    out = cast("call", TASK_ESCROW, sig, str(task_id), "--rpc-url", ORIGIN_RPC)
    lines = [l.strip() for l in out.splitlines() if l.strip()]
    # caseRef/proofRef lines come back quoted by cast
    def unquote(s):
        return s[1:-1] if s.startswith('"') and s.endswith('"') else s
    return {
        "poster": lines[0], "worker": lines[1], "amount": lines[2],
        "verdict": lines[3], "settled": lines[4],
        "case_ref": unquote(lines[5]) if len(lines) > 5 else "",
        "proof_ref": unquote(lines[6]) if len(lines) > 6 else "",
    }


def ask_llm(case_ref, proof_ref):
    prompt = (
        "You are the adjudication engine of an on-chain escrow system. A poster escrowed funds "
        "for a small task and a worker submitted proof. Decide APPROVE or REJECT.\n\n"
        f"Task brief: {case_ref}\n"
        f"Worker's proof: {proof_ref}\n\n"
        "Rules: APPROVE if the proof plausibly satisfies the brief, otherwise REJECT. "
        "Reply with EXACTLY two lines:\n"
        "VERDICT: APPROVE or REJECT\n"
        "RATIONALE: one short sentence (max 120 chars, plain ASCII, no quotes)\n"
    )
    with open(LLM_KEY_FILE) as f:
        key = f.read().strip()
    if LLM_PROVIDER == "gemini":
        url = ("https://generativelanguage.googleapis.com/v1beta/models/"
               "gemini-3-flash-preview:generateContent?key=" + key)
        body = {"contents": [{"parts": [{"text": prompt}]}]}
        req = urllib.request.Request(url, data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=110) as r:
            text = json.load(r)["candidates"][0]["content"]["parts"][0]["text"]
    elif LLM_PROVIDER == "requesty":
        body = {"model": "google/gemma-4-31b-it",
                "messages": [{"role": "user", "content": prompt}],
                "max_tokens": 800}
        req = urllib.request.Request("https://router.requesty.ai/v1/chat/completions",
                                     data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json",
                                              "Authorization": "Bearer " + key})
        with urllib.request.urlopen(req, timeout=110) as r:
            text = json.load(r)["choices"][0]["message"]["content"]
    elif LLM_PROVIDER == "nvidia":
        body = {"model": "meta/llama-3.3-70b-instruct",
                "messages": [{"role": "user", "content": prompt}], "max_tokens": 200}
        req = urllib.request.Request("https://integrate.api.nvidia.com/v1/chat/completions",
                                     data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json",
                                              "Authorization": "Bearer " + key})
        with urllib.request.urlopen(req, timeout=110) as r:
            text = json.load(r)["choices"][0]["message"]["content"]
    else:
        raise RuntimeError("unknown LLM_PROVIDER")
    verdict, rationale = None, ""
    for line in text.splitlines():
        if line.upper().startswith("VERDICT:"):
            verdict = "APPROVE" in line.upper()
        elif line.upper().startswith("RATIONALE:"):
            rationale = line.split(":", 1)[1].strip()[:120]
    if verdict is None:
        raise RuntimeError("LLM gave unparseable verdict: " + text[:200])
    rationale = "".join(c for c in rationale if 32 <= ord(c) < 127).replace('"', "'")
    return verdict, rationale or "AI adjudication complete"


def post_verdict(task_id, approved, rationale):
    key = open(ORACLE_KEY_FILE).read().strip()
    cast("send", TASK_ESCROW, "postVerdict(uint256,bool,string)",
         str(task_id), "true" if approved else "false", rationale,
         "--rpc-url", ORIGIN_RPC, "--private-key", key)
    print(f"[agent] verdict posted task={task_id} approved={approved}: {rationale}", flush=True)


def main():
    global CASE_FILED_TOPIC
    CASE_FILED_TOPIC = keccak("CaseFiled(uint256,address,string)")
    state = load_state()
    once = "--once" in sys.argv
    print(f"[agent] watching {TRIAGE_REACTIVE} on Lasna for CaseFiled...", flush=True)
    while True:
        try:
            latest = int(rpc(LASNA_RPC, "eth_blockNumber", []), 16)
            from_block = state["last_block"] or max(0, latest - 25000)  # Lasna caps getLogs at 30k blocks
            logs = rpc(LASNA_RPC, "eth_getLogs", [{
                "address": TRIAGE_REACTIVE,
                "topics": [CASE_FILED_TOPIC],
                "fromBlock": hex(from_block),
                "toBlock": "latest",
            }])
            for log in logs:
                task_id, worker, proof_ref = decode_case_filed(log)
                if task_id in state["processed"]:
                    continue
                print(f"[agent] new case #{task_id} from {worker}: {proof_ref}", flush=True)
                task = read_task(task_id)
                approved, rationale = ask_llm(task["case_ref"], task["proof_ref"])
                print(f"[agent] LLM says {'APPROVE' if approved else 'REJECT'}: {rationale}", flush=True)
                post_verdict(task_id, approved, rationale)
                state["processed"].append(task_id)
            state["last_block"] = latest + 1
            save_state(state)
        except Exception as e:
            print(f"[agent] error: {e}", file=sys.stderr, flush=True)
        if once:
            break
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()

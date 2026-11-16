"""Bounded, sequential test of per-subscription llm-token-limit counters.

Calls the APIM gateway with two APIM subscription keys (team-a / team-b) and
shows that:
  1. both subscriptions get a successful response at baseline;
  2. team-a hits a gateway 429 after a bounded number of sequential calls;
  3. team-b still succeeds immediately after team-a is throttled;
  4. team-a recovers after the per-minute window resets.

No concurrency, no streaming, small max_tokens — this is a lab probe, not a
load test. Keys come from the environment, never from argv or files.

Usage:
    set APIM_GATEWAY_URL=https://<apim>.azure-api.net
    set APIM_API_PATH=/<base-path>/openai/deployments/<deployment>/chat/completions?api-version=<ver>
    set TEAM_A_KEY=<apim-subscription-key-a>
    set TEAM_B_KEY=<apim-subscription-key-b>
    python test_limits.py
"""

import json
import os
import sys
import time
import urllib.request
import urllib.error

GATEWAY_URL = os.environ["APIM_GATEWAY_URL"].rstrip("/")
API_PATH = os.environ["APIM_API_PATH"]
KEYS = {
    "team-a": os.environ["TEAM_A_KEY"],
    "team-b": os.environ["TEAM_B_KEY"],
}

# Bounded on purpose: a fixed request budget, a prompt that produces a ~150-170
# token completion, and sequential (never concurrent) calls. With a 500 TPM
# policy that crosses the limit in ~4 calls while staying under the backend's
# 1K TPM deployment capacity — so APIM throttles first, not the model.
MAX_REQUESTS_PER_TEAM = 10   # hard cap per phase
PROMPT = "List 20 European capitals with their countries."
MAX_TOKENS = 160                     # ~170 total tokens per call
RECOVERY_WAIT_S = 65                 # wait > 1 minute before retry after 429

URL = f"{GATEWAY_URL}{API_PATH}"
BODY = json.dumps({
    "messages": [{"role": "user", "content": PROMPT}],
    "max_completion_tokens": MAX_TOKENS,
    "stream": False,
}).encode()


def call(team: str) -> tuple[int, dict, dict]:
    req = urllib.request.Request(
        URL, data=BODY, method="POST",
        headers={
            "Content-Type": "application/json",
            "Ocp-Apim-Subscription-Key": KEYS[team],
        })
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, dict(r.headers), json.loads(r.read())
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read())
        except Exception:
            body = {}
        return e.code, dict(e.headers), body


def report(team: str, status: int, headers: dict, body: dict) -> str:
    usage = body.get("usage", {})
    total = usage.get("total_tokens", "?")
    remaining = headers.get("x-lab-remaining-tokens", "?")
    consumed = headers.get("x-lab-consumed-tokens", "?")
    retry = headers.get("Retry-After", "?")
    err = body.get("error", {}).get("message", "")[:80]
    print(f"  {team}: HTTP {status} | usage={total} "
          f"| x-lab-remaining={remaining} x-lab-consumed={consumed} "
          f"| retry-after={retry} {err}")
    return status


def drive(team: str) -> int:
    """Sequential calls until a 429 or the request cap. Returns last status."""
    status = 0
    for i in range(1, MAX_REQUESTS_PER_TEAM + 1):
        status, headers, body = call(team)
        print(f"  request {i}: ", end="")
        report(team, status, headers, body)
        if status == 429:
            return 429
        if status != 200:
            return status
    return status


def main() -> int:
    print("== baseline: one call per team ==")
    for team in ("team-a", "team-b"):
        status, headers, body = call(team)
        report(team, status, headers, body)
        if status != 200:
            print(f"FAIL: {team} baseline returned {status}")
            return 1

    print("== team-a: sequential calls until gateway 429 ==")
    if drive("team-a") != 429:
        print("FAIL: team-a did not hit a 429 within the request budget")
        return 1

    print("== team-b: must still succeed through the same API ==")
    status, headers, body = call("team-b")
    report("team-b", status, headers, body)
    if status != 200:
        print("FAIL: team-b was throttled too — counters are not independent")
        return 1

    print(f"== team-a: waiting {RECOVERY_WAIT_S}s for the window to reset ==")
    time.sleep(RECOVERY_WAIT_S)
    status, headers, body = call("team-a")
    report("team-a", status, headers, body)
    if status != 200:
        print("FAIL: team-a did not recover")
        return 1

    print("PASS: independent per-subscription counters demonstrated")
    return 0


if __name__ == "__main__":
    sys.exit(main())

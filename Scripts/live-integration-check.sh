#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

swift build -c debug --product QuotaGlass >/dev/null
probe_output=$($project_dir/.build/debug/QuotaGlass --probe | tail -n 1)

/usr/bin/python3 - "$probe_output" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
if payload.get("ok") is not True:
    raise SystemExit(f"Live quota probe failed: {payload.get('error', 'unknown error')}")

remaining = payload.get("remainingPercent")
window_count = payload.get("windowCount")
if not isinstance(remaining, int) or not 0 <= remaining <= 100:
    raise SystemExit(f"Invalid remainingPercent: {remaining!r}")
if not isinstance(window_count, int) or window_count < 1:
    raise SystemExit(f"Invalid windowCount: {window_count!r}")
if not payload.get("source") or not payload.get("window"):
    raise SystemExit("Probe did not identify the selected quota window")

print(json.dumps({
    "ok": True,
    "source": payload["source"],
    "window": payload["window"],
    "remainingPercent": remaining,
    "windowCount": window_count,
}, ensure_ascii=False))
PY

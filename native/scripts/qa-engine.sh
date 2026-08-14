#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s PATH_TO_CODEXBAR_CLI\n' "${0##*/}"
}

[[ $# -eq 1 ]] || { usage >&2; exit 2; }
engine="$(realpath "$1")"
[[ -x "$engine" ]] || {
    printf 'Provider engine is missing or not executable: %s\n' "$engine" >&2
    exit 1
}

qa_dir="$(mktemp -d)"
cleanup() {
    rm -rf -- "$qa_dir"
}
trap cleanup EXIT HUP INT TERM

NO_COLOR=1 "$engine" config providers --json > "${qa_dir}/providers.json"
NO_COLOR=1 "$engine" dashboard --identity redacted --timeout 60 > "${qa_dir}/dashboard.json"
NO_COLOR=1 "$engine" cost --provider all --json --days 30 > "${qa_dir}/cost.json" || true

python3 - "$qa_dir" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
providers = json.loads((root / "providers.json").read_text(encoding="utf-8"))
dashboard = json.loads((root / "dashboard.json").read_text(encoding="utf-8"))
cost = json.loads((root / "cost.json").read_text(encoding="utf-8") or "[]")

provider_ids = [entry["provider"] for entry in providers]
assert len(provider_ids) == 69, f"expected 69 providers, got {len(provider_ids)}"
assert len(set(provider_ids)) == len(provider_ids), "provider IDs are not unique"
assert dashboard.get("schemaVersion") == 1, "dashboard-v1 schema is required"
dashboard_ids = [entry["id"] for entry in dashboard.get("providers", [])]
assert set(dashboard_ids).issubset(provider_ids), "dashboard returned an unknown provider"
assert isinstance(cost, list), "cost projection must be a JSON array"

print(f"provider_catalog={len(provider_ids)}")
print(f"enabled_dashboard_rows={len(dashboard_ids)}")
print(f"cost_rows={len(cost)}")
print("native_engine_contract=ok")
PY

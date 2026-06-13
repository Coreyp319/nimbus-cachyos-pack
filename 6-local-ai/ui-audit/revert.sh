#!/usr/bin/env bash
# Layer 6 · UI-audit revert — removes the deployed skill and the daily cron job.
# Default keeps the audit runtime ($HERMES_HOME/ui-audit: ledger, backups,
# pending) so history/undo survive. --purge deletes that too.
set -uo pipefail
PURGE="${1:-}"
HHOME="${HERMES_HOME:-$HOME/.hermes}"
SKILL_DST="$HHOME/skills/devops/kde-plasma-customization"
RUNTIME="$HHOME/ui-audit"
VENV_PY="$HHOME/hermes-agent/venv/bin/python"

echo "── Layer 6 · UI-audit ──"

# Remove the cron job(s) named "Daily UI audit".
if [ -x "$VENV_PY" ]; then
  HERMES_HOME="$HHOME" "$VENV_PY" - <<'PY' 2>/dev/null || true
import os, json, pathlib
from cron import jobs
NAME = "Daily UI audit"
home = pathlib.Path(os.environ.get("HERMES_HOME", str(pathlib.Path.home() / ".hermes")))
jf = home / "cron" / "jobs.json"
ids = []
if jf.exists():
    try:
        data = json.loads(jf.read_text())
        items = data if isinstance(data, list) else data.get("jobs", [])
        ids = [j.get("id") for j in items if j.get("name") == NAME]
    except Exception:
        ids = []
for jid in ids:
    try:
        jobs.remove_job(jid); print(f"  ✓ removed cron job {jid}")
    except Exception as e:
        print(f"  ! could not remove {jid}: {e}")
if not ids:
    print("  · no 'Daily UI audit' cron job found")
PY
else
  echo "  · Hermes venv absent — skipping cron removal"
fi

# Remove the deployed skill.
if [ -d "$SKILL_DST" ]; then
  rm -rf "$SKILL_DST" && echo "  ✓ removed skill $SKILL_DST" || true
fi

if [ "$PURGE" = "--purge" ]; then
  if [ -d "$RUNTIME" ]; then
    rm -rf "$RUNTIME" && echo "  ✓ purged audit runtime $RUNTIME (ledger, backups, pending)" || true
  fi
else
  echo "  audit runtime kept at $RUNTIME (ledger/backups/pending). --purge to delete."
fi

#!/usr/bin/env bash
set -euo pipefail

DEPLOY_FILE="${1:-deploy.json}"
ENVIRONMENT="${2:-dev}"

if [[ ! -f "$DEPLOY_FILE" ]]; then
  echo "ERROR: deploy file not found: $DEPLOY_FILE" >&2
  exit 1
fi

mapfile -t JOBS < <(python - "$DEPLOY_FILE" "$ENVIRONMENT" <<'PY'
import json
import sys

deploy_file, environment = sys.argv[1], sys.argv[2]
with open(deploy_file, encoding="utf-8") as fh:
    config = json.load(fh)

for key, job in config.get("glue_jobs", {}).items():
    if not job.get("enabled", True):
        continue
    if environment not in job.get("enabled_environments", ["dev", "qas", "prd"]):
        continue
    if not job.get("validations", {}).get("enabled", True):
        continue
    script_path = job.get("script_local_path", "")
    print(f"{key}\t{script_path}")
PY
)

if [[ ${#JOBS[@]} -eq 0 ]]; then
  echo "No Glue Job validations enabled for environment: $ENVIRONMENT"
  exit 0
fi

for job_entry in "${JOBS[@]}"; do
  IFS=$'\t' read -r job_key script_path <<< "$job_entry"

  if [[ -z "$script_path" ]]; then
    echo "ERROR: glue job '$job_key' must define script_local_path for validations." >&2
    exit 1
  fi

  if [[ ! -f "$script_path" ]]; then
    echo "ERROR: glue job '$job_key' script not found: $script_path" >&2
    exit 1
  fi

  echo "Validating Glue Job '$job_key' script: $script_path"

  python -m py_compile "$script_path"

  if command -v flake8 >/dev/null 2>&1; then
    flake8 "$script_path" --select=E9,F63,F7,F82
  else
    echo "ERROR: flake8 is required for Glue Job lint validation." >&2
    exit 1
  fi

  if ! grep -Eq "\bGlueContext\b" "$script_path"; then
    echo "ERROR: glue job '$job_key' must initialize GlueContext." >&2
    exit 1
  fi

  if ! grep -Eq "create_dynamic_frame|spark\.read|\.read\(" "$script_path"; then
    echo "ERROR: glue job '$job_key' must read from a source." >&2
    exit 1
  fi

  if ! grep -Eq "write_dynamic_frame|spark\.write|\.write\(" "$script_path"; then
    echo "ERROR: glue job '$job_key' must write to a destination." >&2
    exit 1
  fi

  if ! grep -Eq "^[[:space:]]*try:" "$script_path" || ! grep -Eq "^[[:space:]]*except\b" "$script_path"; then
    echo "ERROR: glue job '$job_key' must implement try/except error handling." >&2
    exit 1
  fi
done

echo "Glue Job validations passed."

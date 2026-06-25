#!/usr/bin/env bash
set -euo pipefail

DEPLOY_FILE="${1:-deploy.json}"
ENVIRONMENT="${2:-dev}"

if [[ ! -f "$DEPLOY_FILE" ]]; then
  echo "ERROR: deploy file not found: $DEPLOY_FILE" >&2
  exit 1
fi

mapfile -t LAMBDAS < <(python - "$DEPLOY_FILE" "$ENVIRONMENT" <<'PY'
import json
import sys

deploy_file, environment = sys.argv[1], sys.argv[2]
with open(deploy_file, encoding="utf-8") as fh:
    config = json.load(fh)

for key, function_config in config.get("lambda", {}).items():
    if not function_config.get("enabled", True):
        continue
    if environment not in function_config.get("enabled_environments", ["dev", "qas", "prd"]):
        continue
    if not function_config.get("validations", {}).get("enabled", True):
        continue
    source_path = function_config.get("source_path", "")
    runtime = function_config.get("runtime", "")
    timeout_present = "timeout" in function_config
    memory_present = "memory_size" in function_config
    print(f"{key}\t{source_path}\t{runtime}\t{timeout_present}\t{memory_present}")
PY
)

if [[ ${#LAMBDAS[@]} -eq 0 ]]; then
  echo "No Lambda validations enabled for environment: $ENVIRONMENT"
  exit 0
fi

for lambda_entry in "${LAMBDAS[@]}"; do
  IFS=$'\t' read -r lambda_key source_path runtime timeout_present memory_present <<< "$lambda_entry"

  if [[ -z "$source_path" ]]; then
    echo "ERROR: lambda '$lambda_key' must define source_path for validations." >&2
    exit 1
  fi

  if [[ ! -d "$source_path" && ! -f "$source_path" ]]; then
    echo "ERROR: lambda '$lambda_key' source_path not found: $source_path" >&2
    exit 1
  fi

  if [[ "$timeout_present" != "True" ]]; then
    echo "ERROR: lambda '$lambda_key' must define timeout explicitly." >&2
    exit 1
  fi

  if [[ "$memory_present" != "True" ]]; then
    echo "ERROR: lambda '$lambda_key' must define memory_size explicitly." >&2
    exit 1
  fi

  echo "Validating Lambda '$lambda_key' source: $source_path"

  case "$runtime" in
    python*)
      PYTHONDONTWRITEBYTECODE=1 python -m py_compile $(find "$source_path" -name "*.py")
      if command -v flake8 >/dev/null 2>&1; then
        flake8 "$source_path" --select=E9,F63,F7,F82
      else
        echo "ERROR: flake8 is required for Python Lambda lint validation." >&2
        exit 1
      fi
      ;;
    nodejs*)
      if command -v npx >/dev/null 2>&1; then
        npx eslint "$source_path"
      else
        echo "ERROR: npx is required for Node.js Lambda lint validation." >&2
        exit 1
      fi
      ;;
    *)
      echo "ERROR: unsupported Lambda runtime for validation: $runtime" >&2
      exit 1
      ;;
  esac

  if command -v trufflehog >/dev/null 2>&1; then
    trufflehog filesystem "$source_path" --fail
  elif grep -RInE "(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|aws_access_key_id|aws_secret_access_key|password[[:space:]]*=|token[[:space:]]*=|api[_-]?key[[:space:]]*=|private[_-]?key)" "$source_path"; then
    echo "ERROR: possible hardcoded secret found in lambda '$lambda_key'." >&2
    exit 1
  else
    echo "trufflehog not found; used fallback secret pattern scan."
  fi
done

echo "Lambda validations passed."

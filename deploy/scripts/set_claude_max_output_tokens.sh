#!/usr/bin/env bash
#
# set_claude_max_output_tokens.sh
#
# Adds CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000 to ~/.zshrc so Claude Code
# responses can exceed the default 32k output cap.
#
# Safe to re-run: detects existing exports and avoids duplicate entries.
# Backs up ~/.zshrc to ~/.zshrc.bak.<timestamp> before modifying.
#
# Usage:
#   bash set_claude_max_output_tokens.sh
#   bash set_claude_max_output_tokens.sh --value 128000   # override default

set -euo pipefail

# ── Configuration ───────────────────────────────────────────────────────────
DEFAULT_VALUE=64000
TARGET_FILE="${HOME}/.zshrc"
VARIABLE_NAME="CLAUDE_CODE_MAX_OUTPUT_TOKENS"

# ── Parse arguments ─────────────────────────────────────────────────────────
VALUE="${DEFAULT_VALUE}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --value)
      VALUE="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [--value <token_count>]"
      echo ""
      echo "Adds CLAUDE_CODE_MAX_OUTPUT_TOKENS to ~/.zshrc."
      echo ""
      echo "Options:"
      echo "  --value N    Set token cap to N (default: ${DEFAULT_VALUE})."
      echo "               Sonnet supports up to 64000."
      echo "               Opus supports up to 128000."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Run with --help for usage." >&2
      exit 1
      ;;
  esac
done

# ── Validate value is a positive integer ────────────────────────────────────
if ! [[ "${VALUE}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: --value must be a positive integer, got: ${VALUE}" >&2
  exit 1
fi

if [[ "${VALUE}" -gt 128000 ]]; then
  echo "Warning: ${VALUE} exceeds Opus 4.7's max output of 128000." >&2
  echo "Claude Code will likely cap at the model's actual maximum." >&2
fi

# ── Preflight: ensure target file exists ────────────────────────────────────
if [[ ! -f "${TARGET_FILE}" ]]; then
  echo "Error: ${TARGET_FILE} does not exist." >&2
  echo "Expected zsh shell configuration. Edit script if using a different shell." >&2
  exit 1
fi

# ── Check for existing export ───────────────────────────────────────────────
EXISTING_LINE=$(grep -n "^export ${VARIABLE_NAME}=" "${TARGET_FILE}" || true)

if [[ -n "${EXISTING_LINE}" ]]; then
  EXISTING_VALUE=$(echo "${EXISTING_LINE}" | sed -E "s/^[0-9]+:export ${VARIABLE_NAME}=([0-9]+).*/\1/")

  if [[ "${EXISTING_VALUE}" == "${VALUE}" ]]; then
    echo "Already configured: ${VARIABLE_NAME}=${VALUE}"
    echo "No changes needed. Existing line:"
    echo "  ${EXISTING_LINE}"
    exit 0
  else
    echo "Existing ${VARIABLE_NAME} found with value ${EXISTING_VALUE}."
    echo "Will replace with new value ${VALUE}."
    echo ""
  fi
fi

# ── Back up the file ────────────────────────────────────────────────────────
BACKUP_FILE="${TARGET_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
cp "${TARGET_FILE}" "${BACKUP_FILE}"
echo "Backed up ${TARGET_FILE} to ${BACKUP_FILE}"

# ── Apply the change ────────────────────────────────────────────────────────
if [[ -n "${EXISTING_LINE}" ]]; then
  # Replace existing export line in place
  sed -i.tmp -E "s|^export ${VARIABLE_NAME}=.*$|export ${VARIABLE_NAME}=${VALUE}|" "${TARGET_FILE}"
  rm -f "${TARGET_FILE}.tmp"
  echo "Updated ${VARIABLE_NAME} to ${VALUE} in ${TARGET_FILE}"
else
  # Append a new export with a header comment
  {
    echo ""
    echo "# Claude Code: raise output token cap from 32k default to ${VALUE}."
    echo "# Sonnet 4.6 supports up to 64k output; Opus 4.7 supports up to 128k."
    echo "# Setting a higher cap has no cost impact — only tokens actually"
    echo "# generated are billed. Prevents truncation errors on long edits."
    echo "export ${VARIABLE_NAME}=${VALUE}"
  } >> "${TARGET_FILE}"
  echo "Added ${VARIABLE_NAME}=${VALUE} to ${TARGET_FILE}"
fi

# ── Verification ────────────────────────────────────────────────────────────
echo ""
echo "Verification:"
echo "  Current ${TARGET_FILE} entry:"
grep -n "${VARIABLE_NAME}" "${TARGET_FILE}" | sed 's/^/    /'
echo ""

# ── Next steps ──────────────────────────────────────────────────────────────
echo "To activate in your current shell, run:"
echo "  source ${TARGET_FILE}"
echo ""
echo "Or open a new terminal session."
echo ""
echo "To verify activation:"
echo "  echo \$${VARIABLE_NAME}"
echo "  # should print: ${VALUE}"

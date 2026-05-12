#!/usr/bin/env bash
set -euo pipefail

SOURCE="$HOME/triskele-prompts/00_PROJECT_BIBLE.md"
DEST_DIR="$HOME/triskele/docs"
DEST_BIBLE="$DEST_DIR/PROJECT_BIBLE.md"
DEST_README="$DEST_DIR/README.md"
SNAPSHOT_DATE="2026-05-12"

echo "--- Preflight checks ---"
[[ -f "$SOURCE" ]] || { echo "ERROR: source Bible not found at $SOURCE"; exit 1; }
[[ -d "$DEST_DIR" ]] || { echo "ERROR: docs dir not found at $DEST_DIR"; exit 1; }
[[ ! -f "$DEST_BIBLE" ]] || { echo "ERROR: $DEST_BIBLE already exists; refusing to overwrite"; exit 1; }
[[ ! -f "$DEST_README" ]] || { echo "ERROR: $DEST_README already exists; refusing to overwrite"; exit 1; }

echo "--- Copying Bible ---"
cp "$SOURCE" "$DEST_BIBLE"

echo "--- Writing docs/README.md ---"
cat > "$DEST_README" <<EOF
# docs/

## PROJECT_BIBLE.md

This file is a snapshot of \`~/triskele-prompts/00_PROJECT_BIBLE.md\`,
copied on $SNAPSHOT_DATE at the start of Phase 0.

The canonical source lives in the prompts package. If you correct
anything here, mirror the change there (or vice versa). We'll revisit
the storage strategy if the Bible starts changing frequently.

## Other files

- \`architecture.md\` — system architecture and design decisions
- \`disaster_recovery.md\` — DR procedures
- \`runbook.md\` — operational runbook
EOF

echo "--- Verification ---"
ls -la "$DEST_DIR"
echo
diff "$SOURCE" "$DEST_BIBLE" && echo "Bible copy matches source (byte-identical)"
echo
echo "--- docs/README.md contents ---"
cat "$DEST_README"

echo
echo "=== Step 2 complete ==="

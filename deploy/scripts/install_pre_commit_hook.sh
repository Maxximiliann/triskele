#!/usr/bin/env bash
set -euo pipefail

HOOK=".git/hooks/pre-commit"

cat > "$HOOK" <<'EOF'
#!/usr/bin/env bash
set -e
mix format --check-formatted
mix credo --strict
EOF

chmod +x "$HOOK"
echo "Pre-commit hook installed at $HOOK"

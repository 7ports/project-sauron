#!/bin/bash
# Voltron Docker launcher — starts Claude Code with full agent autonomy
# Usage: ./scripts/voltron-run.sh
#        ./scripts/voltron-run.sh -p "invoke @agent-scrum-master to plan the backlog"

docker build -t voltron-agent -f Dockerfile.voltron . 2>/dev/null

# Build env passthrough for auth (OAuth token or API key)
AUTH_ARGS=()
[ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && AUTH_ARGS+=(-e "CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN")
[ -n "$ANTHROPIC_API_KEY" ] && AUTH_ARGS+=(-e "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY")

docker run --rm -it \
  "${AUTH_ARGS[@]}" \
  -v "$(pwd):/workspace" \
  -v "$HOME/.claude:/home/voltron/.claude" \
  -v "$HOME/.claude.json:/home/voltron/.claude.json:ro" \
  voltron-agent \
  --dangerously-skip-permissions \
  "$@"
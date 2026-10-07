#!/usr/bin/env bash
# start_tunnel.sh - Forward local ports 8000 (engine) and 8080 (Jupyter) to a rented GPU instance.
#
# Usage: scripts/start_tunnel.sh [host] [ssh_port]
#   or set TUNNEL_HOST / TUNNEL_SSH_PORT (and optionally TUNNEL_USER, TUNNEL_KEY).
# The host key must already be in ~/.ssh/known_hosts (or confirmed interactively);
# unknown or changed keys are not accepted silently.
set -euo pipefail

HOST="${1:-${TUNNEL_HOST:-}}"
PORT="${2:-${TUNNEL_SSH_PORT:-}}"
USER_NAME="${TUNNEL_USER:-root}"
KEY="${TUNNEL_KEY:-$HOME/.ssh/id_ed25519}"

if [[ -z "$HOST" || -z "$PORT" ]]; then
    echo "Usage: $0 <host> <ssh_port>   (or set TUNNEL_HOST and TUNNEL_SSH_PORT)" >&2
    exit 1
fi

echo "=== Establishing SSH Tunnel: localhost:8000 (Engine) & 8080 (Jupyter) -> ${HOST}:${PORT} ==="
fuser -k 8000/tcp 2>/dev/null || true
ssh -p "$PORT" \
    -i "$KEY" \
    -N \
    -L 8000:localhost:8000 \
    -L 8080:localhost:8080 \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=6 \
    -o ExitOnForwardFailure=yes \
    -o StrictHostKeyChecking=ask \
    "${USER_NAME}@${HOST}"

#!/usr/bin/env bash
# start_tunnel.sh - Forward local port 8000 to Vast.ai RTX 5090 instance
echo "=== Establishing SSH Tunnel: Localhost:8000 -> Vast.ai RTX 5090:8000 ==="
# Instance: vast.ai #51223084 — RTX 5090 32GB, CN
# SSH port: 53262, IP: 113.207.71.6
fuser -k 8000/tcp 2>/dev/null || true
ssh -p 53262 \
    -i ~/.ssh/id_ed25519 \
    -N \
    -L 8000:localhost:8000 \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=6 \
    -o ExitOnForwardFailure=yes \
    -o StrictHostKeyChecking=no \
    root@113.207.71.6


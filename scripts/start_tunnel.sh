#!/usr/bin/env bash
# start_tunnel.sh - Forward local ports 8000 and 8080 to Vast.ai instance
echo "=== Establishing SSH Tunnel: Localhost:8000 (Engine) & 8080 (Jupyter) -> Vast.ai RTX 3090 ==="
# Instance: vast.ai — RTX 3090 24GB
# SSH port: 41504, IP: 106.184.52.80
fuser -k 8000/tcp 2>/dev/null || true
ssh -p 41504 \
    -i ~/.ssh/id_ed25519 \
    -N \
    -L 8000:localhost:8000 \
    -L 8080:localhost:8080 \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=6 \
    -o ExitOnForwardFailure=yes \
    -o StrictHostKeyChecking=no \
    root@106.184.52.80



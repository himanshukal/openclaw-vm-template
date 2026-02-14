#!/bin/bash
# Wait for gateway to be fully up before starting browser relay
echo "[relay] Waiting for gateway to start..."
sleep 20

# Log diagnostics
echo "[relay] OpenClaw version:" && openclaw --version 2>&1
echo "[relay] Checking for clawbot:" && which clawbot 2>&1 || true
echo "[relay] OpenClaw browser help:" && openclaw browser --help 2>&1

# Check listening ports
echo "[relay] Current listening ports:"
ss -tlnp 2>/dev/null | grep -E '187' || true

# Try the browser serve command
echo "[relay] Starting: openclaw browser serve --cdp-url http://127.0.0.1:18800 --port 18792"
exec openclaw browser serve --cdp-url http://127.0.0.1:18800 --port 18792 2>&1

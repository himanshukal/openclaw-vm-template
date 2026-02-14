#!/bin/bash
# Setup script: waits for Chrome CDP + gateway, then initializes browser connection
# Runs once after gateway and Chrome are up (autorestart=false)

echo "[setup-browser] Waiting for Chrome and gateway to start..."
sleep 15

# Wait for Chrome CDP to be accessible
echo "[setup-browser] Waiting for Chrome CDP on port 18800..."
for i in $(seq 1 30); do
    if curl -sf http://127.0.0.1:18800/json/version > /dev/null 2>&1; then
        echo "[setup-browser] Chrome CDP is responding on port 18800"
        curl -s http://127.0.0.1:18800/json/version
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "[setup-browser] ERROR: Chrome CDP never responded after 30 attempts"
        exit 1
    fi
    echo "[setup-browser] Chrome CDP not ready, attempt $i/30..."
    sleep 3
done

# Wait for gateway
echo "[setup-browser] Waiting for gateway on port 18789..."
for i in $(seq 1 20); do
    if curl -sf http://127.0.0.1:18789/__openclaw__/canvas/ > /dev/null 2>&1; then
        echo "[setup-browser] Gateway is responding"
        break
    fi
    echo "[setup-browser] Gateway not ready, attempt $i/20..."
    sleep 3
done

# Install the OpenClaw Chrome extension into the browser
echo "[setup-browser] Installing OpenClaw Chrome extension..."
openclaw browser extension install --token "$OPENCLAW_GATEWAY_TOKEN" 2>&1 || echo "[setup-browser] Extension install failed (may already be installed via policy)"

# Start the browser connection (attaches to Chrome CDP via attachOnly config)
echo "[setup-browser] Starting browser connection..."
openclaw browser start --token "$OPENCLAW_GATEWAY_TOKEN" 2>&1 || echo "[setup-browser] Browser start returned non-zero"

# Check browser status
echo "[setup-browser] Browser status:"
openclaw browser status --token "$OPENCLAW_GATEWAY_TOKEN" 2>&1 || echo "[setup-browser] Status check failed"

# Show port status
echo "[setup-browser] Port status:"
netstat -tlnp 2>/dev/null | grep -E '187|18800' || ss -tlnp 2>/dev/null | grep -E '187|18800' || echo "[setup-browser] Could not check ports"

echo "[setup-browser] Setup complete."

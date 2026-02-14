#!/bin/bash
# Setup script: installs OpenClaw Chrome extension and initializes browser connection
# Runs once after gateway and Chrome are up (autorestart=false)

echo "[setup-browser] Waiting for gateway and Chrome to start..."
sleep 30

# Verify Chrome CDP is accessible
echo "[setup-browser] Checking Chrome CDP on port 18800..."
for i in $(seq 1 10); do
    if curl -sf http://127.0.0.1:18800/json/version > /dev/null 2>&1; then
        echo "[setup-browser] Chrome CDP is responding on port 18800"
        break
    fi
    echo "[setup-browser] Chrome CDP not ready, attempt $i/10..."
    sleep 5
done

# Show port status
echo "[setup-browser] Port status:"
ss -tlnp 2>/dev/null | grep -E '187|5900|6080|18800' || true

# Install the OpenClaw Chrome extension into Chrome
echo "[setup-browser] Installing OpenClaw Chrome extension..."
openclaw browser extension install --token "$OPENCLAW_GATEWAY_TOKEN" 2>&1 || true

# Start the browser connection (triggers pairing with gateway)
echo "[setup-browser] Starting browser connection (pairing with gateway)..."
openclaw browser start --token "$OPENCLAW_GATEWAY_TOKEN" 2>&1 || true

# Check browser status
echo "[setup-browser] Browser status:"
openclaw browser status --token "$OPENCLAW_GATEWAY_TOKEN" 2>&1 || true

echo "[setup-browser] Setup complete."

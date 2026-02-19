#!/bin/bash
# Setup script: waits for gateway to stabilize, then starts managed browser profile.
# The managed profile (openclaw.json browser.defaultProfile="openclaw") handles
# Chrome launch, CDP connection, and extension relay automatically.

echo "[setup-browser] Waiting for gateway to start..."

# Wait for gateway to be healthy
for i in $(seq 1 30); do
    if curl -sf http://127.0.0.1:18789/__openclaw__/canvas/ > /dev/null 2>&1; then
        echo "[setup-browser] Gateway is responding on port 18789"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "[setup-browser] WARNING: Gateway not ready after 30 attempts"
    fi
    echo "[setup-browser] Gateway not ready, attempt $i/30..."
    sleep 5
done

# Give gateway a few more seconds to stabilize
sleep 5

# Start the managed browser profile — OpenClaw launches Chrome with settings from openclaw.json
echo "[setup-browser] Starting managed browser profile..."
openclaw browser start --profile openclaw --token "$OPENCLAW_GATEWAY_TOKEN" 2>&1 || echo "[setup-browser] Browser start returned non-zero"

# Check browser status
echo "[setup-browser] Browser status:"
openclaw browser status --token "$OPENCLAW_GATEWAY_TOKEN" 2>&1 || echo "[setup-browser] Status check failed"

# Show port status
echo "[setup-browser] Port status:"
netstat -tlnp 2>/dev/null | grep -E '187|18800' || ss -tlnp 2>/dev/null | grep -E '187|18800' || echo "[setup-browser] Could not check ports"

echo "[setup-browser] Setup complete."

# Keep script alive for supervisord
exec sleep infinity

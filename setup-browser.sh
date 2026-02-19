#!/bin/bash
# Setup script: waits for gateway to stabilize, then starts managed browser profile.
# The managed profile (openclaw.json browser.defaultProfile="openclaw") handles
# Chrome launch, CDP connection, and extension relay automatically.

echo "[setup-browser] Waiting for gateway to start..."

# Wait for gateway to be healthy (up to 5 minutes — first boot can be slow)
for i in $(seq 1 60); do
    if curl -sf http://127.0.0.1:18789/__openclaw__/canvas/ > /dev/null 2>&1; then
        echo "[setup-browser] Gateway is responding on port 18789"
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "[setup-browser] WARNING: Gateway not ready after 60 attempts, trying browser start anyway"
    fi
    echo "[setup-browser] Gateway not ready, attempt $i/60..."
    sleep 5
done

# Give gateway a few more seconds to stabilize
sleep 5

# Start the managed browser profile with retries
echo "[setup-browser] Starting managed browser profile..."
for attempt in $(seq 1 10); do
    if openclaw browser start --profile openclaw --token "$OPENCLAW_GATEWAY_TOKEN" 2>&1; then
        echo "[setup-browser] Browser started successfully on attempt $attempt"
        break
    fi
    if [ "$attempt" -eq 10 ]; then
        echo "[setup-browser] ERROR: Browser start failed after 10 attempts"
    else
        echo "[setup-browser] Browser start attempt $attempt failed, retrying in 10s..."
        sleep 10
    fi
done

# Check browser status
echo "[setup-browser] Browser status:"
openclaw browser status --token "$OPENCLAW_GATEWAY_TOKEN" 2>&1 || echo "[setup-browser] Status check failed"

# Show port status
echo "[setup-browser] Port status:"
netstat -tlnp 2>/dev/null | grep -E '187|18800' || ss -tlnp 2>/dev/null | grep -E '187|18800' || echo "[setup-browser] Could not check ports"

echo "[setup-browser] Setup complete."

# Keep script alive for supervisord
exec sleep infinity

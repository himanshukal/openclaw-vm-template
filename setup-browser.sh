#!/bin/bash
# Setup script: waits for gateway to stabilize, launches Chrome, then initializes browser connection
# Runs once after gateway is up (autorestart=false)

echo "[setup-browser] Waiting for gateway to start..."

# Wait for gateway to be healthy first (before starting Chrome to save memory)
for i in $(seq 1 30); do
    if curl -sf http://127.0.0.1:18789/__openclaw__/canvas/ > /dev/null 2>&1; then
        echo "[setup-browser] Gateway is responding on port 18789"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "[setup-browser] WARNING: Gateway not ready after 30 attempts, starting Chrome anyway"
    fi
    echo "[setup-browser] Gateway not ready, attempt $i/30..."
    sleep 5
done

# Give gateway a few more seconds to stabilize
sleep 5

# Launch Chrome with memory-limiting flags (not managed by supervisord to control startup order)
echo "[setup-browser] Launching Chrome..."
google-chrome-stable \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --start-maximized \
    --remote-debugging-port=18800 \
    --user-data-dir=/tmp/chrome-data \
    --disable-background-networking \
    --disable-sync \
    --disable-translate \
    --no-first-run \
    --disable-default-apps \
    --renderer-process-limit=2 \
    --js-flags="--max-old-space-size=128" &
CHROME_PID=$!
echo "[setup-browser] Chrome launched with PID $CHROME_PID"

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

echo "[setup-browser] Setup complete. Chrome PID: $CHROME_PID"

# Keep this script running to keep Chrome alive (wait for Chrome process)
wait $CHROME_PID
echo "[setup-browser] Chrome exited, restarting..."
exec "$0"

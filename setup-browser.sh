#!/bin/bash
# Setup script: waits for gateway to stabilize, then launches Chrome directly.
#
# OpenClaw's managed browser profile (openclaw browser start) uses a browser
# control service on port 18791 that has a known Docker bug — it reports ready
# but never actually binds the port. This script bypasses that entirely by
# launching Chrome directly with --remote-debugging-port=18800 and configuring
# OpenClaw with attachOnly: true so it connects via CDP without the control service.
#
# After Chrome starts, pending devices are auto-approved so the browser tool
# can connect back to the gateway without manual intervention.

echo "[setup-browser] Waiting for gateway to start..."

# Wait for gateway to be healthy (up to 5 minutes — first boot can be slow)
for i in $(seq 1 60); do
    if curl -sf http://127.0.0.1:18789/__openclaw__/canvas/ > /dev/null 2>&1; then
        echo "[setup-browser] Gateway is responding on port 18789"
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "[setup-browser] WARNING: Gateway not ready after 60 attempts, starting Chrome anyway"
    fi
    echo "[setup-browser] Gateway not ready, attempt $i/60..."
    sleep 5
done

# Give gateway a few more seconds to stabilize
sleep 5

# ---------------------------------------------------------------------------
# Helper: approve ALL pending device pairing requests
# ---------------------------------------------------------------------------
approve_pending_devices() {
    echo "[setup-browser] Checking for pending device pairing requests..."

    # Method 1: Approve via CLI (preferred)
    PENDING=$(openclaw devices list --token "$OPENCLAW_GATEWAY_TOKEN" 2>&1 || true)
    echo "[setup-browser] Devices output: $PENDING"

    # Extract request IDs from pending devices and approve them
    echo "$PENDING" | grep -oE '[0-9a-f]{8,}' | while read -r id; do
        echo "[setup-browser] Approving device: $id"
        openclaw devices approve "$id" --token "$OPENCLAW_GATEWAY_TOKEN" 2>&1 || true
    done

    # Method 2: Direct file manipulation as fallback
    PENDING_FILE="/root/.openclaw/devices/pending.json"
    PAIRED_FILE="/root/.openclaw/devices/paired.json"

    if [ -f "$PENDING_FILE" ] && [ -s "$PENDING_FILE" ]; then
        echo "[setup-browser] Found pending.json, merging into paired.json..."
        node -e "
const fs = require('fs');
const pendingPath = '$PENDING_FILE';
const pairedPath = '$PAIRED_FILE';

try {
    const pending = JSON.parse(fs.readFileSync(pendingPath, 'utf8'));
    let paired = {};
    try { paired = JSON.parse(fs.readFileSync(pairedPath, 'utf8')); } catch(e) {}

    let approved = 0;
    for (const [id, device] of Object.entries(pending)) {
        if (!paired[id]) {
            const d = { ...device };
            d.approvedAtMs = Date.now();
            d.roles = d.roles || ['operator'];
            if (d.tokens && d.tokens.operator) {
                d.tokens.operator.scopes = [
                    'operator.read', 'operator.write',
                    'operator.pairing', 'operator.admin'
                ];
            }
            paired[id] = d;
            approved++;
            console.log('[setup-browser] Auto-approved device: ' + id.substring(0, 16) + '...');
        }
    }

    if (approved > 0) {
        fs.writeFileSync(pairedPath, JSON.stringify(paired, null, 2));
        fs.writeFileSync(pendingPath, '{}');
        console.log('[setup-browser] Approved ' + approved + ' pending device(s)');
    } else {
        console.log('[setup-browser] No new pending devices to approve');
    }
} catch(e) {
    console.log('[setup-browser] Pending device approval error: ' + e.message);
}
" 2>&1
    else
        echo "[setup-browser] No pending.json found or empty"
    fi
}

# ---------------------------------------------------------------------------
# Launch Chrome directly with CDP on port 18800
# Bypasses the broken browser control service (port 18791 Docker bug)
# ---------------------------------------------------------------------------
echo "[setup-browser] Launching Chrome directly with CDP on port 18800..."

CHROME_DATA_DIR="/root/.openclaw/browser/openclaw/user-data"
mkdir -p "$CHROME_DATA_DIR"

google-chrome-stable \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --remote-debugging-port=18800 \
    --user-data-dir="$CHROME_DATA_DIR" \
    --window-size=1280,720 \
    --display=:99 \
    about:blank &

CHROME_PID=$!
echo "[setup-browser] Chrome launched with PID $CHROME_PID"

# Wait for Chrome CDP to be reachable
for i in $(seq 1 30); do
    if curl -sf http://127.0.0.1:18800/json/version > /dev/null 2>&1; then
        echo "[setup-browser] Chrome CDP is responding on port 18800"
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "[setup-browser] WARNING: Chrome CDP not responding after 30 attempts"
    fi
    sleep 2
done

# Approve pending devices
sleep 3
approve_pending_devices

# Show port status
echo "[setup-browser] Port status:"
netstat -tlnp 2>/dev/null | grep -E '187|18800' || ss -tlnp 2>/dev/null | grep -E '187|18800' || echo "[setup-browser] Could not check ports"

echo "[setup-browser] Setup complete. Chrome running on CDP port 18800."

# Keep script alive for supervisord (and monitor Chrome)
while kill -0 $CHROME_PID 2>/dev/null; do
    sleep 30
done

echo "[setup-browser] Chrome process exited, restarting..."
exec "$0"

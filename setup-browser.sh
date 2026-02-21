#!/bin/bash
# Setup script: waits for gateway to stabilize, then starts managed browser profile.
# The managed profile (openclaw.json browser.defaultProfile="openclaw") handles
# Chrome launch, CDP connection, and extension relay automatically.
#
# After browser start, any pending devices are auto-approved so the browser tool
# can connect back to the gateway without manual intervention (fixes 1008 pairing
# errors in Docker / headless environments).

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
    # Move any pending devices directly to paired.json
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
            // Copy pending device to paired, add approval timestamp and full scopes
            const d = { ...device };
            d.approvedAtMs = Date.now();
            d.roles = d.roles || ['operator'];
            // Ensure tokens have full operator scopes
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
# Start the managed browser profile with retries + auto-approval
# ---------------------------------------------------------------------------
echo "[setup-browser] Starting managed browser profile..."
BROWSER_STARTED=false

for attempt in $(seq 1 10); do
    if openclaw browser start --profile openclaw --token "$OPENCLAW_GATEWAY_TOKEN" 2>&1; then
        echo "[setup-browser] Browser started successfully on attempt $attempt"
        BROWSER_STARTED=true
        break
    fi

    echo "[setup-browser] Browser start attempt $attempt failed"

    # After first failure, try approving pending devices (browser start may have
    # created a pending device entry that needs approval)
    sleep 3
    approve_pending_devices
    sleep 5

    if [ "$attempt" -eq 10 ]; then
        echo "[setup-browser] ERROR: Browser start failed after 10 attempts"
    else
        echo "[setup-browser] Retrying in 5s..."
        sleep 5
    fi
done

# Even if browser start "succeeded", approve any pending devices that the
# browser tool might need when the agent later calls navigate/click/etc.
sleep 3
approve_pending_devices

# Check browser status
echo "[setup-browser] Browser status:"
openclaw browser status --token "$OPENCLAW_GATEWAY_TOKEN" 2>&1 || echo "[setup-browser] Status check failed"

# Show port status
echo "[setup-browser] Port status:"
netstat -tlnp 2>/dev/null | grep -E '187|18800' || ss -tlnp 2>/dev/null | grep -E '187|18800' || echo "[setup-browser] Could not check ports"

echo "[setup-browser] Setup complete."

# Keep script alive for supervisord
exec sleep infinity

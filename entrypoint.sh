#!/bin/bash
set -e

WORKSPACE="/root/.openclaw/workspace"
CONFIG_DIR="/root/.openclaw"

# If CONFIG_URL is set, fetch config from our marketplace server
if [ -n "$CONFIG_URL" ]; then
  echo "[entrypoint] Fetching config from $CONFIG_URL"

  CONFIG_JSON=$(curl -sf --retry 3 --retry-delay 5 "$CONFIG_URL" 2>/dev/null || echo "")

  if [ -n "$CONFIG_JSON" ] && echo "$CONFIG_JSON" | jq . > /dev/null 2>&1; then
    echo "[entrypoint] Config fetched successfully"

    # Write openclaw.json
    echo "$CONFIG_JSON" | jq -r '.openclawJson // empty' > /tmp/openclaw_config.json 2>/dev/null
    if [ -s /tmp/openclaw_config.json ] && [ "$(cat /tmp/openclaw_config.json)" != "null" ]; then
      cp /tmp/openclaw_config.json "$CONFIG_DIR/openclaw.json"
      echo "[entrypoint] Wrote openclaw.json"
    fi

    # Write workspace markdown files
    mkdir -p "$WORKSPACE"

    for field in soulMd:SOUL.md identityMd:IDENTITY.md agentsMd:AGENTS.md userMd:USER.md heartbeatMd:HEARTBEAT.md; do
      key="${field%%:*}"
      filename="${field##*:}"
      content=$(echo "$CONFIG_JSON" | jq -r ".${key} // empty" 2>/dev/null)
      if [ -n "$content" ] && [ "$content" != "null" ]; then
        echo "$content" > "$WORKSPACE/$filename"
        echo "[entrypoint] Wrote $filename"
      fi
    done

    echo "[entrypoint] Config injection complete"

    # Install skills from config bundle
    SKILLS_DIR="$WORKSPACE/skills"
    mkdir -p "$SKILLS_DIR"

    SKILL_COUNT=$(echo "$CONFIG_JSON" | jq '.skills | length' 2>/dev/null || echo "0")

    if [ "$SKILL_COUNT" -gt 0 ]; then
      echo "[entrypoint] Installing $SKILL_COUNT skills..."

      for i in $(seq 0 $(($SKILL_COUNT - 1))); do
        SLUG=$(echo "$CONFIG_JSON" | jq -r ".skills[$i].slug // empty" 2>/dev/null)
        CONTENT=$(echo "$CONFIG_JSON" | jq -r ".skills[$i].content // empty" 2>/dev/null)

        if [ -z "$SLUG" ]; then
          continue
        fi

        mkdir -p "$SKILLS_DIR/$SLUG"

        if [ -n "$CONTENT" ] && [ "$CONTENT" != "null" ]; then
          # Inline content provided — write directly
          echo "$CONTENT" > "$SKILLS_DIR/$SLUG/SKILL.md"
          echo "[entrypoint] Installed skill (inline): $SLUG"
        else
          # Download from ClawHub public API
          echo "[entrypoint] Downloading skill: $SLUG"
          TMPZIP="/tmp/skill-${SLUG}.zip"
          if curl -sf --retry 2 --retry-delay 3 --max-time 30 \
            "https://clawhub.ai/api/v1/download?slug=${SLUG}&tag=latest" \
            -o "$TMPZIP" 2>/dev/null; then
            unzip -o -q "$TMPZIP" -d "$SKILLS_DIR/$SLUG" 2>/dev/null
            rm -f "$TMPZIP"
            echo "[entrypoint] Installed skill (downloaded): $SLUG"
          else
            echo "[entrypoint] WARNING: Failed to download skill: $SLUG"
          fi
        fi
      done
    fi
  else
    echo "[entrypoint] WARNING: Failed to fetch or parse config, using defaults"
  fi
else
  echo "[entrypoint] No CONFIG_URL set, using baked-in defaults"
fi

# Ensure --allow-unconfigured flag is present (handles cached Docker layers)
if ! grep -q 'allow-unconfigured' /etc/supervisor/conf.d/supervisord.conf; then
  sed -i 's|openclaw gateway --port 18790|openclaw gateway --port 18790 --allow-unconfigured|' /etc/supervisor/conf.d/supervisord.conf
  echo "[entrypoint] Patched supervisord.conf with --allow-unconfigured"
fi

# Pre-seed device pairing so the relay server can connect with operator scopes.
# Derives a deterministic ed25519 keypair from OPENCLAW_GATEWAY_TOKEN via HKDF,
# then writes the device entry to paired.json before the gateway starts.
mkdir -p "$CONFIG_DIR/devices"
node -e "
const crypto = require('crypto');
const fs = require('fs');
const token = process.env.OPENCLAW_GATEWAY_TOKEN || 'openclaw-default-token';
const seed = Buffer.from(crypto.hkdfSync('sha256', token, 'openclaw-device-seed', 'gleel2-relay-device', 32));
const keyObj = crypto.createPrivateKey({ key: Buffer.concat([Buffer.from('302e020100300506032b657004220420','hex'), seed]), format: 'der', type: 'pkcs8' });
const pubKey = crypto.createPublicKey(keyObj);
const pubDer = pubKey.export({ type: 'spki', format: 'der' });
const rawPubKey = pubDer.slice(pubDer.length - 32);
const deviceId = crypto.createHash('sha256').update(rawPubKey).digest('hex');
const pubKeyB64url = Buffer.from(rawPubKey).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
const deviceToken = crypto.createHmac('sha256', token).update('gleel2-device-token').digest('hex').substring(0, 48);
const entry = [{
  deviceId, publicKey: pubKeyB64url, displayName: 'gleel2-relay',
  platform: 'linux', clientId: 'gateway-client', clientMode: 'backend', roles: ['operator'],
  tokens: { operator: { token: deviceToken, role: 'operator',
    scopes: ['operator.read','operator.write','operator.pairing','operator.admin'],
    createdAtMs: Date.now() }},
  createdAtMs: Date.now(), approvedAtMs: Date.now(), remoteIp: '127.0.0.1'
}];
const path = (process.env.OPENCLAW_STATE_DIR || '/root/.openclaw') + '/devices/paired.json';
fs.writeFileSync(path, JSON.stringify(entry, null, 2));
console.log('[entrypoint] Pre-seeded device: ' + deviceId.substring(0, 16) + '...');
" 2>&1 && echo "[entrypoint] Device pairing pre-seeded" || echo "[entrypoint] WARNING: Failed to pre-seed device pairing"

# Start supervisord (which manages all services)
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf

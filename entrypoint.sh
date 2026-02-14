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
  else
    echo "[entrypoint] WARNING: Failed to fetch or parse config, using defaults"
  fi
else
  echo "[entrypoint] No CONFIG_URL set, using baked-in defaults"
fi

# Start supervisord (which manages all services)
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf

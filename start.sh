#!/bin/bash
set -e

# Start virtual display
Xvfb :99 -screen 0 1920x1080x24 &
sleep 2

# Start VNC server (no password for simplicity)
x11vnc -display :99 -forever -shared -rfbport 5900 -nopw &
sleep 1

# Start noVNC web interface on port 6080
websockify --web=/usr/share/novnc 6080 localhost:5900 &

# Start OpenClaw Gateway (control UI on port 18789)
openclaw gateway --port 18789 --allow-unconfigured --verbose

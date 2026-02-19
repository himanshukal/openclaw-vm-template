#!/bin/bash
# Chrome wrapper script that adds memory-saving flags.
# OpenClaw's managed browser profile calls executablePath to launch Chrome.
# This wrapper intercepts that call and injects flags to prevent OOM on Railway.

exec /usr/bin/google-chrome-stable \
  --disable-dev-shm-usage \
  --disable-gpu \
  --disable-software-rasterizer \
  --renderer-process-limit=2 \
  --js-flags="--max-old-space-size=256" \
  --disable-features=IsolateOrigins,site-per-process \
  --disable-extensions-except=nglingapjinhecnfejdcpihlpneeadjp \
  --single-process \
  "$@"

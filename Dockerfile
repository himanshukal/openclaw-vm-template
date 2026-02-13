FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:99

# Install system dependencies including lightweight desktop
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    gnupg \
    xvfb \
    x11vnc \
    novnc \
    websockify \
    fonts-liberation \
    libnss3 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    libpango-1.0-0 \
    libcairo2 \
    supervisor \
    git \
    xterm \
    openbox \
    menu \
    dbus-x11 \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Google Chrome (NOT Chromium - required for Claude Extension)
RUN wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs

# Install pnpm and OpenClaw
RUN npm install -g pnpm openclaw@latest

# Create directories
RUN mkdir -p /root/.openclaw /var/log/supervisor /root/.config/google-chrome/Default/Extensions

# Verify OpenClaw installation
RUN openclaw --version || echo "OpenClaw installed"

# Pre-install Chrome extensions
# Claude Chrome Extension ID: fcoeoabgfenejglbffodgkkbkcdhcgfn
# OpenClaw Browser Relay ID: nglingapjinhecnfejdcpihlpneeadjp
# Note: Extensions will be downloaded on first Chrome launch or can be force-installed via policy

# Create Chrome policy directory for extension management
RUN mkdir -p /etc/opt/chrome/policies/managed

# Force-install extensions via Chrome policy
# This tells Chrome to install these extensions automatically
RUN echo '{ \
  "ExtensionInstallForcelist": [ \
    "fcoeoabgfenejglbffodgkkbkcdhcgfn;https://clients2.google.com/service/update2/crx", \
    "nglingapjinhecnfejdcpihlpneeadjp;https://clients2.google.com/service/update2/crx" \
  ], \
  "ExtensionInstallAllowlist": [ \
    "fcoeoabgfenejglbffodgkkbkcdhcgfn", \
    "nglingapjinhecnfejdcpihlpneeadjp" \
  ] \
}' > /etc/opt/chrome/policies/managed/extensions.json

# Copy configuration and startup files
COPY openclaw.json /root/.openclaw/openclaw.json
COPY start.sh /start.sh
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
RUN chmod +x /start.sh

# Expose ports: 6080 (noVNC), 18789 (OpenClaw Gateway)
EXPOSE 6080 18789

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]

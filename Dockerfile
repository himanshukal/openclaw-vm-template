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
    socat \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install Google Chrome (required for OpenClaw browser automation)
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
RUN mkdir -p /root/.openclaw/workspace /var/log/supervisor

# Environment variables (can be overridden at runtime)
ENV OPENCLAW_GATEWAY_TOKEN=openclaw-default-token
ENV NVIDIA_API_KEY=

# Verify OpenClaw installation
RUN openclaw --version || echo "OpenClaw installed"

# Copy configuration and startup files
COPY openclaw.json /root/.openclaw/openclaw.json
COPY start.sh /start.sh
COPY entrypoint.sh /entrypoint.sh
COPY setup-browser.sh /setup-browser.sh
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
RUN chmod +x /start.sh /entrypoint.sh /setup-browser.sh

# Expose ports: 6080 (noVNC), 18789 (OpenClaw Gateway)
EXPOSE 6080 18789

CMD ["/entrypoint.sh"]

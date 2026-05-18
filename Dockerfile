FROM debian:13.4

ENV PYTHONUNBUFFERED=1
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential curl nodejs npm \
    python3 python3-pip python3-venv \
    ripgrep ffmpeg git tini \
    procps openssh-client && \
    rm -rf /var/lib/apt/lists/*

# gosu: privilege-drop helper used by entrypoint.sh (root -> hermes user)
RUN dpkgArch="$(dpkg --print-architecture | awk -F- '{print $NF}')" && \
    curl -fsSL "https://github.com/tianon/gosu/releases/download/1.17/gosu-${dpkgArch}" \
         -o /usr/local/bin/gosu && \
    chmod +x /usr/local/bin/gosu && \
    gosu --version

RUN useradd -u 10000 -m -d /opt/data hermes

# Install hermes into a venv; entrypoint.sh and railway-start.sh expect
# the CLI at ${INSTALL_DIR}/.venv/bin/hermes = /opt/hermes/.venv/bin/hermes
RUN mkdir -p /opt/hermes && \
    python3 -m venv /opt/hermes/.venv && \
    /opt/hermes/.venv/bin/pip install --upgrade pip

RUN /opt/hermes/.venv/bin/pip install --no-cache-dir "hermes-agent[all]"

# playwright executable is not shipped by hermes-agent[all]; install the Python
# package for import compatibility but skip the ~700 MB browser download —
# the Telegram gateway doesn't need a browser.
RUN /opt/hermes/.venv/bin/pip install --no-cache-dir playwright

# Deployment scripts and provider config
COPY docker/ /opt/hermes/docker/
COPY anthropic-config.yaml /opt/hermes/

# entrypoint.sh copies cli-config.yaml.example on first boot — use our
# anthropic config as the seed so the default provider is always Anthropic
RUN cp /opt/hermes/anthropic-config.yaml /opt/hermes/cli-config.yaml.example && \
    touch /opt/hermes/.env.example && \
    chmod 0755 /opt/hermes/docker/entrypoint.sh /opt/hermes/docker/railway-start.sh && \
    chmod -R a+rX /opt/hermes

# Detect web asset path and bake it into the venv activate script so that
# `hermes dashboard` can find its SPA regardless of Python version in site-packages.
# Uses find rather than a fragile Python import so any module name works.
RUN web_dist="$(find /opt/hermes/.venv -name 'web_dist' -type d 2>/dev/null | head -1)" && \
    if [ -n "$web_dist" ]; then \
      echo "export HERMES_WEB_DIST=${web_dist}" >> /opt/hermes/.venv/bin/activate && \
      echo "[build] Baked HERMES_WEB_DIST=${web_dist}"; \
    else \
      echo "[build] WARNING: web_dist not found — dashboard SPA may not load"; \
      find /opt/hermes/.venv/lib -maxdepth 4 -name '*.dist-info' -type d | head -10 || true; \
    fi

ENV HERMES_HOME=/opt/data

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/opt/hermes/docker/entrypoint.sh"]

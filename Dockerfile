FROM debian:13.4

ENV PYTHONUNBUFFERED=1
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential curl nodejs npm \
    python3 python3-pip python3-venv \
    ripgrep ffmpeg git tini \
    procps openssh-client libopus0 portaudio19-dev && \
    rm -rf /var/lib/apt/lists/*

# gosu: privilege-drop helper used by entrypoint.sh (root -> hermes user)
RUN dpkgArch="$(dpkg --print-architecture | awk -F- '{print $NF}')" && \
    curl -fsSL "https://github.com/tianon/gosu/releases/download/1.17/gosu-${dpkgArch}" \
         -o /usr/local/bin/gosu && \
    chmod +x /usr/local/bin/gosu && \
    gosu --version

RUN useradd -u 10000 -m -d /opt/data hermes

# Pin the exact Hermes release that was current when this fork last ran on Railway.
# This prevents a future Docker rebuild from silently changing agent behaviour.
RUN mkdir -p /opt/hermes && \
    python3 -m venv /opt/hermes/.venv && \
    /opt/hermes/.venv/bin/pip install --upgrade pip

RUN /opt/hermes/.venv/bin/pip install --no-cache-dir "hermes-agent[all]==0.15.2"

# HERMES-PATCH: preserve /model selection across /new — see
# docker/patch_hermes.py for the bug description and the exact 4-line
# block we comment out in gateway/run.py.
COPY docker/patch_hermes.py /tmp/patch_hermes.py
RUN /opt/hermes/.venv/bin/python /tmp/patch_hermes.py \
      "$(/opt/hermes/.venv/bin/python -c 'import sys; print(sys.prefix + "/lib/python" + sys.version[:4] + "/site-packages")')" \
    && rm /tmp/patch_hermes.py

# playwright executable is not shipped by hermes-agent[all]; install the Python
# package for import compatibility but skip the ~700 MB browser download —
# the Telegram gateway doesn't need a browser.
RUN /opt/hermes/.venv/bin/pip install --no-cache-dir playwright

# Install specialized Python dependencies for the advanced agent skills
RUN /opt/hermes/.venv/bin/pip install --no-cache-dir \
    youtube-transcript-api \
    pymupdf \
    pygithub \
    notion-client \
    jupyter-client \
    ipykernel \
    faster-whisper \
    openpyxl \
    pillow

# Install Chromium browser and its system dependencies for local browsing
RUN /opt/hermes/.venv/bin/playwright install --with-deps chromium

# Deployment scripts, advanced skills, plugins, locales, and provider configs
COPY docker/ /opt/hermes/docker/
COPY skills/ /opt/hermes/skills/
COPY plugins/ /opt/hermes/plugins/
COPY locales/ /opt/hermes/locales/
COPY anthropic-config.yaml gemini-config.yaml dual-config.yaml /opt/hermes/

# Copy plugins and locales to the correct site-packages paths so the Python application can resolve them
RUN site_packages="$(/opt/hermes/.venv/bin/python -c 'import sys; print(sys.prefix + "/lib/python" + sys.version[:4] + "/site-packages")')" && \
    cp -rf /opt/hermes/plugins "$site_packages/plugins" && \
    cp -rf /opt/hermes/locales "$site_packages/locales"


# entrypoint.sh copies cli-config.yaml.example on first boot — use dual-config.yaml as the
# default seed (supporting Gemini + Anthropic Claude + Z.AI GLM).
# Switch providers in Telegram via /model — selection persists in /opt/data.
RUN cp /opt/hermes/dual-config.yaml /opt/hermes/cli-config.yaml.example && \
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

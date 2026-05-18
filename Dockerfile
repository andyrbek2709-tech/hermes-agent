FROM tianon/gosu:1.19-trixie AS gosu_source
FROM debian:13.4

ENV PYTHONUNBUFFERED=1
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential curl nodejs npm \
    python3 python3-pip python3-venv \
    ripgrep ffmpeg git tini \
    procps openssh-client && \
    rm -rf /var/lib/apt/lists/*

# gosu: used by entrypoint.sh to drop from root to the hermes user
COPY --chmod=0755 --from=gosu_source /gosu /usr/local/bin/

RUN useradd -u 10000 -m -d /opt/data hermes

# Install hermes from PyPI into a venv at the path entrypoint/railway-start.sh expect
RUN mkdir -p /opt/hermes && python3 -m venv /opt/hermes/.venv
RUN /opt/hermes/.venv/bin/pip install --no-cache-dir "hermes-agent[all]"

# Playwright browser (stored outside /opt/data so it survives volume mounts)
RUN /opt/hermes/.venv/bin/playwright install --with-deps chromium

# Deployment scripts and provider config
COPY docker/ /opt/hermes/docker/
COPY anthropic-config.yaml /opt/hermes/

# entrypoint.sh copies these on first boot; use anthropic-config as the default
RUN cp /opt/hermes/anthropic-config.yaml /opt/hermes/cli-config.yaml.example && \
    touch /opt/hermes/.env.example

RUN chmod 0755 /opt/hermes/docker/entrypoint.sh /opt/hermes/docker/railway-start.sh && \
    chmod -R a+rX /opt/hermes

ENV HERMES_HOME=/opt/data

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/opt/hermes/docker/entrypoint.sh"]

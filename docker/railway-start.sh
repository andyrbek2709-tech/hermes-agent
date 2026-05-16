#!/usr/bin/env bash
# Railway: HTTP on $PORT (dashboard) + Telegram gateway in background.
# Invoked as: bash -c 'exec /opt/hermes/docker/railway-start.sh'
# so docker/entrypoint.sh runs first (dirs, optional HERMES_DASHBOARD).
#
# Public URL 502? In Railway → Settings → Networking, the "target port" for your
# *.up.railway.app domain MUST match $PORT here (see deploy logs, e.g. 8080).
# A stale "→ Port 9119" routes traffic to the wrong socket.
# We do NOT rely on PATH: Railway may exec this script without entrypoint's
# `source .venv/bin/activate`, and Railpack images may omit the shim entirely.
# Use the venv console script path baked into the official Dockerfile layout.
#
# In Railway Variables, turn OFF HERMES_DASHBOARD / HERMES_DASHBOARD_PORT when
# using this script — otherwise entrypoint starts a second dashboard on 9119.
# For 502 / edge timeouts during debugging: HERMES_RAILWAY_SKIP_GATEWAY=1 runs
# only the dashboard on $PORT (no background gateway).

set -euo pipefail

# Railway environment variables (automatically injected)
export RAILWAY_ENVIRONMENT="${RAILWAY_ENVIRONMENT:-development}"
export RAILWAY_PROJECT_ID="${RAILWAY_PROJECT_ID:-unknown}"
export RAILWAY_SERVICE_NAME="${RAILWAY_SERVICE_NAME:-unknown}"

INSTALL_DIR="${INSTALL_DIR:-/opt/hermes}"
HERMES_HOME="${HERMES_HOME:-/opt/data}"
VENV_BIN="${INSTALL_DIR}/.venv/bin"
HERMES_CLI="${VENV_BIN}/hermes"

# Logging configuration
exec 3>&1 4>&2
trap 'echo "ERROR: Railway startup failed at line $LINENO" >&3; exit 1' ERR

if [[ ! -x "${HERMES_CLI}" ]]; then
  echo "error: Hermes CLI not found at ${HERMES_CLI} (wrong image or build stage?)" >&2
  ls -la "${VENV_BIN}" 2>&1 || true
  exit 127
fi

# Prefer venv on PATH for any child tools (node, uv, etc.).
# shellcheck source=/dev/null
[[ -f "${VENV_BIN}/activate" ]] && source "${VENV_BIN}/activate"

# Never fail startup if a bundled template is missing (image mismatch / old layer).
if [[ -f "${INSTALL_DIR}/openai-config.yaml" ]]; then
  cp -f "${INSTALL_DIR}/openai-config.yaml" "${HERMES_HOME}/config.yaml" || true
elif [[ -f "${INSTALL_DIR}/gemini-config.yaml" ]]; then
  cp -f "${INSTALL_DIR}/gemini-config.yaml" "${HERMES_HOME}/config.yaml" || true
fi

DASH_PORT="${PORT:-9119}"

# Optional: set HERMES_RAILWAY_SKIP_GATEWAY=1 in Railway Variables to isolate HTTP
# issues (502 / "failed to respond") from the Telegram gateway subprocess.
if [[ "${HERMES_RAILWAY_SKIP_GATEWAY:-}" == "1" ]]; then
  echo "HERMES_RAILWAY_SKIP_GATEWAY=1 — skipping background gateway"
else
  "${HERMES_CLI}" gateway run &
fi
exec "${HERMES_CLI}" dashboard --host 0.0.0.0 --port "${DASH_PORT}" --insecure --no-open

#!/usr/bin/env bash
# Railway: dashboard on $PORT (background, health checks) +
# gateway in a supervised restart loop.
#
# WHY THIS EXISTS: the previous script did `gateway run &` then `exec dashboard`.
# When the user sends /restart via Telegram the gateway exits, but the dashboard
# keeps the container alive — so the bot stays dead until a manual Railway restart.
# This script wraps the gateway in a restart loop so it recovers automatically.
#
# Public URL 502? In Railway → Settings → Networking, the "target port" for your
# *.up.railway.app domain MUST match $PORT here (see deploy logs, e.g. 8080).
#
# We do NOT rely on PATH: Railway may exec this script without entrypoint's
# `source .venv/bin/activate`, and Railpack images may omit the shim entirely.
# Use the venv console script path baked into the official Dockerfile layout.
#
# In Railway Variables, turn OFF HERMES_DASHBOARD / HERMES_DASHBOARD_PORT when
# using this script — otherwise entrypoint starts a second dashboard on 9119.
# For 502 / edge timeouts during debugging: HERMES_RAILWAY_SKIP_GATEWAY=1 runs
# only the dashboard on $PORT (no background gateway).

set -uo pipefail

# Railway environment variables (automatically injected)
export RAILWAY_ENVIRONMENT="${RAILWAY_ENVIRONMENT:-development}"
export RAILWAY_PROJECT_ID="${RAILWAY_PROJECT_ID:-unknown}"
export RAILWAY_SERVICE_NAME="${RAILWAY_SERVICE_NAME:-unknown}"

INSTALL_DIR="${INSTALL_DIR:-/opt/hermes}"
HERMES_HOME="${HERMES_HOME:-/opt/data}"
VENV_BIN="${INSTALL_DIR}/.venv/bin"
HERMES_CLI="${VENV_BIN}/hermes"

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
  exec "${HERMES_CLI}" dashboard --host 0.0.0.0 --port "${DASH_PORT}" --insecure --no-open
fi

# Start the dashboard in the background so it survives gateway restarts and
# continues to serve Railway health checks on $PORT.
"${HERMES_CLI}" dashboard --host 0.0.0.0 --port "${DASH_PORT}" --insecure --no-open &
DASH_PID=$!
echo "Dashboard started (PID ${DASH_PID}) on port ${DASH_PORT}"

# On exit (SIGTERM from Railway, CTRL-C, etc.) cleanly stop the dashboard too.
cleanup() {
  echo "Shutting down..."
  kill "${DASH_PID}" 2>/dev/null || true
  wait "${DASH_PID}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Gateway restart loop.
# Sending /restart via Telegram causes the gateway process to exit; we restart
# it here automatically so the bot recovers without a manual Railway restart.
RESTART_DELAY=3
while true; do
  echo "Starting gateway..."
  "${HERMES_CLI}" gateway run &
  GATEWAY_PID=$!

  # Wait for the gateway to exit, checking every 2 s that the dashboard is
  # still alive.  If the dashboard dies we exit so Railway restarts the container.
  while kill -0 "${GATEWAY_PID}" 2>/dev/null; do
    if ! kill -0 "${DASH_PID}" 2>/dev/null; then
      echo "Dashboard exited unexpectedly; triggering container restart"
      kill "${GATEWAY_PID}" 2>/dev/null || true
      exit 1
    fi
    sleep 2
  done

  wait "${GATEWAY_PID}" || true
  echo "Gateway exited; restarting in ${RESTART_DELAY}s..."
  sleep "${RESTART_DELAY}"
done

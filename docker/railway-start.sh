#!/usr/bin/env bash
# Railway: dashboard on $PORT (background, health checks) +
# gateway in a supervised restart loop.

set -uo pipefail

export RAILWAY_ENVIRONMENT="${RAILWAY_ENVIRONMENT:-development}"
export RAILWAY_PROJECT_ID="${RAILWAY_PROJECT_ID:-unknown}"
export RAILWAY_SERVICE_NAME="${RAILWAY_SERVICE_NAME:-unknown}"

INSTALL_DIR="${INSTALL_DIR:-/opt/hermes}"
HERMES_HOME="${HERMES_HOME:-/opt/data}"
VENV_BIN="${INSTALL_DIR}/.venv/bin"
HERMES_CLI="${VENV_BIN}/hermes"

# ── Diagnostics (visible in Railway → Deploy Logs) ──────────────────────────
echo "[startup] HERMES_CLI=${HERMES_CLI}"
echo "[startup] HERMES_HOME=${HERMES_HOME}"
echo "[startup] HERMES_WEB_DIST=${HERMES_WEB_DIST:-UNSET}"
echo "[startup] PORT=${PORT:-UNSET}"

if [[ ! -x "${HERMES_CLI}" ]]; then
  echo "[startup] ERROR: CLI not found at ${HERMES_CLI}" >&2
  ls -la "${VENV_BIN}" 2>&1 || true
  exit 127
fi

echo "[startup] hermes version: $("${HERMES_CLI}" --version 2>&1 | head -1 || echo unknown)"

# Prefer venv on PATH for any child tools (node, uv, etc.).
# shellcheck source=/dev/null
[[ -f "${VENV_BIN}/activate" ]] && source "${VENV_BIN}/activate"

echo "[startup] HERMES_WEB_DIST after activate=${HERMES_WEB_DIST:-UNSET}"

# Apply provider config on every start so Railway env-var changes take effect.
if [[ -f "${INSTALL_DIR}/anthropic-config.yaml" ]]; then
  cp -f "${INSTALL_DIR}/anthropic-config.yaml" "${HERMES_HOME}/config.yaml" || true
  echo "[startup] Applied anthropic-config.yaml"
elif [[ -f "${INSTALL_DIR}/openai-config.yaml" ]]; then
  cp -f "${INSTALL_DIR}/openai-config.yaml" "${HERMES_HOME}/config.yaml" || true
elif [[ -f "${INSTALL_DIR}/gemini-config.yaml" ]]; then
  cp -f "${INSTALL_DIR}/gemini-config.yaml" "${HERMES_HOME}/config.yaml" || true
fi

DASH_PORT="${PORT:-9119}"

if [[ "${HERMES_RAILWAY_SKIP_GATEWAY:-}" == "1" ]]; then
  echo "[startup] HERMES_RAILWAY_SKIP_GATEWAY=1 — dashboard only"
  exec "${HERMES_CLI}" dashboard --host 0.0.0.0 --port "${DASH_PORT}" --insecure --no-open
fi

# Start dashboard in background; capture its output so errors show in Deploy Logs.
echo "[startup] Starting dashboard on port ${DASH_PORT}..."
"${HERMES_CLI}" dashboard --host 0.0.0.0 --port "${DASH_PORT}" --insecure --no-open 2>&1 &
DASH_PID=$!

# Wait up to 10 s for the dashboard to stay alive.
sleep 5
if kill -0 "${DASH_PID}" 2>/dev/null; then
  echo "[startup] Dashboard running (PID ${DASH_PID})"
else
  echo "[startup] ERROR: Dashboard exited within 5s — check output above" >&2
  exit 1
fi

cleanup() {
  echo "[startup] Shutting down..."
  kill "${DASH_PID}" 2>/dev/null || true
  wait "${DASH_PID}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Gateway restart loop — /restart in Telegram exits the gateway; restart it here.
RESTART_DELAY=3
while true; do
  echo "[startup] Starting gateway..."
  "${HERMES_CLI}" gateway run 2>&1 &
  GATEWAY_PID=$!

  while kill -0 "${GATEWAY_PID}" 2>/dev/null; do
    if ! kill -0 "${DASH_PID}" 2>/dev/null; then
      echo "[startup] Dashboard died unexpectedly; triggering container restart" >&2
      kill "${GATEWAY_PID}" 2>/dev/null || true
      exit 1
    fi
    sleep 2
  done

  wait "${GATEWAY_PID}" || true
  echo "[startup] Gateway exited; restarting in ${RESTART_DELAY}s..."
  sleep "${RESTART_DELAY}"
done

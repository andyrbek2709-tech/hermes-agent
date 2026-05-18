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
echo "[startup] PORT=${PORT:-UNSET}"

if [[ ! -x "${HERMES_CLI}" ]]; then
  echo "[startup] ERROR: CLI not found at ${HERMES_CLI}" >&2
  ls -la "${VENV_BIN}" 2>&1 || true
  exit 127
fi

echo "[startup] hermes version: $("${HERMES_CLI}" --version 2>&1 | head -1 || echo unknown)"

# Prefer venv on PATH for any child tools.
# shellcheck source=/dev/null
[[ -f "${VENV_BIN}/activate" ]] && source "${VENV_BIN}/activate"

echo "[startup] HERMES_WEB_DIST after activate=${HERMES_WEB_DIST:-UNSET}"

# Fallback: detect web_dist via find if not set by activate script.
if [[ -z "${HERMES_WEB_DIST:-}" ]]; then
  FOUND_DIST="$(find "${INSTALL_DIR}/.venv" -name 'web_dist' -type d 2>/dev/null | head -1)"
  if [[ -n "${FOUND_DIST}" ]]; then
    export HERMES_WEB_DIST="${FOUND_DIST}"
    echo "[startup] Auto-detected HERMES_WEB_DIST=${HERMES_WEB_DIST}"
  else
    echo "[startup] WARNING: web_dist not found — dashboard may fail to load SPA" >&2
    find "${INSTALL_DIR}/.venv/lib" -maxdepth 4 -name '*.dist-info' -type d 2>/dev/null | head -10 >&2 || true
  fi
fi

# Seed config.yaml on first boot only; preserve user's /model selection on restarts.
# Override seed via HERMES_PROVIDER_CONFIG=gemini|anthropic|openai (matches *-config.yaml).
if [[ -f "${HERMES_HOME}/config.yaml" ]]; then
  echo "[startup] Preserving existing config.yaml — managed via /model command"
else
  SEED_NAME="${HERMES_PROVIDER_CONFIG:-gemini}"
  SEED_PATH="${INSTALL_DIR}/${SEED_NAME}-config.yaml"
  if [[ ! -f "${SEED_PATH}" ]] && [[ -f "${INSTALL_DIR}/gemini-config.yaml" ]]; then
    SEED_PATH="${INSTALL_DIR}/gemini-config.yaml"
  elif [[ ! -f "${SEED_PATH}" ]] && [[ -f "${INSTALL_DIR}/anthropic-config.yaml" ]]; then
    SEED_PATH="${INSTALL_DIR}/anthropic-config.yaml"
  fi
  if [[ -f "${SEED_PATH}" ]]; then
    cp -f "${SEED_PATH}" "${HERMES_HOME}/config.yaml"
    echo "[startup] Seeded config.yaml from $(basename "${SEED_PATH}") (first boot)"
  else
    echo "[startup] WARNING: no seed config found in ${INSTALL_DIR}"
  fi
fi

DASH_PORT="${PORT:-9119}"
DASH_LOG="/tmp/hermes-dashboard.log"

if [[ "${HERMES_RAILWAY_SKIP_GATEWAY:-}" == "1" ]]; then
  echo "[startup] HERMES_RAILWAY_SKIP_GATEWAY=1 — dashboard only"
  exec "${HERMES_CLI}" dashboard --host 0.0.0.0 --port "${DASH_PORT}" --insecure --no-open
fi

# Start dashboard in background; output goes to log file AND to container logs.
echo "[startup] Starting dashboard on port ${DASH_PORT}..."
"${HERMES_CLI}" dashboard --host 0.0.0.0 --port "${DASH_PORT}" --insecure --no-open \
  > "${DASH_LOG}" 2>&1 &
DASH_PID=$!

# Wait up to 20s for dashboard to stay alive (slow startup on first boot).
DASH_OK=0
for _i in 1 2 3 4; do
  sleep 5
  if kill -0 "${DASH_PID}" 2>/dev/null; then
    echo "[startup] Dashboard running (PID ${DASH_PID}) after ${_i}x5s"
    DASH_OK=1
    break
  fi
done

if [[ ${DASH_OK} -eq 0 ]]; then
  echo "[startup] ERROR: Dashboard exited within 20s — dashboard output:" >&2
  cat "${DASH_LOG}" >&2 || true
  echo "[startup] Starting fallback health server on port ${DASH_PORT} so Railway healthcheck passes" >&2
  # Minimal HTTP 200 server — keeps Railway healthcheck green while gateway runs.
  python3 - "${DASH_PORT}" <<'PYEOF' &
import sys, http.server, socketserver
port = int(sys.argv[1])
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"Hermes gateway running\n")
    def log_message(self, *a): pass
with socketserver.TCPServer(("0.0.0.0", port), H) as s:
    s.serve_forever()
PYEOF
  DASH_PID=$!
  echo "[startup] Fallback health server PID ${DASH_PID}"
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
      echo "[startup] Health server/dashboard died unexpectedly; triggering container restart" >&2
      kill "${GATEWAY_PID}" 2>/dev/null || true
      exit 1
    fi
    sleep 2
  done

  wait "${GATEWAY_PID}" || true
  echo "[startup] Gateway exited; restarting in ${RESTART_DELAY}s..."
  sleep "${RESTART_DELAY}"
done

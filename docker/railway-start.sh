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

# Seed config.yaml on first boot, OR when HERMES_FORCE_RESEED=1 is set (one-shot
# override to recover from a stuck/dead provider — set the env var, redeploy,
# then unset it once the new seed is in place).
# Override seed source via HERMES_PROVIDER_CONFIG=gemini|anthropic|openai
# (matches <name>-config.yaml in /opt/hermes/).
# Auto-recovery: if the active provider in config.yaml has no API key in env,
# treat it as broken and re-seed from default. Prevents the bot from being
# stuck on a dead provider (e.g. Anthropic with paused billing) after the
# user switched providers via /model and then the relevant key was removed.
# Set HERMES_DISABLE_AUTO_RECOVERY=1 to opt out.
AUTO_RECOVER=0
if [[ -f "${HERMES_HOME}/config.yaml" ]] && [[ "${HERMES_DISABLE_AUTO_RECOVERY:-}" != "1" ]]; then
  ACTIVE_PROVIDER="$(sed -n "s/^[[:space:]]*provider:[[:space:]]*[\"']\?\([a-zA-Z]*\)[\"']\?[[:space:]]*$/\1/p" "${HERMES_HOME}/config.yaml" | head -1)"
  case "${ACTIVE_PROVIDER}" in
    anthropic)
      if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then AUTO_RECOVER=1; fi ;;
    openai)
      if [[ -z "${OPENAI_API_KEY:-}" ]]; then AUTO_RECOVER=1; fi ;;
    gemini|google)
      if [[ -z "${GOOGLE_API_KEY:-}" ]] && [[ -z "${GEMINI_API_KEY:-}" ]]; then AUTO_RECOVER=1; fi ;;
    zai)
      if [[ -z "${ZAI_API_KEY:-}" ]]; then AUTO_RECOVER=1; fi ;;
    openrouter)
      if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then AUTO_RECOVER=1; fi ;;
  esac
  if [[ "${AUTO_RECOVER}" == "1" ]]; then
    echo "[startup] AUTO-RECOVERY: active provider '${ACTIVE_PROVIDER}' has no API key in env — reseeding"
    cp -f "${HERMES_HOME}/config.yaml" "${HERMES_HOME}/config.yaml.bak"
  fi
fi

if [[ -f "${HERMES_HOME}/config.yaml" ]] && [[ "${HERMES_FORCE_RESEED:-}" != "1" ]] && [[ "${AUTO_RECOVER}" != "1" ]]; then
  echo "[startup] Preserving existing config.yaml — managed via /model command"
else
  if [[ "${HERMES_FORCE_RESEED:-}" == "1" ]] && [[ -f "${HERMES_HOME}/config.yaml" ]]; then
    cp -f "${HERMES_HOME}/config.yaml" "${HERMES_HOME}/config.yaml.bak"
    echo "[startup] HERMES_FORCE_RESEED=1 — backed up old config.yaml to config.yaml.bak"
  fi
  SEED_NAME="${HERMES_PROVIDER_CONFIG:-dual}"
  SEED_PATH="${INSTALL_DIR}/${SEED_NAME}-config.yaml"
  if [[ ! -f "${SEED_PATH}" ]] && [[ -f "${INSTALL_DIR}/dual-config.yaml" ]]; then
    SEED_PATH="${INSTALL_DIR}/dual-config.yaml"
  elif [[ ! -f "${SEED_PATH}" ]] && [[ -f "${INSTALL_DIR}/gemini-config.yaml" ]]; then
    SEED_PATH="${INSTALL_DIR}/gemini-config.yaml"
  elif [[ ! -f "${SEED_PATH}" ]] && [[ -f "${INSTALL_DIR}/anthropic-config.yaml" ]]; then
    SEED_PATH="${INSTALL_DIR}/anthropic-config.yaml"
  fi
  if [[ -f "${SEED_PATH}" ]]; then
    cp -f "${SEED_PATH}" "${HERMES_HOME}/config.yaml"
    echo "[startup] Seeded config.yaml from $(basename "${SEED_PATH}")"
  else
    echo "[startup] WARNING: no seed config found in ${INSTALL_DIR}"
  fi
fi

# Sync advanced skills to the persistent home directory on boot
if [[ -d "${INSTALL_DIR}/skills" ]]; then
  echo "[startup] Syncing advanced skills to ${HERMES_HOME}/skills/..."
  mkdir -p "${HERMES_HOME}/skills"
  cp -rf "${INSTALL_DIR}/skills/"* "${HERMES_HOME}/skills/"
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
# --replace: kill any stale PID-file owner before binding. Without this, a hung
# gateway from a previous container instance leaves a PID file that blocks every
# subsequent boot in an infinite "Gateway already running" restart loop.
RESTART_DELAY=3
while true; do
  echo "[startup] Starting gateway..."
  "${HERMES_CLI}" gateway run --replace 2>&1 &
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

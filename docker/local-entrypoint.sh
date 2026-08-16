#!/usr/bin/env bash
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-/opt/data}"
INSTALL_DIR="/opt/hermes"
HERMES_CLI="${INSTALL_DIR}/.venv/bin/hermes"

export HERMES_HOME
export HOME="${HERMES_HOME}/home"
export PATH="${INSTALL_DIR}/.venv/bin:${PATH}"

mkdir -p "${HERMES_HOME}"/{cron,sessions,logs,hooks,memories,skills,skins,plans,workspace,home}

# Never overwrite local state after first boot.
if [[ ! -f "${HERMES_HOME}/.env" ]]; then
  : > "${HERMES_HOME}/.env"
fi
if [[ ! -f "${HERMES_HOME}/config.yaml" ]]; then
  cp "${INSTALL_DIR}/cli-config.yaml.example" "${HERMES_HOME}/config.yaml"
fi
if [[ ! -f "${HERMES_HOME}/SOUL.md" ]]; then
  cp "${INSTALL_DIR}/docker/SOUL.md" "${HERMES_HOME}/SOUL.md"
fi
if [[ ! -f "${HERMES_HOME}/memories/USER.md" ]] && [[ -f "${INSTALL_DIR}/docker/memories/USER.md" ]]; then
  cp "${INSTALL_DIR}/docker/memories/USER.md" "${HERMES_HOME}/memories/USER.md"
fi

# Seed bundled skills only when a target file is missing. User-edited skills in
# D:\Hermes\data always win and survive image rebuilds.
python3 - <<'PY'
from pathlib import Path
import shutil

src = Path('/opt/hermes/skills')
dst = Path('/opt/data/skills')
if src.exists():
    for item in src.rglob('*'):
        rel = item.relative_to(src)
        target = dst / rel
        if item.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        elif not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(item, target)
PY

# Docker Desktop bind mounts are usually writable already; chown is best-effort
# and only exists so the non-root hermes process can persist state on other hosts.
if [[ "$(id -u)" == "0" ]]; then
  chown -R hermes:hermes "${HERMES_HOME}" 2>/dev/null || true
  exec gosu hermes env \
    HERMES_HOME="${HERMES_HOME}" \
    HOME="${HOME}" \
    PATH="${PATH}" \
    "${HERMES_CLI}" "$@"
fi

exec "${HERMES_CLI}" "$@"

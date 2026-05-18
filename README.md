# Hermes Agent — Railway Deployment

Production-ready Docker deployment for **Hermes Agent** on Railway.

## 📋 Overview

This repository contains:
- **Dockerfile** — Optimized Docker image with Hermes Agent
- **railway.toml** — Railway.app deployment configuration
- **anthropic-config.yaml** — Default Anthropic Claude Haiku configuration
- **docker/entrypoint.sh** — Container bootstrap with privilege dropping
- **docker/railway-start.sh** — Railway startup script with dashboard + gateway
- **docker/SOUL.md** — Agent personality customization

## 🚀 Quick Start

### 1. Local Docker Build

```bash
docker build -t hermes-agent:latest .
```

### 2. Run Locally

```bash
docker run -it \
  -v $(pwd)/hermes-data:/opt/data \
  -e HERMES_DASHBOARD=1 \
  -e HERMES_DASHBOARD_PORT=9119 \
  -p 9119:9119 \
  hermes-agent:latest
```

Then visit `http://localhost:9119` for the dashboard.

### 3. Deploy to Railway

1. **Connect GitHub**
   ```
   Railway.app → New Project → GitHub Repo
   ```

2. **Add Telegram/API Keys**
   ```
   Variables → Add:
   - TELEGRAM_BOT_TOKEN
   - ANTHROPIC_API_KEY (or other provider keys)
   - PORT (default: 8080, set if needed)
   ```

3. **Deploy**
   Railway auto-deploys on push. Check logs:
   ```
   Railway → Deployments → View Logs
   ```

## 🔧 Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HERMES_HOME` | `/opt/data` | Data volume path |
| `HERMES_DASHBOARD` | `0` | Enable dashboard (1/true) |
| `HERMES_DASHBOARD_PORT` | `9119` | Dashboard port |
| `HERMES_DASHBOARD_HOST` | `0.0.0.0` | Dashboard bind address |
| `PORT` | `8080` | Railway public port (auto-set) |
| `HERMES_UID` | `10000` | Container hermes user UID |
| `HERMES_GID` | `10000` | Container hermes group GID |
| `HERMES_AUTH_JSON_BOOTSTRAP` | — | OAuth bootstrap (first boot only) |
| `HERMES_RAILWAY_SKIP_GATEWAY` | `0` | Dashboard-only mode (1=skip gateway) |

### Model Provider

Edit `anthropic-config.yaml` to change default model:

```yaml
model:
  default: "claude-opus-4-1"  # Change this
  provider: "anthropic"
```

Or override with **Railway Variables**:
```
ANTHROPIC_API_KEY=sk-...
```

For other providers (OpenAI, Gemini), add their config files to `/opt/hermes/`.

### Agent Personality (SOUL.md)

Customize how Hermes speaks by editing `docker/SOUL.md`:

```markdown
# Hermes Agent Persona

You are a helpful technical expert who:
- Communicates in Russian
- Prefers concise, direct answers
- Uses code examples liberally
- Respects the user's workflow
```

This file is loaded fresh each message — no restart needed.

## 📦 Docker Image Details

**Base:** Debian 13.4
**Python:** 3.x with venv at `/opt/hermes/.venv`
**User:** `hermes` (uid 10000, non-root)
**Data:** `/opt/data` (mounted volume)

**Installed Tools:**
- hermes-agent[all] (PyPI package)
- ripgrep, ffmpeg, git
- nodejs, npm
- openssh-client
- gosu (privilege-drop utility)

## 🌐 Railway Deployment

### Health Check

Railway sends GET requests to `/` every 120s. The container must respond with HTTP 200.

- **Dashboard mode:** Dashboard handles health check at `/`
- **Fallback:** If dashboard crashes, a minimal Python HTTP server returns 200

### Ports

- `8000` — Dashboard (local)
- `8080` — API Server (Railway $PORT)
- `9000` — Gateway
- `9119` — Dashboard (local alt)

### Restart Policy

- **Type:** ALWAYS
- **Max retries:** 10

The `railway-start.sh` script:
1. Starts dashboard in background
2. Runs gateway in a restart loop
3. Restarts gateway on `/restart` command (Telegram)
4. Monitors health; exits if dashboard dies (container restart)

## 🔐 Security

- **Root drop:** Container runs as `hermes` (non-root), not root
- **Volume ownership:** Automatic UID/GID sync with host
- **Config permissions:** config.yaml is mode 640 (readable by hermes only)
- **Token storage:** Tokens in `/opt/data/auth.json` (mode 600, user-only)

## 📝 First Boot

On first container start, the entrypoint:
1. Drops root privileges (gosu)
2. Creates directory structure:
   ```
   /opt/data/
   ├── cron/
   ├── sessions/
   ├── logs/
   ├── hooks/
   ├── memories/
   ├── skills/
   ├── skins/
   ├── plans/
   ├── workspace/
   └── home/
   ```
3. Syncs bundled skills (manifest-based)
4. Bootstraps .env, config.yaml, SOUL.md
5. Optionally starts dashboard
6. Runs your command (chat, gateway, sleep infinity, etc.)

## 🐛 Troubleshooting

### Dashboard won't load

Check if `HERMES_WEB_DIST` is set:
```bash
docker exec <container> env | grep HERMES_WEB_DIST
```

If empty, the activate script didn't find web_dist. The fallback `find` command runs but may be slow.

### Gateway keeps restarting

Check logs:
```bash
docker logs -f <container>
```

Look for:
- Missing API keys (ANTHROPIC_API_KEY, etc.)
- Socket errors on port 9000

### Permission denied on /opt/data

Ensure volume owner matches HERMES_UID:
```bash
ls -la /path/to/hermes-data
# Should be uid 10000 (hermes)
```

If mismatch, set HERMES_UID:
```bash
docker run -e HERMES_UID=$(id -u) ...
```

## 📚 References

- [Hermes Agent Docs](https://hermes-agent.nousresearch.com/docs)
- [Railway.app Docs](https://docs.railway.app)
- [Docker Docs](https://docs.docker.com)

## 📜 License

[Your license here]

## 🤝 Support

For issues, open a GitHub issue or check the Hermes Agent community.

---

**Last updated:** May 2026

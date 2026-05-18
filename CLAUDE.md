# CLAUDE.md

Context primer for AI agents (Claude Code, etc.) opening this repository.
Read this first to skip 20 minutes of re-discovery.

## What this repo is

Production deployment of **Hermes Agent** (Nous Research, PyPI `hermes-agent`)
on **Railway.app** via Docker. The agent runs a Telegram bot + a web dashboard.
End users chat with the bot; admins manage it through the dashboard.

This repo **does not contain Hermes source code** — Hermes is installed from
PyPI inside the Docker image. This repo contains:

- `Dockerfile` — wraps `hermes-agent[all]` in a Debian image with venv, gosu,
  Playwright (no browsers), ripgrep, ffmpeg.
- `railway.toml` — Railway service config (healthcheck `/`, restart ALWAYS,
  `startCommand` runs `docker/railway-start.sh`).
- `gemini-config.yaml` — **current default seed** (Google Gemini 2.5 Flash).
- `anthropic-config.yaml` — alt seed with Anthropic prompt caching (`1h` TTL).
  Kept for users who switch back to Claude.
- `docker/entrypoint.sh` — root → hermes (uid 10000) via gosu, fixes volume
  ownership, seeds `.env`/`config.yaml`/`SOUL.md` if missing.
- `docker/railway-start.sh` — supervisor for dashboard + gateway processes,
  contains seed-config logic and gateway restart loop.
- `docker/SOUL.md` — agent persona (loaded fresh by Hermes on each message).

## Architecture

```
[Telegram user]
     ↓
[Railway public URL :$PORT]
     ↓
[Container: docker/railway-start.sh supervisor]
     ├── hermes dashboard (binds $PORT, serves Railway healthcheck)
     └── hermes gateway run --replace (restart-loop, talks to Telegram + provider APIs)
              ↓
       provider chosen from /opt/data/config.yaml
              ↓
       [Gemini / Anthropic / OpenAI / Z.AI / OpenRouter / etc.]
```

State that survives container restarts lives in the persistent volume mounted
at `/opt/data` (= `HERMES_HOME`): `config.yaml`, sessions, skills, auth tokens.

## Provider switching — three layers, in order of precedence

1. **`/model` command in Telegram** (Hermes-native, primary UX): live-switch
   between OpenRouter / GitHub Copilot / Z.AI / Google / Anthropic / OpenAI.
   Hermes writes the selection to `/opt/data/config.yaml` and it persists
   across container restarts.

2. **`/opt/data/config.yaml`** (volume): the live config. Once written it
   survives restarts. `railway-start.sh` seeds it only when missing OR when
   `HERMES_FORCE_RESEED=1` is set.

3. **Repo `<name>-config.yaml`** (seed source): only consumed on first volume
   boot or forced reseed. Choose via env var `HERMES_PROVIDER_CONFIG=gemini|anthropic|openai`.
   Default fallback: `gemini-config.yaml`.

## Critical env vars (Railway → Variables)

| Var | Purpose |
|---|---|
| `GOOGLE_API_KEY` / `GEMINI_API_KEY` | Gemini API auth (current default provider) |
| `ANTHROPIC_API_KEY` | Claude API auth |
| `OPENAI_API_KEY` | OpenAI API auth |
| `ZAI_API_KEY` | Z.AI / Zhipu GLM API auth |
| `OPENROUTER_API_KEY` | OpenRouter aggregator (200+ models via one key) |
| `TELEGRAM_BOT_TOKEN` | Bot token from @BotFather |
| `TELEGRAM_ALLOWED_USERS` | Whitelist (who can talk to the bot) |
| `HERMES_PROVIDER_CONFIG` | Seed selector. Only matters on fresh volume or forced reseed. |
| `HERMES_FORCE_RESEED` | One-shot: set to `1` → next boot overwrites `config.yaml` (backed up to `.bak`). REMOVE the var after taking effect to restore preserve-mode. |
| `HERMES_RAILWAY_SKIP_GATEWAY` | Dashboard-only mode (skip gateway) |
| `HERMES_AUTH_JSON_BOOTSTRAP` | One-shot seed for Hermes' own OAuth (not provider auth) |
| `PORT` | Auto-set by Railway. Dashboard binds here. |

## Known bugs and gotchas

### i18n key leak (upstream bug in `hermes-agent` — not fixable from this repo)

The Telegram bot sometimes shows raw translation keys instead of localized text:

```
gateway.model.switched
gateway.model.session_only_hint
gateway.reset.tip
```

Hermes v0.14.0 ships an incomplete Russian locale; keys exist for English but
not Russian. **Do not try to fix from this repo** — it lives inside the PyPI
package. Bot is functionally fine; only the labels look broken. Workaround
(if confirmed to work): set `HERMES_LOCALE=en` (verify upstream support
before suggesting).

### Gateway "already running" infinite loop (regression watch)

`hermes gateway run` must be invoked with `--replace` (see
`docker/railway-start.sh:128`). Without it, a stale PID file from a previous
container instance traps the supervisor in an infinite loop:

```
❌ Gateway already running (PID 19725).
[startup] Gateway exited; restarting in 3s...
```

The fix shipped in commit `b8ed12f`. Don't remove the flag.

### Persistent `config.yaml` hides repo seed changes

Editing `gemini-config.yaml` (or any `<name>-config.yaml`) in this repo does
**NOT** automatically propagate to a running deployment, because the seed only
applies when `/opt/data/config.yaml` is missing. Three ways to force a fresh
config:

1. `/model` in Telegram (preferred, no restart needed)
2. Set `HERMES_FORCE_RESEED=1` in Railway → redeploy → REMOVE the var
3. Manually delete `/opt/data/config.yaml` via Railway shell

This is by design — protects user's runtime model selection from being wiped
on every redeploy.

### Anthropic prompt caching applies only when running on Anthropic

`anthropic-config.yaml` has `prompt_caching: { cache_ttl: "1h" }`. Hermes
auto-enables Anthropic's `cache_control` API when this is present. Gemini has
its own context caching (separate API, not controlled by this YAML key) and
Hermes handles it transparently.

## Don't-do list

- **Don't** push to a branch other than `claude/study-research-2Ckv4` (dev) or
  `main` (prod) without explicit user permission. Standard pattern: develop on
  the study-research branch, merge to `main` when user says deploy.
- **Don't** unconditionally `cp` over `${HERMES_HOME}/config.yaml`. This was
  the original bug that wiped user selections on every restart.
- **Don't** add `--no-verify` / `--no-gpg-sign` to commits, or `--force` to
  pushes, unless the user explicitly asks.
- **Don't** try to fix the Hermes i18n key leak from this repo — file an
  upstream issue at https://github.com/NousResearch/hermes-agent/issues.
- **Don't** expose API keys, OAuth tokens, or Telegram tokens in logs, code,
  or commit messages.
- **Don't** use Anthropic Max subscription OAuth tokens with this deployment.
  We considered it and rejected: violates Anthropic Max ToS (Max is for
  first-party clients only), and Max 5× tier gives LESS throughput than a
  Gemini Tier 1 API key. Not worth the ban risk.

## Where to look first when troubleshooting

1. **Bot doesn't reply at all** → Railway logs → search for
   `Gateway already running` (PID-file regression) or provider API 4xx
   errors (auth/billing problem).
2. **Bot replies but on wrong model** → check `/opt/data/config.yaml` via
   Railway shell. Or grep startup logs for `[startup] Preserving existing
   config.yaml` vs `[startup] Seeded config.yaml from …`.
3. **Raw `gateway.model.*` keys in chat** → upstream i18n bug. Not
   actionable here.
4. **Healthcheck 502 / "Application failed to respond"** → dashboard crashed.
   `railway-start.sh` has a Python fallback HTTP server (line ~87) — if even
   that's not responding, check `HERMES_WEB_DIST` is set (`[build] Baked
   HERMES_WEB_DIST=…` should appear in image build logs).

## Quick deploy / rollback cheatsheet

```bash
# Deploy a change to prod (Railway auto-deploys from main)
git push origin main

# Rollback last commit
git revert HEAD && git push origin main

# Sync dev branch to match main after merge
git checkout claude/study-research-2Ckv4
git merge --ff-only main
git push origin claude/study-research-2Ckv4
git checkout main
```

## Recent history (most recent first)

- `b8ed12f` — Gateway `--replace` fix + `HERMES_FORCE_RESEED` escape hatch
- `0b3a8cd` — Switch default seed to Gemini; preserve `/model` selection across restarts
- `7a2fdef` — Enable Anthropic prompt caching with 1h TTL (legacy; relevant only on Anthropic)
- `e0a6ca7` — Add README, .gitignore, CI/CD, expanded SOUL.md (v1.0 release prep)
- `b8a1aa3` — Dashboard startup hardening (web_dist detection, fallback health server)

See `CHANGELOG.md` for granular entries grouped by Added/Changed/Fixed.
See `git log` for full commit history with detailed messages.

## Context that's NOT in the repo (only in this file)

These facts come from prior conversations and won't be obvious from code alone:

- The original deployer's Anthropic billing is currently **disabled** (workspace
  paused, not key revoked). That's why Gemini is the default and why
  `/model` → Anthropic temporarily returns 4xx until billing is re-enabled.
- The deployer hit TPM rate limit (450K) on Anthropic Tier 1 even though
  Anthropic prompt caching was at 98.7% hit rate — caching reduces $$$ but
  cached tokens still count toward TPM. Upgrading to Tier 2 (or staying on
  Gemini) is the structural fix.
- The deployer has API keys for: Gemini, OpenAI, Z.AI/GLM, Anthropic (disabled
  billing), and possibly OpenRouter. Hermes' `/model` picker uses whichever
  keys are available.
- Z.AI / GLM provider in Hermes is `provider: zai` (verified in
  `cli-config.yaml.example` upstream). GLM 4.7 was the user's interest.
- Gemini provider in Hermes is `provider: gemini` (NOT `google`,
  NOT `google/gemini`), model `gemini-2.5-flash` (no version suffix).

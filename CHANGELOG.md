# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- README with deployment instructions
- .gitignore for secrets and build artifacts
- .github/workflows/docker-build.yml for GitHub Actions CI/CD
- .github/workflows/lint.yml for YAML/shell validation
- .env.example with all configurable variables
- CHANGELOG.md (this file)
- Expanded SOUL.md with agent personality definition
- GitHub Container Registry (ghcr.io) auto-publish on tag
- Docker image validation tests in CI

### Added
- gemini-config.yaml: new default seed config using Google Gemini 2.5 Flash (main + vision + compression) and gemini-2.5-flash-lite (title)
- HERMES_PROVIDER_CONFIG env var: selects which `<name>-config.yaml` to use as first-boot seed (default: gemini)
- HERMES_FORCE_RESEED env var: one-shot override to overwrite an existing /opt/data/config.yaml (backs up to config.yaml.bak) — useful for recovering from a stuck dead-provider config

### Fixed
- Gateway restart loop: pass --replace to `hermes gateway run` so a stale PID file from a previous container instance doesn't block every subsequent boot with "Gateway already running" errors

### Changed
- SOUL.md now fully defined (was placeholder)
- Improved documentation structure
- Enable Anthropic prompt caching with 1h TTL in anthropic-config.yaml (was disabled by default) — reduces input token cost ~5-10x on typical Hermes workloads with heavy tool-use roundtrips
- Default seed provider switched from Anthropic Claude Haiku to Google Gemini 2.5 Flash (cheaper, multimodal, 1M context). Anthropic config preserved for users who switch back via /model
- railway-start.sh now seeds /opt/data/config.yaml only on first boot; subsequent restarts preserve user's /model selection from Telegram

## [1.0.0] - 2026-05-18

### Added
- Initial release
- Docker multi-stage Dockerfile optimized for Railway
- Railway.toml deployment configuration
- anthropic-config.yaml with Claude Haiku default
- entrypoint.sh with privilege dropping (gosu)
- railway-start.sh with dashboard + gateway restart loop
- Fallback HTTP health server when dashboard crashes
- Support for HERMES_UID/GID mapping for host ownership sync
- SOUL.md placeholder for agent personality customization

### Fixed
- Dashboard startup reliability via find fallback for web_dist
- Health check path consistency
- Privilege escalation handling in containers
- Config.yaml ownership and permissions (mode 640)

---

## Version History

### v1.0.0
- Production-ready Hermes Agent Docker image
- Full Railway.app integration
- Anthropic Claude Haiku as default model
- Dashboard + gateway on Railway
- Proper signal handling and restart loops

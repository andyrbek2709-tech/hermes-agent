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

### Changed
- SOUL.md now fully defined (was placeholder)
- Improved documentation structure

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

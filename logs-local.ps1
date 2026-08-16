$ErrorActionPreference = 'Stop'
$ComposeFile = Join-Path $PSScriptRoot 'docker-compose.local.yml'
docker compose -f $ComposeFile logs -f --tail=120 hermes

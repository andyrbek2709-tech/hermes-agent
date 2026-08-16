$ErrorActionPreference = 'Stop'
$ComposeFile = Join-Path $PSScriptRoot 'docker-compose.local.yml'
docker compose -f $ComposeFile run --rm hermes model

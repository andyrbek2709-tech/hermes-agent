$ErrorActionPreference = 'Stop'
$ComposeFile = Join-Path $PSScriptRoot 'docker-compose.local.yml'
docker compose -f $ComposeFile up -d
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
docker compose -f $ComposeFile ps

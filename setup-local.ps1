Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$AppDir = $PSScriptRoot
$RootDir = Split-Path -Parent $AppDir
$DataDir = Join-Path $RootDir 'data'
$EnvPath = Join-Path $DataDir '.env'
$ComposeFile = Join-Path $AppDir 'docker-compose.local.yml'

function Write-Utf8NoBom([string]$Path, [string[]]$Lines) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Path, $Lines, $enc)
}

function Get-EnvValue([string]$Name) {
    if (-not (Test-Path $EnvPath)) { return $null }
    $prefix = "$Name="
    foreach ($line in [System.IO.File]::ReadAllLines($EnvPath)) {
        if ($line.StartsWith($prefix)) {
            return $line.Substring($prefix.Length)
        }
    }
    return $null
}

function Set-EnvValue([string]$Name, [string]$Value) {
    $lines = @()
    if (Test-Path $EnvPath) {
        $lines = @([System.IO.File]::ReadAllLines($EnvPath))
    }
    $prefix = "$Name="
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].StartsWith($prefix)) {
            $lines[$i] = "$Name=$Value"
            $found = $true
            break
        }
    }
    if (-not $found) { $lines += "$Name=$Value" }
    Write-Utf8NoBom $EnvPath $lines
}

function Secure-ToPlain([System.Security.SecureString]$Secure) {
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

Write-Host ''
Write-Host '=== Hermes Local Windows ==='
Write-Host "APP : $AppDir"
Write-Host "DATA: $DataDir"
Write-Host ''

# Docker must already be running.
docker info *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'Docker Desktop не запущен. Запустите Docker Desktop и повторите setup-local.ps1.'
}

New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
foreach ($name in @('cron','sessions','logs','hooks','memories','skills','skins','plans','workspace','home')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $DataDir $name) | Out-Null
}

if (-not (Test-Path $EnvPath)) {
    Write-Utf8NoBom $EnvPath @(
        '# Hermes local secrets. This file lives outside the Git repository.',
        '# ChatGPT/OpenAI Codex OAuth is NOT stored here; it is stored in auth.json.',
        '# Optional later: GOOGLE_API_KEY=..., ANTHROPIC_API_KEY=..., ZAI_API_KEY=...',
        'HERMES_HOME=/opt/data'
    )
}

$telegramToken = Get-EnvValue 'TELEGRAM_BOT_TOKEN'
if ([string]::IsNullOrWhiteSpace($telegramToken)) {
    Write-Host 'Введите Telegram Bot Token. Он будет сохранён только в D:\Hermes\data\.env.'
    $secure = Read-Host 'TELEGRAM_BOT_TOKEN' -AsSecureString
    $telegramToken = Secure-ToPlain $secure
    if ([string]::IsNullOrWhiteSpace($telegramToken)) {
        throw 'Telegram token не введён.'
    }
    Set-EnvValue 'TELEGRAM_BOT_TOKEN' $telegramToken
}
else {
    Write-Host 'Telegram token уже есть в локальном data\.env — сохраняю без изменений.'
}

Write-Host ''
Write-Host '[1/4] Сборка локального Hermes 0.15.2...'
docker compose -f $ComposeFile build
if ($LASTEXITCODE -ne 0) { throw 'Docker build завершился ошибкой.' }

Write-Host ''
Write-Host '[2/4] Проверка версии и инициализация постоянного хранилища...'
docker compose -f $ComposeFile run --rm hermes --version
if ($LASTEXITCODE -ne 0) { throw 'Hermes не запускается после сборки.' }

Write-Host ''
Write-Host '[3/4] Выбор модели и авторизация.'
Write-Host 'Выберите в меню: OpenAI Codex.'
Write-Host 'Это ChatGPT OAuth, НЕ OPENAI_API_KEY и НЕ OpenRouter.'
Write-Host 'Если браузер сам не откроется, Hermes покажет адрес и код — откройте адрес в обычном браузере Windows и введите код.'
Write-Host ''
docker compose -f $ComposeFile run --rm hermes model
if ($LASTEXITCODE -ne 0) { throw 'Настройка модели завершилась ошибкой.' }

$AuthPath = Join-Path $DataDir 'auth.json'
$ConfigPath = Join-Path $DataDir 'config.yaml'
if (Test-Path $AuthPath) {
    $authText = [System.IO.File]::ReadAllText($AuthPath)
    if ($authText -match 'openai-codex') {
        Write-Host 'ChatGPT/OpenAI Codex OAuth сохранён в локальном auth.json.'
    }
}
if (Test-Path $ConfigPath) {
    $cfgText = [System.IO.File]::ReadAllText($ConfigPath)
    if ($cfgText -notmatch 'provider:\s*["'']?openai-codex') {
        Write-Warning 'OpenAI Codex не найден как активный provider в config.yaml. Hermes запустится с выбранным вами провайдером.'
    }
}

Write-Host ''
Write-Host '[4/4] Запуск Telegram gateway...'
docker compose -f $ComposeFile up -d
if ($LASTEXITCODE -ne 0) { throw 'Gateway не удалось запустить.' }

Start-Sleep -Seconds 4
docker compose -f $ComposeFile ps
Write-Host ''
Write-Host 'Последние строки лога:'
docker compose -f $ComposeFile logs --tail=35 hermes

Write-Host ''
Write-Host 'Готово. Постоянная память и рабочее пространство находятся в D:\Hermes\data.'
Write-Host 'Остановить: .\stop-local.ps1'
Write-Host 'Запустить: .\start-local.ps1'
Write-Host 'Логи:      .\logs-local.ps1'
Write-Host 'Модель:    .\model-local.ps1'

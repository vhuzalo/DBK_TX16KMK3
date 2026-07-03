[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [string]$RadioRoot
)

$ErrorActionPreference = "Stop"

$resolvedRadioRoot = $RadioRoot.Trim('"')
if (-not (Test-Path -LiteralPath $resolvedRadioRoot)) {
    throw "Pasta do radio nao encontrada: $resolvedRadioRoot"
}

$destination = Join-Path $resolvedRadioRoot "WIDGETS\DBK_TX16KMK3"
New-Item -ItemType Directory -Force -Path $destination | Out-Null

Write-Host "Deploy de $Source para $destination"

robocopy $Source $destination /MIR /XD .git .github .agents .vscode /XF *.code-workspace
$exitCode = $LASTEXITCODE

if ($exitCode -gt 7) {
    throw "Falha no deploy via robocopy. Codigo: $exitCode"
}

Write-Host "Deploy concluido com sucesso."

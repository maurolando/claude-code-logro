# Instala los avisos tipo "logro" de Claude Code para el usuario actual (Windows).
#
#   powershell -ExecutionPolicy Bypass -File .\windows\instalar.ps1
#
# Archivo en ASCII puro a proposito: Windows PowerShell 5.1 lee mal los acentos
# de un .ps1 sin BOM.
$ErrorActionPreference = 'Stop'

$aqui = $PSScriptRoot
$destino = Join-Path (Join-Path $HOME '.claude') 'hooks'
$ajustes = Join-Path (Join-Path $HOME '.claude') 'settings.json'
$utf8 = New-Object System.Text.UTF8Encoding($false)

New-Item -ItemType Directory -Force -Path $destino | Out-Null
Copy-Item -Force (Join-Path $aqui 'logro-claude.ps1') $destino
# la fuente va junto al script: asi no hace falta instalarla en el sistema
Copy-Item -Force (Join-Path (Join-Path (Join-Path $aqui '..') 'fuente') 'PressStart2P-Regular.ttf') $destino

$config = $null
if (Test-Path $ajustes) {
    Copy-Item -Force $ajustes "$ajustes.antes-de-logro"
    $texto = [System.IO.File]::ReadAllText($ajustes, $utf8)
    if ($texto.Trim()) { $config = $texto | ConvertFrom-Json }
}
if (-not $config) { $config = New-Object PSObject }

# "$HOME" queda literal en settings.json: lo resuelve la shell que corre el
# hook, sea Git Bash o PowerShell.
function EntradaHook([string]$modo, [string]$filtro) {
    $comando = ('powershell -NoProfile -STA -ExecutionPolicy Bypass -File "$HOME/.claude/hooks/logro-claude.ps1" ' + $modo).Trim()
    $entrada = [ordered]@{}
    if ($filtro) { $entrada['matcher'] = $filtro }
    $entrada['hooks'] = @([ordered]@{ type = 'command'; command = $comando; async = $true; timeout = 20 })
    return $entrada
}

$nuevos = [ordered]@{
    Notification = EntradaHook 'permiso' 'permission_prompt'
    PreToolUse   = EntradaHook 'pregunta' 'AskUserQuestion'
    PostToolUse  = EntradaHook 'respondida' 'AskUserQuestion'
    Stop         = EntradaHook '' ''
}

if (-not ($config.PSObject.Properties.Name -contains 'hooks') -or -not $config.hooks) {
    $config | Add-Member -Force -NotePropertyName 'hooks' -NotePropertyValue (New-Object PSObject)
}
# agrega los hooks sin tocar los que ya haya; si ya estaban instalados no los duplica
foreach ($evento in $nuevos.Keys) {
    $lista = New-Object System.Collections.ArrayList
    if ($config.hooks.PSObject.Properties.Name -contains $evento) {
        foreach ($previo in @($config.hooks.$evento)) {
            $comandos = @($previo.hooks | ForEach-Object { [string]$_.command })
            if (-not ($comandos -match 'logro-claude')) { [void]$lista.Add($previo) }
        }
    }
    [void]$lista.Add($nuevos[$evento])
    $config.hooks | Add-Member -Force -NotePropertyName $evento -NotePropertyValue $lista.ToArray()
}

[System.IO.File]::WriteAllText($ajustes, ($config | ConvertTo-Json -Depth 50), $utf8)

Write-Host "Instalado. Copia de la configuracion anterior: $ajustes.antes-de-logro"
Write-Host 'Reinicia Claude Code (o abri /hooks una vez) para que tome los hooks.'
try {
    $prueba = '{"cwd":"' + ($PWD.Path -replace '\\', '/') + '"}'
    $prueba | powershell -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $destino 'logro-claude.ps1')
} catch {
    Write-Host "No se pudo mostrar el aviso de prueba: $_"
}

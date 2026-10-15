# Aviso tipo "logro" en pixel art, arriba al centro de la pantalla (Windows).
#
# Lo disparan los hooks de Claude Code (settings.json), que le pasan por stdin
# un JSON con el cwd de la sesion. El argumento dice que paso:
#
#   (ninguno)   Stop: termino. Solo avisa si la tarea llevo al menos $MinimoS.
#   error       StopFailure: se corto por un error de la API.
#   permiso     Notification permission_prompt: espera un permiso.
#   pregunta    PreToolUse de AskUserQuestion: muestra un cuadro de opciones.
#   respondida  PostToolUse de AskUserQuestion: no muestra nada.
#   inicio      UserPromptSubmit: no muestra nada, anota la hora para medir.
#   probar      a mano: muestra los cuatro avisos con la configuracion actual.
#
# Los valores de abajo son los de fabrica: cada uno los cambia en
# ~/.claude/logro.json (ver ejemplo-logro.json en el repo), que no se pisa al
# actualizar.
#
# Archivo en ASCII puro a proposito: Windows PowerShell 5.1 lee mal los acentos
# de un .ps1 sin BOM. Los textos que llevan acento se arman con [char].
param([string]$Modo = 'terminado')

$MargenSuperior = 40
$AnimacionMs = 300
$PreguntaAbiertaMaxS = 600  # por si la pregunta se cancela y nadie borra la marca
$MinimoS = 30  # el trofeo solo sale si la tarea llevo al menos esto; 0 para avisar siempre
$Sonidos = Join-Path $env:WINDIR 'Media'

# Press Start 2P (junto a este script) se ve nitida solo en multiplos de 8 px
$ArchivoFuente = Join-Path $PSScriptRoot 'PressStart2P-Regular.ttf'
$FuentePx = 16
$Pixel = 4  # tamano de cada "pixel" del dibujo

# fondo, canto claro, canto oscuro y borde
$Verde = @('#17602c', '#35904a', '#0d401c', '#04140a')
$Rojo = @('#7a1616', '#b33a3a', '#4f0c0c', '#170404')
$ColorTitulo = '#ffe45c'
$ColorDetalle = '#ffffff'

$PaletaIcono = @{
    'o' = '#3b2a00'; 'y' = '#ffd23f'; 'l' = '#fff3a0'; 'd' = '#c98a00'
    'w' = '#ffffff'; 'g' = '#c8ccd4'; 's' = '#7b8190'
}
$Trofeo = @(
    '..oooooooooooo..',
    '.oolyyyyyyyydoo.',
    'o.olyyyyyyyydo.o',
    'o.olyyyyyyyydo.o',
    'o.olyyyyyyyydo.o',
    '.oolyyyyyyyydoo.',
    '...olyyyyyydo...',
    '....olyyyydo....',
    '.....oyyddo.....',
    '......oydo......',
    '......oydo......',
    '.....ooydoo.....',
    '....olyyyydo....',
    '...olyyyyyydo...',
    '...oooooooooo...',
    '................'
)
$Candado = @(
    '................',
    '.....oooooo.....',
    '....owggggso....',
    '...owgoooogso...',
    '...owgo..ogso...',
    '...owgo..ogso...',
    '.oooooooooooooo.',
    '.olyyyyyyyyyydo.',
    '.olyyyyooyyyydo.',
    '.olyyyyooyyyydo.',
    '.olyyyyooyyyydo.',
    '.olyyyyyyyyyydo.',
    '.olyyyyyyyyyydo.',
    '.oddddddddddddo.',
    '.oooooooooooooo.',
    '................'
)
$Pregunta = @(
    '................',
    '....oooooooo....',
    '...olyyyyyydo...',
    '..olyyyyyyyydo..',
    '..olydoooolydo..',
    '..oooo...olydo..',
    '........olydo...',
    '.......olydo....',
    '......olydo.....',
    '......ooooo.....',
    '................',
    '......ooooo.....',
    '......olydo.....',
    '......olydo.....',
    '......ooooo.....',
    '................'
)
$Calavera = @(
    '................',
    '................',
    '................',
    '....oooooooo....',
    '...owwwwwwwwo...',
    '..owwwwwwwwwwo..',
    '..owooowwooogo..',
    '..owooowwooogo..',
    '..owwwwoowwwgo..',
    '...owwwwwwwgo...',
    '...owowowowgo...',
    '....owwwwwgo....',
    '....oooooooo....',
    '................',
    '................',
    '................'
)

# Sonido: '' para silenciarlo
$Avisos = @{
    'terminado' = @{
        Titulo = 'TAREA COMPLETADA'; Detalle = "Claude termin$([char]0xF3)"
        Icono = $Trofeo; VisibleMs = 4500; Sonido = 'chimes.wav'
    }
    'permiso'   = @{
        Titulo = 'PERMISO REQUERIDO'; Detalle = 'Claude espera'
        Icono = $Candado; VisibleMs = 8000; Sonido = 'notify.wav'
    }
    'pregunta'  = @{
        Titulo = 'PREGUNTA PENDIENTE'; Detalle = 'Claude pregunta'
        Icono = $Pregunta; VisibleMs = 8000; Sonido = 'ding.wav'
    }
    'error'     = @{
        Titulo = 'CLAUDE SE DETUVO'; Detalle = 'Error de la API'
        Icono = $Calavera; VisibleMs = 10000; Sonido = 'Windows Critical Stop.wav'; Colores = $Rojo
    }
}

$Errores = @{
    'rate_limit'            = "L$([char]0xED)mite de uso"
    'overloaded'            = 'API saturada'
    'authentication_failed' = "Fall$([char]0xF3) el login"
    'billing_error'         = "Facturaci$([char]0xF3)n"
    'server_error'          = 'Error del servidor'
    'max_output_tokens'     = 'Respuesta muy larga'
}

$Relleno = 5 * $Pixel
$RellenoLateral = 10 * $Pixel  # los extremos son redondos: el contenido va mas adentro
$Separacion = 5 * $Pixel
$Interlineado = 3 * $Pixel
$Sombra = 2 * $Pixel

# --- configuracion propia: ~/.claude/logro.json pisa los valores de fabrica ---

$Config = Join-Path (Join-Path $HOME '.claude') 'logro.json'
$Sonido = $true  # $false silencia todos los avisos
$NoMolestar = $null  # {"desde": "22:00", "hasta": "08:00"}: en ese horario no sale ningun aviso
$Problemas = New-Object System.Collections.ArrayList

$a_ = [char]0xE1  # a con tilde
$i_ = [char]0xED  # i con tilde
$u_ = [char]0xFA  # u con tilde
$NombresColor = @{
    'rojo' = '#c62828'; 'verde' = '#2e7d32'; 'azul' = '#1565c0'; 'celeste' = '#4fc3f7'
    'turquesa' = '#00897b'; 'amarillo' = '#fdd835'; 'dorado' = '#ffc107'; 'naranja' = '#ef6c00'
    'rosa' = '#ec407a'; 'violeta' = '#7b1fa2'; 'morado' = '#7b1fa2'; 'purpura' = '#7b1fa2'
    'lila' = '#ce93d8'; 'marron' = '#6d4c41'; 'gris' = '#757575'; 'negro' = '#000000'
    'blanco' = '#ffffff'
}
$Claves = @('minimo_s', 'sonido', 'no_molestar', 'fondo', 'color_titulo', 'color_detalle', 'avisos')
$ClavesAviso = @('activo', 'titulo', 'detalle', 'visible_ms', 'sonido', 'fondo', 'colores')

# Acepta lo que la gente escribe a mano: comentarios // y /* */, comas de mas
# antes de } o ], y valores sin comillas como #7303fc o azul. Conserva los
# saltos de linea para que un error siga marcando la linea del archivo.
$RePalabra = [regex]'\G(?:#?[^\W\d][\w#-]*|#[0-9a-fA-F]+)'
$ReComaDeMas = [regex]'\G,(?=\s*[}\]])'
function Recorrer([string]$texto, [scriptblock]$fueraDeTexto) {
    $salida = New-Object System.Text.StringBuilder
    $i = 0
    while ($i -lt $texto.Length) {
        if ($texto[$i] -eq '"') {
            $j = $i + 1
            while (($j -lt $texto.Length) -and ($texto[$j] -ne '"')) {
                if ($texto[$j] -eq '\') { $j += 2 } else { $j++ }
            }
            $fin = [math]::Min($j + 1, $texto.Length)
            [void]$salida.Append($texto.Substring($i, $fin - $i))
            $i = $fin
        } else {
            $trozo, $i = & $fueraDeTexto $texto $i
            [void]$salida.Append($trozo)
        }
    }
    return $salida.ToString()
}
$ComentariosYPalabras = {
    param($t, $i)
    $dos = ''
    if ($i + 1 -lt $t.Length) { $dos = $t.Substring($i, 2) }
    if ($dos -eq '//') {
        $fin = $t.IndexOf("`n", $i)
        if ($fin -lt 0) { $fin = $t.Length }
        return '', $fin
    }
    if ($dos -eq '/*') {
        $fin = $t.IndexOf('*/', $i + 2)
        if ($fin -lt 0) { $fin = $t.Length } else { $fin += 2 }
        $saltos = ($t.Substring($i, $fin - $i).Split("`n")).Count - 1
        return ("`n" * $saltos), $fin
    }
    $m = $RePalabra.Match($t, $i)
    if ($m.Success) {
        if (@('true', 'false', 'null') -ccontains $m.Value) { return $m.Value, ($i + $m.Length) }
        return ('"' + $m.Value + '"'), ($i + $m.Length)
    }
    return [string]$t[$i], ($i + 1)
}
$ComasDeMas = {
    param($t, $i)
    if ($ReComaDeMas.Match($t, $i).Success) { return '', ($i + 1) }
    return [string]$t[$i], ($i + 1)
}
function RelajarJson([string]$texto) {
    return Recorrer (Recorrer $texto $ComentariosYPalabras) $ComasDeMas
}

function Tiene($objeto, [string]$clave) {
    return ($null -ne $objeto) -and ($objeto -is [System.Management.Automation.PSCustomObject]) -and
        ($objeto.PSObject.Properties.Name -contains $clave)
}
function EsNumero($x) { return ($x -is [int]) -or ($x -is [long]) -or ($x -is [double]) -or ($x -is [decimal]) }

# '#7303fc', '7303fc', '#73f' o un nombre ('azul', 'violeta') -> '#rrggbb'
function NormalizarColor($valor) {
    if (-not ($valor -is [string])) { return $null }
    $v = $valor.Trim().ToLowerInvariant().Normalize([System.Text.NormalizationForm]::FormD)
    $v = -join ($v.ToCharArray() | Where-Object {
        [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })
    if ($NombresColor.ContainsKey($v)) { $v = $NombresColor[$v] }
    $v = $v.TrimStart('#')
    if ($v -match '^[0-9a-f]{3}$') { $v = -join ($v.ToCharArray() | ForEach-Object { "$_$_" }) }
    if ($v -match '^[0-9a-f]{6}$') { return "#$v" }
    return $null
}
function Color([string]$clave, $valor) {
    $normal = NormalizarColor $valor
    if (-not $normal) { [void]$Problemas.Add("${clave}: color inv${a_}lido") }
    return $normal
}

# del color de fondo saca el canto claro, el canto oscuro y el borde
function Bisel([string]$fondo) {
    $canales = @(1, 3, 5 | ForEach-Object { [Convert]::ToInt32($fondo.Substring($_, 2), 16) })
    $tono = {
        param($factor, $suma)
        '#' + (-join ($canales | ForEach-Object {
            '{0:x2}' -f [int][math]::Max(0, [math]::Min(255, [math]::Round($_ * $factor + $suma))) }))
    }
    return @($fondo, (& $tono 1.35 22), (& $tono 0.65 0), (& $tono 0.18 0))
}

function Hora($texto) {
    if (([string]$texto -match '^(\d{1,2}):(\d{2})$') -and ([int]$matches[1] -lt 24) -and ([int]$matches[2] -lt 60)) {
        return New-TimeSpan -Hours ([int]$matches[1]) -Minutes ([int]$matches[2])
    }
    return $null
}
function HorarioValido($horario) {
    return ($null -ne (Hora $horario.desde)) -and ($null -ne (Hora $horario.hasta))
}
function EnNoMolestar {
    if (-not $NoMolestar) { return $false }
    $desde = Hora $NoMolestar.desde
    $hasta = Hora $NoMolestar.hasta
    $ahora = (Get-Date).TimeOfDay
    if ($desde -le $hasta) { return ($ahora -ge $desde) -and ($ahora -lt $hasta) }
    return ($ahora -ge $desde) -or ($ahora -lt $hasta)  # cruza la medianoche
}

# Pisa los valores de fabrica. Lo que no sirva se ignora y queda anotado en
# $Problemas, para mostrarlo.
$cfg = $null
if (Test-Path $Config) {
    $crudo = [System.IO.File]::ReadAllText($Config, (New-Object System.Text.UTF8Encoding($false)))
    try {
        $cfg = (RelajarJson $crudo) | ConvertFrom-Json -ErrorAction Stop
        if (-not ($cfg -is [System.Management.Automation.PSCustomObject])) {
            [void]$Problemas.Add('tiene que empezar con {')
            $cfg = $null
        }
    } catch {
        # PowerShell 7 dice la linea; Windows PowerShell 5.1 no
        if ("$_" -match '[Ll]ine (\d+)') { [void]$Problemas.Add("error en la l${i_}nea $($matches[1])") }
        else { [void]$Problemas.Add('error de sintaxis') }
    }
}
if ($cfg) {
    foreach ($clave in $cfg.PSObject.Properties.Name) {
        if ($Claves -notcontains $clave) { [void]$Problemas.Add("no existe $clave") }
    }
    if (Tiene $cfg 'minimo_s') {
        if (EsNumero $cfg.minimo_s) { $MinimoS = [double]$cfg.minimo_s }
        else { [void]$Problemas.Add("minimo_s: tiene que ser un n${u_}mero") }
    }
    if (Tiene $cfg 'sonido') {
        if ($cfg.sonido -is [bool]) { $Sonido = $cfg.sonido } else { [void]$Problemas.Add('sonido: true o false') }
    }
    if (Tiene $cfg 'no_molestar') {
        if (($null -eq $cfg.no_molestar) -or (HorarioValido $cfg.no_molestar)) { $NoMolestar = $cfg.no_molestar }
        else { [void]$Problemas.Add('no_molestar: {"desde": "22:00", "hasta": "08:00"}') }
    }
    if (Tiene $cfg 'color_titulo') { $normal = Color 'color_titulo' $cfg.color_titulo; if ($normal) { $ColorTitulo = $normal } }
    if (Tiene $cfg 'color_detalle') { $normal = Color 'color_detalle' $cfg.color_detalle; if ($normal) { $ColorDetalle = $normal } }
    if (Tiene $cfg 'fondo') {
        $normal = Color 'fondo' $cfg.fondo
        if ($normal) {
            # el error queda rojo para que se distinga
            foreach ($nombreAviso in @('terminado', 'permiso', 'pregunta')) { $Avisos[$nombreAviso].Colores = Bisel $normal }
        }
    }
    if (Tiene $cfg 'avisos') {
        if (-not ($cfg.avisos -is [System.Management.Automation.PSCustomObject])) {
            [void]$Problemas.Add('avisos: tiene que ir entre { }')
        } else {
            foreach ($propiedad in $cfg.avisos.PSObject.Properties) {
                $nombreAviso = $propiedad.Name
                $cambios = $propiedad.Value
                if (-not $Avisos.ContainsKey($nombreAviso)) { [void]$Problemas.Add("no existe el aviso $nombreAviso"); continue }
                if (-not ($cambios -is [System.Management.Automation.PSCustomObject])) {
                    [void]$Problemas.Add("${nombreAviso}: tiene que ir entre { }"); continue
                }
                $destino = $Avisos[$nombreAviso]
                foreach ($clave in $cambios.PSObject.Properties.Name) {
                    if ($ClavesAviso -notcontains $clave) { [void]$Problemas.Add("no existe $nombreAviso.$clave") }
                }
                if (Tiene $cambios 'activo') {
                    if ($cambios.activo -is [bool]) { $destino.Activo = $cambios.activo }
                    else { [void]$Problemas.Add("$nombreAviso.activo: true o false") }
                }
                foreach ($par in @(@('titulo', 'Titulo'), @('detalle', 'Detalle'), @('sonido', 'Sonido'))) {
                    if (Tiene $cambios $par[0]) {
                        if ($cambios.($par[0]) -is [string]) { $destino[$par[1]] = $cambios.($par[0]) }
                        else { [void]$Problemas.Add("$nombreAviso.$($par[0]): va entre comillas") }
                    }
                }
                if (Tiene $cambios 'visible_ms') {
                    if (($cambios.visible_ms -is [int]) -or ($cambios.visible_ms -is [long])) { $destino.VisibleMs = [int]$cambios.visible_ms }
                    else { [void]$Problemas.Add("$nombreAviso.visible_ms: milisegundos, sin comillas") }
                }
                if (Tiene $cambios 'fondo') {
                    $normal = Color "$nombreAviso.fondo" $cambios.fondo
                    if ($normal) { $destino.Colores = Bisel $normal }
                }
                if (Tiene $cambios 'colores') {
                    $normales = @(@($cambios.colores) | ForEach-Object { NormalizarColor $_ })
                    if (($normales.Count -eq 4) -and -not ($normales | Where-Object { -not $_ })) { $destino.Colores = $normales }
                    else { [void]$Problemas.Add("$nombreAviso.colores: van 4 colores") }
                }
            }
        }
    }
}
foreach ($problema in $Problemas) { [Console]::Error.WriteLine("${Config}: $problema") }

# --- vista previa: logro-claude.ps1 probar -------------------------------------

if ($Modo -eq 'probar') {
    $existe = ''
    if (-not (Test-Path $Config)) { $existe = ' (no existe: valores de fabrica)' }
    Write-Host "Configuracion: $Config$existe"
    foreach ($problema in $Problemas) { Write-Host "  problema: $problema" }
    if ($Problemas.Count -eq 0) { Write-Host '  sin problemas' }
    if (EnNoMolestar) { Write-Host '  ahora es horario de no molestar: fuera de esta prueba no saldria ningun aviso' }
    $ejecutable = (Get-Process -Id $PID).Path
    $datos = @{ cwd = (Get-Location).Path } | ConvertTo-Json -Compress
    $env:LOGRO_PRUEBA = '1'
    foreach ($nombreAviso in @('terminado', 'permiso', 'pregunta', 'error')) {
        $cada = $Avisos[$nombreAviso]
        if ($cada.Activo -eq $false) { Write-Host "${nombreAviso}: apagado"; continue }
        Write-Host "${nombreAviso}: $($cada.Titulo)"
        $datos | & $ejecutable -NoProfile -STA -ExecutionPolicy Bypass -File $PSCommandPath $nombreAviso
    }
    Remove-Item Env:LOGRO_PRUEBA
    exit 0
}

# --- entrada del hook ---------------------------------------------------------

$sesion = ''
$cwd = ''
$mensaje = ''
$tipoError = ''
try {
    if ([Console]::IsInputRedirected) {
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $lector = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), $utf8)
        $texto = $lector.ReadToEnd()
        if ($texto.Trim()) {
            $datos = $texto | ConvertFrom-Json
            if ($datos.session_id) { $sesion = [string]$datos.session_id }
            if ($datos.cwd) { $cwd = [string]$datos.cwd }
            if ($datos.message) { $mensaje = [string]$datos.message }
            if ($datos.error) { $tipoError = [string]$datos.error }
        }
    }
} catch { }

function Marca([string]$cual) { Join-Path $env:TEMP "claude-logro-$cual-$sesion" }
function Tocar([string]$ruta) { Set-Content -Path $ruta -Value '' }
function Antiguedad([string]$ruta) {
    $archivo = Get-Item -Path $ruta -ErrorAction SilentlyContinue
    if (-not $archivo) { return $null }
    return ((Get-Date) - $archivo.LastWriteTime).TotalSeconds
}
function Duracion([double]$segundos) {
    $s = [int][math]::Floor($segundos)
    if ($s -lt 60) { return "${s}s" }
    if ($s -lt 3600) { return '{0}m {1:00}s' -f [math]::Floor($s / 60), ($s % 60) }
    return '{0}h {1:00}m' -f [math]::Floor($s / 3600), [math]::Floor(($s % 3600) / 60)
}

# Una pregunta dispara tambien el aviso de permiso (unos segundos despues):
# mientras este abierta se deja solo el de pregunta. Esa marca la pone el
# PreToolUse de AskUserQuestion y la borra su PostToolUse. La espera de la
# respuesta no cuenta como tiempo de la tarea: al responder se vuelve a anotar
# la hora de inicio.
if ($Modo -eq 'inicio') {
    Tocar (Marca 'inicio')
    exit 0
}
if ($Modo -eq 'respondida') {
    Remove-Item -Path (Marca 'pregunta') -ErrorAction SilentlyContinue
    Tocar (Marca 'inicio')
    exit 0
}
if (-not $Avisos.ContainsKey($Modo)) { $Modo = 'terminado' }
$aviso = $Avisos[$Modo]
$texto = $aviso.Detalle
if ($env:LOGRO_PRUEBA) {
    # vista previa: sin marcas ni umbral ni horario, y mas corta
    if ($Modo -eq 'terminado') { $texto = "$($aviso.Detalle) en 4m 12s" }
    if ($Modo -eq 'error') { $texto = $Errores['rate_limit'] }
    $aviso.VisibleMs = [math]::Min($aviso.VisibleMs, 2500)
} else {
    if ($Modo -eq 'pregunta') {
        Tocar (Marca 'pregunta')
    } elseif ($Modo -eq 'permiso') {
        if ($mensaje -like '*AskUserQuestion*') { exit 0 }
        $edad = Antiguedad (Marca 'pregunta')
        if ($null -ne $edad -and $edad -lt $PreguntaAbiertaMaxS) { exit 0 }
    } elseif ($Modo -eq 'error') {
        if ($Errores.ContainsKey($tipoError)) { $texto = $Errores[$tipoError] }
    } elseif ($Modo -eq 'terminado') {
        # sin marca (hooks recien instalados) se avisa igual, sin la duracion
        $edad = Antiguedad (Marca 'inicio')
        if ($null -ne $edad) {
            if ($edad -lt $MinimoS) { exit 0 }
            $texto = "$($aviso.Detalle) en $(Duracion $edad)"
        }
    }
    # las marcas ya se actualizaron aunque el aviso este apagado o en horario de no molestar
    if (($aviso.Activo -eq $false) -or (EnNoMolestar)) { exit 0 }
}
$icono = $aviso.Icono
$colores = $Verde
if ($aviso.Colores) { $colores = $aviso.Colores }

$nombre = 'Claude Code'
$cwd = $cwd.TrimEnd('\', '/')
if ($cwd) { $nombre = ($cwd -split '[\\/]')[-1] }
$detalle = "$texto $([char]0xB7) $nombre"
# mientras logro.json tenga algo mal, se avisa ahi en vez del detalle
if ($Problemas.Count -gt 0) { $detalle = "logro.json: $($Problemas[0])" }
if ($detalle.Length -gt 40) { $detalle = $detalle.Substring(0, 39) + [char]0x2026 }

# --- dibujo -------------------------------------------------------------------

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

function Pincel([string]$color) {
    $p = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($color))
    $p.Freeze()
    return $p
}

if (Test-Path $ArchivoFuente) {
    $carpeta = New-Object System.Uri ((Split-Path $ArchivoFuente) + '\')
    $fuente = New-Object System.Windows.Media.FontFamily ($carpeta, './#Press Start 2P')
} else {
    $fuente = New-Object System.Windows.Media.FontFamily 'Consolas'
}

function Texto([string]$contenido, [string]$color) {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $contenido
    $t.FontFamily = $fuente
    $t.FontSize = $FuentePx
    $t.Foreground = Pincel $color
    [System.Windows.Media.TextOptions]::SetTextRenderingMode($t, 'Aliased')
    [System.Windows.Media.TextOptions]::SetTextFormattingMode($t, 'Display')
    return $t
}

$infinito = New-Object System.Windows.Size ([double]::PositiveInfinity, [double]::PositiveInfinity)
$anchoTexto = 0
foreach ($linea in @($aviso.Titulo, $detalle)) {
    $medida = Texto $linea $ColorDetalle
    $medida.Measure($infinito)
    $anchoTexto = [math]::Max($anchoTexto, [math]::Ceiling($medida.DesiredSize.Width))
}

$ladoIcono = $icono.Count * $Pixel
$ancho = $Pixel + $RellenoLateral + $ladoIcono + $Separacion + $anchoTexto + $RellenoLateral + $Pixel
$ancho = [math]::Ceiling($ancho / $Pixel) * $Pixel
$alto = $Pixel + $Relleno + $ladoIcono + $Relleno + $Pixel

$lienzo = New-Object System.Windows.Controls.Canvas
$lienzo.Width = $ancho + $Sombra
$lienzo.Height = $alto + $Sombra
$lienzo.SnapsToDevicePixels = $true
$lienzo.UseLayoutRounding = $true
[System.Windows.Media.RenderOptions]::SetEdgeMode($lienzo, 'Aliased')

function Poner($elemento, $x, $y) {
    [System.Windows.Controls.Canvas]::SetLeft($elemento, $x)
    [System.Windows.Controls.Canvas]::SetTop($elemento, $y)
    [void]$lienzo.Children.Add($elemento)
}

function Bloque($x, $y, $w, $h, $pincel) {
    if ($w -le 0 -or $h -le 0) { return }
    $r = New-Object System.Windows.Shapes.Rectangle
    $r.Width = $w
    $r.Height = $h
    $r.Fill = $pincel
    Poner $r $x $y
}

# Ovalo con los extremos semicirculares, escalonado a la grilla de pixeles:
# devuelve cuanto se mete hacia adentro cada fila.
function Huecos($h) {
    $radio = $h / 2
    $filas = [int]($h / $Pixel)
    $lista = New-Object 'double[]' $filas
    for ($fila = 0; $fila -lt $filas; $fila++) {
        $dy = [math]::Abs(($fila + 0.5) * $Pixel - $radio)
        $lista[$fila] = [math]::Round(($radio - [math]::Sqrt($radio * $radio - $dy * $dy)) / $Pixel) * $Pixel
    }
    return , $lista
}

function Pastilla($x, $y, $w, $h, $pincel) {
    $huecos = Huecos $h
    for ($fila = 0; $fila -lt $huecos.Count; $fila++) {
        Bloque ($x + $huecos[$fila]) ($y + $fila * $Pixel) ($w - 2 * $huecos[$fila]) $Pixel $pincel
    }
}

Pastilla $Sombra $Sombra $ancho $alto (Pincel '#73000000')
Pastilla 0 0 $ancho $alto (Pincel $colores[3])
# bisel: canto claro arriba, oscuro abajo
$ix = $Pixel
$iy = $Pixel
$iw = $ancho - 2 * $Pixel
$ih = $alto - 2 * $Pixel
Pastilla $ix $iy $iw $ih (Pincel $colores[1])
$huecosInterior = Huecos $ih
$pincelOscuro = Pincel $colores[2]
for ($fila = 1; $fila -lt $huecosInterior.Count; $fila++) {
    $hueco = [math]::Max($huecosInterior[$fila], $huecosInterior[$fila - 1])
    Bloque ($ix + $hueco) ($iy + $fila * $Pixel) ($iw - 2 * $hueco) $Pixel $pincelOscuro
}
Pastilla ($ix + $Pixel) ($iy + $Pixel) ($iw - 2 * $Pixel) ($ih - 2 * $Pixel) (Pincel $colores[0])

$x0 = $Pixel + $RellenoLateral
$y0 = $Pixel + $Relleno
$pinceles = @{}
foreach ($clave in $PaletaIcono.Keys) { $pinceles[$clave] = Pincel $PaletaIcono[$clave] }
for ($fila = 0; $fila -lt $icono.Count; $fila++) {
    for ($col = 0; $col -lt $icono[$fila].Length; $col++) {
        $celda = [string]$icono[$fila][$col]
        if ($pinceles.ContainsKey($celda)) {
            Bloque ($x0 + $col * $Pixel) ($y0 + $fila * $Pixel) $Pixel $Pixel $pinceles[$celda]
        }
    }
}

$tx = $x0 + $ladoIcono + $Separacion
$ty = $y0 + [math]::Floor(($ladoIcono - (2 * $FuentePx + $Interlineado)) / 2)
$mediaSombra = $Pixel / 2
Poner (Texto $aviso.Titulo $colores[3]) ($tx + $mediaSombra) ($ty + $mediaSombra)
Poner (Texto $aviso.Titulo $ColorTitulo) $tx $ty
$ty2 = $ty + $FuentePx + $Interlineado
Poner (Texto $detalle $colores[3]) ($tx + $mediaSombra) ($ty2 + $mediaSombra)
Poner (Texto $detalle $ColorDetalle) $tx $ty2

# --- ventana ------------------------------------------------------------------

$ventana = New-Object System.Windows.Window
$ventana.WindowStyle = 'None'
$ventana.AllowsTransparency = $true
$ventana.Background = [System.Windows.Media.Brushes]::Transparent
$ventana.ResizeMode = 'NoResize'
$ventana.Topmost = $true
$ventana.ShowInTaskbar = $false
$ventana.ShowActivated = $false
$ventana.Focusable = $false
$ventana.WindowStartupLocation = 'Manual'
$ventana.Width = $lienzo.Width
$ventana.Height = $lienzo.Height
$ventana.Left = -10000
$ventana.Top = -10000
$ventana.Content = $lienzo
$ventana.Show()

# monitor donde esta el puntero: ahi es donde se esta mirando. Las medidas de
# pantalla vienen en pixeles fisicos y WPF trabaja en unidades escaladas.
$aUnidades = [System.Windows.PresentationSource]::FromVisual($ventana).CompositionTarget.TransformFromDevice
$area = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).Bounds
$izquierda = $aUnidades.Transform((New-Object System.Windows.Point ($area.Left, $area.Top)))
$derecha = $aUnidades.Transform((New-Object System.Windows.Point ($area.Right, $area.Top)))
$yOculto = $izquierda.Y - $alto - $Sombra
$yFinal = $izquierda.Y + $MargenSuperior
$ventana.Left = [math]::Round($izquierda.X + (($derecha.X - $izquierda.X) - $ancho) / 2)
$ventana.Top = $yOculto

$estado = @{ Entrando = $true; Saliendo = $false }
$crono = [System.Diagnostics.Stopwatch]::StartNew()
$reloj = New-Object System.Windows.Threading.DispatcherTimer
$reloj.Interval = [TimeSpan]::FromMilliseconds(16)
$espera = New-Object System.Windows.Threading.DispatcherTimer
$espera.Interval = [TimeSpan]::FromMilliseconds($aviso.VisibleMs)

function Salir {
    if ($estado.Saliendo) { return }
    $estado.Saliendo = $true
    $estado.Entrando = $false
    $espera.Stop()
    $crono.Restart()
    $reloj.Start()
}

$reloj.Add_Tick({
    $t = [math]::Min($crono.ElapsedMilliseconds / $AnimacionMs, 1.0)
    $p = $t
    if (-not $estado.Entrando) { $p = 1 - $t }
    $y = $yOculto + ($yFinal - $yOculto) * $p
    if ($t -lt 1) {
        # se mueve a saltos de un pixel del dibujo, como un sprite
        $ventana.Top = [math]::Floor($y / $Pixel) * $Pixel
        return
    }
    $ventana.Top = $y
    $reloj.Stop()
    if ($estado.Entrando) { $espera.Start() } else { $ventana.Close() }
})
$espera.Add_Tick({ Salir })
$ventana.Add_MouseLeftButtonDown({ Salir })
$ventana.Add_Closed({ [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown() })

if ($Sonido -and $aviso.Sonido) {
    # un nombre suelto se busca en $Sonidos; tambien vale una ruta completa
    $wav = [System.IO.Path]::Combine($Sonidos, $aviso.Sonido)
    if (Test-Path $wav) {
        try { (New-Object System.Media.SoundPlayer $wav).Play() } catch { }
    }
}

$reloj.Start()
[System.Windows.Threading.Dispatcher]::Run()

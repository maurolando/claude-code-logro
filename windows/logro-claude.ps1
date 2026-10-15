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

function Tiene($objeto, [string]$clave) {
    return ($null -ne $objeto) -and ($objeto.PSObject.Properties.Name -contains $clave)
}
function EsColor($valor) { return ($valor -is [string]) -and ($valor -match '^#[0-9a-fA-F]{6}$') }
function Hora($texto) {
    if (([string]$texto -match '^(\d{1,2}):(\d{2})$') -and ([int]$matches[1] -lt 24) -and ([int]$matches[2] -lt 60)) {
        return New-TimeSpan -Hours ([int]$matches[1]) -Minutes ([int]$matches[2])
    }
    return $null
}
function EnNoMolestar {
    if (-not $NoMolestar) { return $false }
    $desde = Hora $NoMolestar.desde
    $hasta = Hora $NoMolestar.hasta
    if ($null -eq $desde -or $null -eq $hasta) { return $false }
    $ahora = (Get-Date).TimeOfDay
    if ($desde -le $hasta) { return ($ahora -ge $desde) -and ($ahora -lt $hasta) }
    return ($ahora -ge $desde) -or ($ahora -lt $hasta)  # cruza la medianoche
}

# lo que no tenga el tipo esperado se ignora
$cfg = $null
if (Test-Path $Config) {
    try {
        $cfg = [System.IO.File]::ReadAllText($Config, (New-Object System.Text.UTF8Encoding($false))) | ConvertFrom-Json
    } catch {
        [Console]::Error.WriteLine("$Config no es JSON valido, se usan los valores de fabrica: $_")
    }
}
if ($cfg -is [System.Management.Automation.PSCustomObject]) {
    if ((Tiene $cfg 'minimo_s') -and (($cfg.minimo_s -is [int]) -or ($cfg.minimo_s -is [long]) -or ($cfg.minimo_s -is [double]))) {
        $MinimoS = [double]$cfg.minimo_s
    }
    if ((Tiene $cfg 'sonido') -and ($cfg.sonido -is [bool])) { $Sonido = $cfg.sonido }
    if (Tiene $cfg 'no_molestar') { $NoMolestar = $cfg.no_molestar }
    if (EsColor $cfg.color_titulo) { $ColorTitulo = $cfg.color_titulo }
    if (EsColor $cfg.color_detalle) { $ColorDetalle = $cfg.color_detalle }
    if (Tiene $cfg 'avisos') {
        foreach ($propiedad in $cfg.avisos.PSObject.Properties) {
            if (-not $Avisos.ContainsKey($propiedad.Name)) { continue }
            $destino = $Avisos[$propiedad.Name]
            $cambios = $propiedad.Value
            if ((Tiene $cambios 'activo') -and ($cambios.activo -is [bool])) { $destino.Activo = $cambios.activo }
            foreach ($par in @(@('titulo', 'Titulo'), @('detalle', 'Detalle'), @('sonido', 'Sonido'))) {
                if ((Tiene $cambios $par[0]) -and ($cambios.($par[0]) -is [string])) { $destino[$par[1]] = $cambios.($par[0]) }
            }
            if ((Tiene $cambios 'visible_ms') -and (($cambios.visible_ms -is [int]) -or ($cambios.visible_ms -is [long]))) {
                $destino.VisibleMs = [int]$cambios.visible_ms
            }
            if (Tiene $cambios 'colores') {
                $lista = @($cambios.colores)
                if (($lista.Count -eq 4) -and -not ($lista | Where-Object { -not (EsColor $_) })) { $destino.Colores = $lista }
            }
        }
    }
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
$icono = $aviso.Icono
$colores = $Verde
if ($aviso.Colores) { $colores = $aviso.Colores }
# las marcas ya se actualizaron aunque el aviso este apagado o en horario de no molestar
if (($aviso.Activo -eq $false) -or (EnNoMolestar)) { exit 0 }

$nombre = 'Claude Code'
$cwd = $cwd.TrimEnd('\', '/')
if ($cwd) { $nombre = ($cwd -split '[\\/]')[-1] }
$detalle = "$texto $([char]0xB7) $nombre"
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

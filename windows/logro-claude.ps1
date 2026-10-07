# Aviso tipo "logro" en pixel art, arriba al centro de la pantalla (Windows).
#
# Lo disparan los hooks de Claude Code (settings.json), que le pasan por stdin
# un JSON con el cwd de la sesion: Stop sin argumentos (termino), Notification
# con "permiso" (espera un permiso), PreToolUse de AskUserQuestion con
# "pregunta" (hace una pregunta) y su PostToolUse con "respondida", que no
# muestra nada.
#
# Archivo en ASCII puro a proposito: Windows PowerShell 5.1 lee mal los acentos
# de un .ps1 sin BOM. Los textos que llevan acento se arman con [char].
param([string]$Modo = 'terminado')

$MargenSuperior = 40
$AnimacionMs = 300
$PreguntaAbiertaMaxS = 600  # por si la pregunta se cancela y nadie borra la marca
$Sonidos = Join-Path $env:WINDIR 'Media'

# Press Start 2P (junto a este script) se ve nitida solo en multiplos de 8 px
$ArchivoFuente = Join-Path $PSScriptRoot 'PressStart2P-Regular.ttf'
$FuentePx = 16
$Pixel = 4  # tamano de cada "pixel" del dibujo

$Verde = '#17602c'
$VerdeClaro = '#35904a'
$VerdeOscuro = '#0d401c'
$Borde = '#04140a'
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
}

$Relleno = 5 * $Pixel
$RellenoLateral = 10 * $Pixel  # los extremos son redondos: el contenido va mas adentro
$Separacion = 5 * $Pixel
$Interlineado = 3 * $Pixel
$Sombra = 2 * $Pixel

# --- entrada del hook ---------------------------------------------------------

$sesion = ''
$cwd = ''
$mensaje = ''
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
        }
    }
} catch { }

# Una pregunta dispara tambien el aviso de permiso (unos segundos despues):
# mientras este abierta se deja solo el de pregunta. La marca la pone el
# PreToolUse de AskUserQuestion y la borra su PostToolUse ("respondida").
$marca = Join-Path $env:TEMP "claude-logro-pregunta-$sesion"
if ($Modo -eq 'pregunta') {
    Set-Content -Path $marca -Value ''
} elseif ($Modo -eq 'respondida') {
    Remove-Item -Path $marca -ErrorAction SilentlyContinue
    exit 0
} elseif ($Modo -eq 'permiso') {
    if ($mensaje -like '*AskUserQuestion*') { exit 0 }
    $archivoMarca = Get-Item -Path $marca -ErrorAction SilentlyContinue
    if ($archivoMarca -and ((Get-Date) - $archivoMarca.LastWriteTime).TotalSeconds -lt $PreguntaAbiertaMaxS) { exit 0 }
}

if (-not $Avisos.ContainsKey($Modo)) { $Modo = 'terminado' }
$aviso = $Avisos[$Modo]
$icono = $aviso.Icono

$nombre = 'Claude Code'
$cwd = $cwd.TrimEnd('\', '/')
if ($cwd) { $nombre = ($cwd -split '[\\/]')[-1] }
$detalle = "$($aviso.Detalle) $([char]0xB7) $nombre"
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
Pastilla 0 0 $ancho $alto (Pincel $Borde)
# bisel: canto claro arriba, oscuro abajo
$ix = $Pixel
$iy = $Pixel
$iw = $ancho - 2 * $Pixel
$ih = $alto - 2 * $Pixel
Pastilla $ix $iy $iw $ih (Pincel $VerdeClaro)
$huecosInterior = Huecos $ih
$pincelOscuro = Pincel $VerdeOscuro
for ($fila = 1; $fila -lt $huecosInterior.Count; $fila++) {
    $hueco = [math]::Max($huecosInterior[$fila], $huecosInterior[$fila - 1])
    Bloque ($ix + $hueco) ($iy + $fila * $Pixel) ($iw - 2 * $hueco) $Pixel $pincelOscuro
}
Pastilla ($ix + $Pixel) ($iy + $Pixel) ($iw - 2 * $Pixel) ($ih - 2 * $Pixel) (Pincel $Verde)

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
Poner (Texto $aviso.Titulo $Borde) ($tx + $mediaSombra) ($ty + $mediaSombra)
Poner (Texto $aviso.Titulo $ColorTitulo) $tx $ty
$ty2 = $ty + $FuentePx + $Interlineado
Poner (Texto $detalle $Borde) ($tx + $mediaSombra) ($ty2 + $mediaSombra)
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

if ($aviso.Sonido) {
    $wav = Join-Path $Sonidos $aviso.Sonido
    if (Test-Path $wav) {
        try { (New-Object System.Media.SoundPlayer $wav).Play() } catch { }
    }
}

$reloj.Start()
[System.Windows.Threading.Dispatcher]::Run()

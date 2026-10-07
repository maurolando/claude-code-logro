#!/usr/bin/env python3
"""Popup tipo "logro" en pixel art, arriba al centro de la pantalla.

Lo disparan los hooks de Claude Code (~/.claude/settings.json), que le pasan
por stdin un JSON con el cwd de la sesión: Stop sin argumentos (terminó) y
Notification con el argumento "permiso" (espera un permiso) y PreToolUse de
AskUserQuestion con el argumento "pregunta" (hace una pregunta); su PostToolUse
pasa "respondida", que no muestra nada.
"""
import json
import os
import subprocess
import sys
import time

MARGEN_SUPERIOR = 40
ANIMACION_MS = 300
SONIDOS = "/usr/share/sounds/ocean/stereo/"
PREGUNTA_ABIERTA_MAX_S = 600  # por si la pregunta se cancela y nadie borra la marca

# Press Start 2P (~/.local/share/fonts) se ve nítida solo en múltiplos de 8 px
FUENTE = "Press Start 2P"
FUENTE_PX = 16
PIXEL = 4  # tamaño de cada "pixel" del dibujo

VERDE = "#17602c"
VERDE_CLARO = "#35904a"
VERDE_OSCURO = "#0d401c"
BORDE = "#04140a"
COLOR_TITULO = "#ffe45c"
COLOR_DETALLE = "#ffffff"

PALETA_ICONO = {
    "o": "#3b2a00", "y": "#ffd23f", "l": "#fff3a0", "d": "#c98a00",
    "w": "#ffffff", "g": "#c8ccd4", "s": "#7b8190",
}
TROFEO = [
    "..oooooooooooo..",
    ".oolyyyyyyyydoo.",
    "o.olyyyyyyyydo.o",
    "o.olyyyyyyyydo.o",
    "o.olyyyyyyyydo.o",
    ".oolyyyyyyyydoo.",
    "...olyyyyyydo...",
    "....olyyyydo....",
    ".....oyyddo.....",
    "......oydo......",
    "......oydo......",
    ".....ooydoo.....",
    "....olyyyydo....",
    "...olyyyyyydo...",
    "...oooooooooo...",
    "................",
]
CANDADO = [
    "................",
    ".....oooooo.....",
    "....owggggso....",
    "...owgoooogso...",
    "...owgo..ogso...",
    "...owgo..ogso...",
    ".oooooooooooooo.",
    ".olyyyyyyyyyydo.",
    ".olyyyyooyyyydo.",
    ".olyyyyooyyyydo.",
    ".olyyyyooyyyydo.",
    ".olyyyyyyyyyydo.",
    ".olyyyyyyyyyydo.",
    ".oddddddddddddo.",
    ".oooooooooooooo.",
    "................",
]
PREGUNTA = [
    "................",
    "....oooooooo....",
    "...olyyyyyydo...",
    "..olyyyyyyyydo..",
    "..olydoooolydo..",
    "..oooo...olydo..",
    "........olydo...",
    ".......olydo....",
    "......olydo.....",
    "......ooooo.....",
    "................",
    "......ooooo.....",
    "......olydo.....",
    "......olydo.....",
    "......ooooo.....",
    "................",
]

# sonido: "" para silenciarlo
AVISOS = {
    "terminado": {
        "titulo": "TAREA COMPLETADA",
        "detalle": "Claude terminó",
        "icono": TROFEO,
        "visible_ms": 4500,
        "sonido": "completion-success.oga",
    },
    "permiso": {
        "titulo": "PERMISO REQUERIDO",
        "detalle": "Claude espera",
        "icono": CANDADO,
        "visible_ms": 8000,
        "sonido": "dialog-question.oga",
    },
    "pregunta": {
        "titulo": "PREGUNTA PENDIENTE",
        "detalle": "Claude pregunta",
        "icono": PREGUNTA,
        "visible_ms": 8000,
        "sonido": "message-attention.oga",
    },
}

RELLENO = 5 * PIXEL
RELLENO_LATERAL = 10 * PIXEL  # los extremos son redondos: el contenido va más adentro
SEPARACION = 5 * PIXEL
INTERLINEADO = 3 * PIXEL
SOMBRA = 2 * PIXEL


def entrada():
    if not sys.stdin.isatty():
        try:
            datos = json.load(sys.stdin)
            if isinstance(datos, dict):
                return datos
        except ValueError:
            pass
    return {}


def es_permiso_de_pregunta(modo, datos):
    """Una pregunta dispara también el aviso de permiso (unos segundos después):
    mientras esté abierta se deja solo el de pregunta. La marca la pone el
    PreToolUse de AskUserQuestion y la borra su PostToolUse ("respondida")."""
    marca = os.path.join(
        os.environ.get("XDG_RUNTIME_DIR", "/tmp"), f"claude-logro-pregunta-{datos.get('session_id', '')}"
    )
    if modo == "pregunta":
        open(marca, "w").close()
        return False
    if modo == "respondida":
        try:
            os.remove(marca)
        except OSError:
            pass
        return True
    if modo != "permiso":
        return False
    if "AskUserQuestion" in str(datos.get("message", "")):
        return True
    try:
        return time.time() - os.path.getmtime(marca) < PREGUNTA_ABIERTA_MAX_S
    except OSError:
        return False


def rgb(hexa):
    return tuple(int(hexa[i : i + 2], 16) / 255 for i in (1, 3, 5))


def main():
    datos = entrada()
    modo = sys.argv[1] if len(sys.argv) > 1 else "terminado"
    if es_permiso_de_pregunta(modo, datos):
        return
    nombre = os.path.basename(str(datos.get("cwd", "")).rstrip("/")) or "Claude Code"
    aviso = AVISOS.get(modo, AVISOS["terminado"])
    titulo, icono = aviso["titulo"], aviso["icono"]
    # en Wayland una ventana no puede elegir su posición: se usa XWayland
    os.environ.setdefault("GDK_BACKEND", "x11")
    try:
        import cairo
        import gi

        gi.require_version("Gtk", "3.0")
        gi.require_version("Gdk", "3.0")
        gi.require_version("PangoCairo", "1.0")
        from gi.repository import Gdk, GLib, Gtk, Pango, PangoCairo

        if not Gtk.init_check()[0]:
            raise RuntimeError("sin display")
    except Exception:
        subprocess.call(["notify-send", "-a", "Claude Code", aviso["detalle"], nombre])
        return

    detalle = f"{aviso['detalle']} · {nombre}"
    if len(detalle) > 40:
        detalle = detalle[:39] + "…"

    ventana = Gtk.Window(type=Gtk.WindowType.POPUP)
    ventana.set_type_hint(Gdk.WindowTypeHint.NOTIFICATION)
    ventana.set_keep_above(True)
    ventana.set_accept_focus(False)
    ventana.set_app_paintable(True)
    pantalla = Gdk.Screen.get_default()
    visual = pantalla.get_rgba_visual()
    if visual and pantalla.is_composited():
        ventana.set_visual(visual)

    fuente = Pango.FontDescription(FUENTE)
    fuente.set_absolute_size(FUENTE_PX * Pango.SCALE)
    sin_suavizado = cairo.FontOptions()
    sin_suavizado.set_antialias(cairo.ANTIALIAS_NONE)
    sin_suavizado.set_hint_style(cairo.HINT_STYLE_FULL)

    def capa_texto(contexto_pango, texto):
        capa = Pango.Layout.new(contexto_pango)
        capa.set_font_description(fuente)
        capa.set_text(texto, -1)
        return capa

    ctx_medicion = ventana.create_pango_context()
    PangoCairo.context_set_font_options(ctx_medicion, sin_suavizado)
    ancho_texto = max(capa_texto(ctx_medicion, t).get_pixel_size()[0] for t in (titulo, detalle))

    lado_icono = len(icono) * PIXEL
    ancho = PIXEL + RELLENO_LATERAL + lado_icono + SEPARACION + ancho_texto + RELLENO_LATERAL + PIXEL
    alto = PIXEL + RELLENO + lado_icono + RELLENO + PIXEL
    ancho += -ancho % PIXEL

    def pastilla(cr, x, y, w, h):
        """Óvalo con los extremos semicirculares, escalonado a la grilla de pixeles."""
        radio = h / 2
        for fila in range(h // PIXEL):
            dy = abs((fila + 0.5) * PIXEL - radio)
            hueco = round((radio - (radio**2 - dy**2) ** 0.5) / PIXEL) * PIXEL
            cr.rectangle(x + hueco, y + fila * PIXEL, w - 2 * hueco, PIXEL)

    def dibujar(_, cr):
        cr.set_antialias(cairo.ANTIALIAS_NONE)
        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(0, 0, 0, 0)
        cr.paint()
        cr.set_operator(cairo.OPERATOR_OVER)

        cr.set_source_rgba(0, 0, 0, 0.45)
        pastilla(cr, SOMBRA, SOMBRA, ancho, alto)
        cr.fill()
        cr.set_source_rgb(*rgb(BORDE))
        pastilla(cr, 0, 0, ancho, alto)
        cr.fill()
        # bisel: canto claro arriba, oscuro abajo
        ix, iy, iw, ih = PIXEL, PIXEL, ancho - 2 * PIXEL, alto - 2 * PIXEL
        cr.set_source_rgb(*rgb(VERDE_CLARO))
        pastilla(cr, ix, iy, iw, ih)
        cr.fill()
        cr.save()
        pastilla(cr, ix, iy, iw, ih)
        cr.clip()
        cr.set_source_rgb(*rgb(VERDE_OSCURO))
        pastilla(cr, ix, iy + PIXEL, iw, ih)
        cr.fill()
        cr.restore()
        cr.set_source_rgb(*rgb(VERDE))
        pastilla(cr, ix + PIXEL, iy + PIXEL, iw - 2 * PIXEL, ih - 2 * PIXEL)
        cr.fill()

        x0, y0 = PIXEL + RELLENO_LATERAL, PIXEL + RELLENO
        for fila, linea in enumerate(icono):
            for col, celda in enumerate(linea):
                if celda in PALETA_ICONO:
                    cr.set_source_rgb(*rgb(PALETA_ICONO[celda]))
                    cr.rectangle(x0 + col * PIXEL, y0 + fila * PIXEL, PIXEL, PIXEL)
                    cr.fill()

        ctx_pango = PangoCairo.create_context(cr)
        PangoCairo.context_set_font_options(ctx_pango, sin_suavizado)
        tx = x0 + lado_icono + SEPARACION
        ty = y0 + (lado_icono - (2 * FUENTE_PX + INTERLINEADO)) // 2
        for texto, color, y in ((titulo, COLOR_TITULO, ty), (detalle, COLOR_DETALLE, ty + FUENTE_PX + INTERLINEADO)):
            capa = capa_texto(ctx_pango, texto)
            for dx, dy, c in ((PIXEL // 2, PIXEL // 2, BORDE), (0, 0, color)):
                cr.set_source_rgb(*rgb(c))
                cr.move_to(tx + dx, y + dy)
                PangoCairo.show_layout(cr, capa)

    lienzo = Gtk.DrawingArea()
    lienzo.set_size_request(ancho + SOMBRA, alto + SOMBRA)
    lienzo.connect("draw", dibujar)
    ventana.add(lienzo)
    lienzo.show()

    # monitor donde está el puntero: ahí es donde se está mirando
    display = Gdk.Display.get_default()
    _, px, py = display.get_default_seat().get_pointer().get_position()
    geo = display.get_monitor_at_point(px, py).get_geometry()
    x = geo.x + (geo.width - ancho) // 2
    y_oculto = geo.y - alto - SOMBRA
    y_final = geo.y + MARGEN_SUPERIOR

    ventana.move(x, y_oculto)
    ventana.show()

    paso_ms = 16
    estado = {"t": 0}

    def animar(entrando):
        estado["t"] += paso_ms
        p = min(estado["t"] / ANIMACION_MS, 1.0)
        if not entrando:
            p = 1 - p
        # se mueve a saltos de un pixel del dibujo, como un sprite
        y = y_oculto + (y_final - y_oculto) * p
        ventana.move(x, int(y // PIXEL * PIXEL) if 0 < p < 1 else int(y))
        if 0 < p < 1:
            return True
        if entrando:
            GLib.timeout_add(aviso["visible_ms"], salir)
        else:
            Gtk.main_quit()
        return False

    def salir(*_):
        if estado.get("saliendo"):
            return False
        estado["saliendo"] = True
        estado["t"] = 0
        GLib.timeout_add(paso_ms, animar, False)
        return False

    ventana.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
    ventana.connect("button-press-event", salir)

    sonido = SONIDOS + aviso["sonido"]
    if aviso["sonido"] and os.path.exists(sonido):
        subprocess.Popen(["paplay", sonido], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    GLib.timeout_add(paso_ms, animar, True)
    Gtk.main()


if __name__ == "__main__":
    main()

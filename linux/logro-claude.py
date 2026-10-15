#!/usr/bin/env python3
"""Popup tipo "logro" en pixel art, arriba al centro de la pantalla.

Lo disparan los hooks de Claude Code (~/.claude/settings.json), que le pasan
por stdin un JSON con el cwd de la sesión. El argumento dice qué pasó:

  (ninguno)   Stop: terminó. Solo avisa si la tarea llevó al menos MINIMO_S.
  error       StopFailure: se cortó por un error de la API.
  permiso     Notification permission_prompt: espera un permiso.
  pregunta    PreToolUse de AskUserQuestion: muestra un cuadro de opciones.
  respondida  PostToolUse de AskUserQuestion: no muestra nada.
  inicio      UserPromptSubmit: no muestra nada, anota la hora para medir.

Los valores de abajo son los de fábrica: cada uno los cambia en
~/.claude/logro.json (ver ejemplo-logro.json en el repo), que no se pisa al
actualizar.
"""
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime

MARGEN_SUPERIOR = 40
ANIMACION_MS = 300
CONFIG = os.path.expanduser("~/.claude/logro.json")
SONIDOS = "/usr/share/sounds/ocean/stereo/"
SONIDO = True  # False silencia todos los avisos
NO_MOLESTAR = None  # {"desde": "22:00", "hasta": "08:00"}: en ese horario no sale ningún aviso
PREGUNTA_ABIERTA_MAX_S = 600  # por si la pregunta se cancela y nadie borra la marca
MINIMO_S = 30  # el trofeo solo sale si la tarea llevó al menos esto; 0 para avisar siempre

# Press Start 2P (~/.local/share/fonts) se ve nítida solo en múltiplos de 8 px
FUENTE = "Press Start 2P"
FUENTE_PX = 16
PIXEL = 4  # tamaño de cada "pixel" del dibujo

# fondo, canto claro, canto oscuro y borde
VERDE = ("#17602c", "#35904a", "#0d401c", "#04140a")
ROJO = ("#7a1616", "#b33a3a", "#4f0c0c", "#170404")
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

CALAVERA = [
    "................",
    "................",
    "................",
    "....oooooooo....",
    "...owwwwwwwwo...",
    "..owwwwwwwwwwo..",
    "..owooowwooogo..",
    "..owooowwooogo..",
    "..owwwwoowwwgo..",
    "...owwwwwwwgo...",
    "...owowowowgo...",
    "....owwwwwgo....",
    "....oooooooo....",
    "................",
    "................",
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
    "error": {
        "titulo": "CLAUDE SE DETUVO",
        "detalle": "Error de la API",
        "icono": CALAVERA,
        "visible_ms": 10000,
        "sonido": "dialog-error.oga",
        "colores": ROJO,
    },
}

ERRORES = {
    "rate_limit": "Límite de uso",
    "overloaded": "API saturada",
    "authentication_failed": "Falló el login",
    "billing_error": "Facturación",
    "server_error": "Error del servidor",
    "max_output_tokens": "Respuesta muy larga",
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


def leer_config():
    try:
        with open(CONFIG, encoding="utf-8") as f:
            config = json.load(f)
    except OSError:
        return {}
    except ValueError as e:
        print(f"{CONFIG} no es JSON válido, se usan los valores de fábrica: {e}", file=sys.stderr)
        return {}
    return config if isinstance(config, dict) else {}


def es_color(valor):
    return isinstance(valor, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", valor) is not None


def aplicar_config(config):
    """Pisa los valores de fábrica con los de ~/.claude/logro.json; lo que no
    tenga el tipo esperado se ignora."""
    global MINIMO_S, SONIDO, NO_MOLESTAR, COLOR_TITULO, COLOR_DETALLE
    if isinstance(config.get("minimo_s"), (int, float)):
        MINIMO_S = config["minimo_s"]
    if isinstance(config.get("sonido"), bool):
        SONIDO = config["sonido"]
    if "no_molestar" in config and (config["no_molestar"] is None or isinstance(config["no_molestar"], dict)):
        NO_MOLESTAR = config["no_molestar"]
    if es_color(config.get("color_titulo")):
        COLOR_TITULO = config["color_titulo"]
    if es_color(config.get("color_detalle")):
        COLOR_DETALLE = config["color_detalle"]
    avisos = config.get("avisos")
    for modo, cambios in (avisos.items() if isinstance(avisos, dict) else ()):
        if modo not in AVISOS or not isinstance(cambios, dict):
            continue
        aviso = AVISOS[modo]
        for clave, tipo in (("activo", bool), ("titulo", str), ("detalle", str), ("visible_ms", int), ("sonido", str)):
            if isinstance(cambios.get(clave), tipo):
                aviso[clave] = cambios[clave]
        colores = cambios.get("colores")
        if isinstance(colores, list) and len(colores) == 4 and all(map(es_color, colores)):
            aviso["colores"] = tuple(colores)


def en_no_molestar():
    if not NO_MOLESTAR:
        return False
    try:
        desde, hasta = (datetime.strptime(NO_MOLESTAR[k], "%H:%M").time() for k in ("desde", "hasta"))
    except (KeyError, TypeError, ValueError):
        return False
    ahora = datetime.now().time()
    if desde <= hasta:
        return desde <= ahora < hasta
    return ahora >= desde or ahora < hasta  # cruza la medianoche


def marca(cual, datos):
    carpeta = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    return os.path.join(carpeta, f"claude-logro-{cual}-{datos.get('session_id', '')}")


def tocar(ruta):
    open(ruta, "w").close()


def antiguedad(ruta):
    try:
        return time.time() - os.path.getmtime(ruta)
    except OSError:
        return None


def duracion(segundos):
    s = int(segundos)
    if s < 60:
        return f"{s}s"
    if s < 3600:
        return f"{s // 60}m {s % 60:02d}s"
    return f"{s // 3600}h {s % 3600 // 60:02d}m"


def detalle_del_aviso(modo, datos):
    """Texto de la segunda línea, o None si no hay que mostrar nada.

    Una pregunta dispara también el aviso de permiso (unos segundos después):
    mientras esté abierta se deja solo el de pregunta. Esa marca la pone el
    PreToolUse de AskUserQuestion y la borra su PostToolUse. La espera de la
    respuesta no cuenta como tiempo de la tarea: al responder se vuelve a
    anotar la hora de inicio."""
    if modo == "inicio":
        tocar(marca("inicio", datos))
        return None
    if modo == "respondida":
        try:
            os.remove(marca("pregunta", datos))
        except OSError:
            pass
        tocar(marca("inicio", datos))
        return None
    aviso = AVISOS[modo]
    if modo == "pregunta":
        tocar(marca("pregunta", datos))
    elif modo == "permiso":
        if "AskUserQuestion" in str(datos.get("message", "")):
            return None
        edad = antiguedad(marca("pregunta", datos))
        if edad is not None and edad < PREGUNTA_ABIERTA_MAX_S:
            return None
    elif modo == "error":
        return ERRORES.get(datos.get("error"), aviso["detalle"])
    elif modo == "terminado":
        # sin marca (hooks recién instalados) se avisa igual, sin la duración
        edad = antiguedad(marca("inicio", datos))
        if edad is not None:
            if edad < MINIMO_S:
                return None
            return f"{aviso['detalle']} en {duracion(edad)}"
    return aviso["detalle"]


def rgb(hexa):
    return tuple(int(hexa[i : i + 2], 16) / 255 for i in (1, 3, 5))


def main():
    aplicar_config(leer_config())
    datos = entrada()
    modo = sys.argv[1] if len(sys.argv) > 1 else "terminado"
    if modo not in AVISOS and modo not in ("inicio", "respondida"):
        modo = "terminado"
    # las marcas se actualizan aunque el aviso esté apagado o en horario de no molestar
    texto = detalle_del_aviso(modo, datos)
    if texto is None or not AVISOS[modo].get("activo", True) or en_no_molestar():
        return
    nombre = os.path.basename(str(datos.get("cwd", "")).rstrip("/")) or "Claude Code"
    aviso = AVISOS[modo]
    titulo, icono = aviso["titulo"], aviso["icono"]
    fondo, canto_claro, canto_oscuro, borde = aviso.get("colores", VERDE)
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
        subprocess.call(["notify-send", "-a", "Claude Code", texto, nombre])
        return

    detalle = f"{texto} · {nombre}"
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
        cr.set_source_rgb(*rgb(borde))
        pastilla(cr, 0, 0, ancho, alto)
        cr.fill()
        # bisel: canto claro arriba, oscuro abajo
        ix, iy, iw, ih = PIXEL, PIXEL, ancho - 2 * PIXEL, alto - 2 * PIXEL
        cr.set_source_rgb(*rgb(canto_claro))
        pastilla(cr, ix, iy, iw, ih)
        cr.fill()
        cr.save()
        pastilla(cr, ix, iy, iw, ih)
        cr.clip()
        cr.set_source_rgb(*rgb(canto_oscuro))
        pastilla(cr, ix, iy + PIXEL, iw, ih)
        cr.fill()
        cr.restore()
        cr.set_source_rgb(*rgb(fondo))
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
            for dx, dy, c in ((PIXEL // 2, PIXEL // 2, borde), (0, 0, color)):
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

    # un nombre suelto se busca en SONIDOS; también vale una ruta completa
    sonido = os.path.join(SONIDOS, os.path.expanduser(aviso["sonido"]))
    if SONIDO and aviso["sonido"] and os.path.exists(sonido):
        subprocess.Popen(["paplay", sonido], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    GLib.timeout_add(paso_ms, animar, True)
    Gtk.main()


if __name__ == "__main__":
    main()

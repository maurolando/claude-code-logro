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
  probar      a mano: muestra los cuatro avisos con la configuración actual.

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
import unicodedata
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


NOMBRES_COLOR = {
    "rojo": "#c62828", "verde": "#2e7d32", "azul": "#1565c0", "celeste": "#4fc3f7",
    "turquesa": "#00897b", "amarillo": "#fdd835", "dorado": "#ffc107", "naranja": "#ef6c00",
    "rosa": "#ec407a", "violeta": "#7b1fa2", "morado": "#7b1fa2", "purpura": "#7b1fa2",
    "lila": "#ce93d8", "marron": "#6d4c41", "gris": "#757575", "negro": "#000000",
    "blanco": "#ffffff",
}
CLAVES = {"minimo_s", "sonido", "no_molestar", "fondo", "color_titulo", "color_detalle", "avisos"}
CLAVES_AVISO = {"activo", "titulo", "detalle", "visible_ms", "sonido", "fondo", "colores"}


def relajar_json(texto):
    """Acepta lo que la gente escribe a mano: comentarios // y /* */, comas de
    más antes de } o ], y valores sin comillas como #7303fc o azul. Conserva
    los saltos de línea para que un error siga marcando la línea del archivo."""

    def recorrer(texto, fuera_de_texto):
        salida, i = [], 0
        while i < len(texto):
            if texto[i] == '"':
                j = i + 1
                while j < len(texto) and texto[j] != '"':
                    j += 2 if texto[j] == "\\" else 1
                salida.append(texto[i : j + 1])
                i = j + 1
            else:
                trozo, i = fuera_de_texto(texto, i)
                salida.append(trozo)
        return "".join(salida)

    def comentarios_y_palabras(texto, i):
        if texto.startswith("//", i):
            fin = texto.find("\n", i)
            return "", len(texto) if fin < 0 else fin
        if texto.startswith("/*", i):
            fin = texto.find("*/", i + 2)
            fin = len(texto) if fin < 0 else fin + 2
            return "\n" * texto.count("\n", i, fin), fin
        palabra = re.match(r"#?[^\W\d][\w#-]*|#[0-9a-fA-F]+", texto[i:])
        if palabra:
            literal = palabra.group() in ("true", "false", "null")
            return palabra.group() if literal else f'"{palabra.group()}"', i + palabra.end()
        return texto[i], i + 1

    def comas_de_mas(texto, i):
        if texto[i] == "," and re.match(r"\s*[}\]]", texto[i + 1 :]):
            return "", i + 1
        return texto[i], i + 1

    return recorrer(recorrer(texto, comentarios_y_palabras), comas_de_mas)


def leer_config(problemas):
    try:
        with open(CONFIG, encoding="utf-8") as f:
            texto = f.read()
    except OSError:
        return {}
    try:
        config = json.loads(relajar_json(texto))
    except ValueError as e:
        problemas.append(f"error en la línea {getattr(e, 'lineno', '?')}")
        return {}
    if not isinstance(config, dict):
        problemas.append("tiene que empezar con {")
        return {}
    return config


def normalizar_color(valor):
    """'#7303fc', '7303fc', '#73f' o un nombre ('azul', 'violeta') -> '#rrggbb'."""
    if not isinstance(valor, str):
        return None
    v = "".join(c for c in unicodedata.normalize("NFD", valor.strip().lower()) if not unicodedata.combining(c))
    v = NOMBRES_COLOR.get(v, v).lstrip("#")
    if re.fullmatch(r"[0-9a-f]{3}", v):
        v = "".join(c * 2 for c in v)
    return "#" + v if re.fullmatch(r"[0-9a-f]{6}", v) else None


def bisel(fondo):
    """Del color de fondo saca el canto claro, el canto oscuro y el borde."""
    r, g, b = (int(fondo[i : i + 2], 16) for i in (1, 3, 5))

    def a_hex(*canales):
        return "#" + "".join(f"{max(0, min(255, round(c))):02x}" for c in canales)

    return (
        fondo,
        a_hex(r * 1.35 + 22, g * 1.35 + 22, b * 1.35 + 22),
        a_hex(r * 0.65, g * 0.65, b * 0.65),
        a_hex(r * 0.18, g * 0.18, b * 0.18),
    )


def aplicar_config(config, problemas):
    """Pisa los valores de fábrica con los de ~/.claude/logro.json. Lo que no
    sirva se ignora y queda anotado en problemas, para mostrarlo."""
    global MINIMO_S, SONIDO, NO_MOLESTAR, COLOR_TITULO, COLOR_DETALLE

    def color(clave, valor):
        normal = normalizar_color(valor)
        if normal is None:
            problemas.append(f"{clave}: color inválido")
        return normal

    for clave in config:
        if clave not in CLAVES:
            problemas.append(f"no existe {clave}")
    if "minimo_s" in config:
        if isinstance(config["minimo_s"], (int, float)) and not isinstance(config["minimo_s"], bool):
            MINIMO_S = config["minimo_s"]
        else:
            problemas.append("minimo_s: tiene que ser un número")
    if "sonido" in config:
        if isinstance(config["sonido"], bool):
            SONIDO = config["sonido"]
        else:
            problemas.append("sonido: true o false")
    if "no_molestar" in config:
        horario = config["no_molestar"]
        if horario is None or (isinstance(horario, dict) and horas(horario)):
            NO_MOLESTAR = horario
        else:
            problemas.append('no_molestar: {"desde": "22:00", "hasta": "08:00"}')
    for clave in ("color_titulo", "color_detalle"):
        if clave in config and (normal := color(clave, config[clave])):
            globals()[clave.upper()] = normal
    if "fondo" in config and (normal := color("fondo", config["fondo"])):
        for modo, aviso in AVISOS.items():
            if modo != "error":  # el error queda rojo para que se distinga
                aviso["colores"] = bisel(normal)

    avisos = config.get("avisos", {})
    if not isinstance(avisos, dict):
        problemas.append("avisos: tiene que ir entre { }")
        avisos = {}
    for modo, cambios in avisos.items():
        if modo not in AVISOS:
            problemas.append(f"no existe el aviso {modo}")
            continue
        if not isinstance(cambios, dict):
            problemas.append(f"{modo}: tiene que ir entre {{ }}")
            continue
        aviso = AVISOS[modo]
        for clave in cambios:
            if clave not in CLAVES_AVISO:
                problemas.append(f"no existe {modo}.{clave}")
        for clave, tipo, ayuda in (
            ("activo", bool, "true o false"),
            ("titulo", str, "va entre comillas"),
            ("detalle", str, "va entre comillas"),
            ("visible_ms", int, "milisegundos, sin comillas"),
            ("sonido", str, "va entre comillas"),
        ):
            if clave in cambios:
                if isinstance(cambios[clave], tipo) and not (tipo is int and isinstance(cambios[clave], bool)):
                    aviso[clave] = cambios[clave]
                else:
                    problemas.append(f"{modo}.{clave}: {ayuda}")
        if "fondo" in cambios and (normal := color(f"{modo}.fondo", cambios["fondo"])):
            aviso["colores"] = bisel(normal)
        if "colores" in cambios:
            lista = cambios["colores"]
            normales = [normalizar_color(c) for c in lista] if isinstance(lista, list) else []
            if len(normales) == 4 and all(normales):
                aviso["colores"] = tuple(normales)
            else:
                problemas.append(f"{modo}.colores: van 4 colores")


def horas(horario):
    try:
        return tuple(datetime.strptime(str(horario[k]), "%H:%M").time() for k in ("desde", "hasta"))
    except (KeyError, TypeError, ValueError):
        return None


def en_no_molestar():
    if not NO_MOLESTAR:
        return False
    desde, hasta = horas(NO_MOLESTAR)
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


def probar(problemas):
    print(f"Configuración: {CONFIG}" + ("" if os.path.exists(CONFIG) else " (no existe: valores de fábrica)"))
    for problema in problemas:
        print(f"  problema: {problema}")
    if not problemas:
        print("  sin problemas")
    if en_no_molestar():
        print("  ahora es horario de no molestar: fuera de esta prueba no saldría ningún aviso")
    datos = json.dumps({"cwd": os.getcwd()})
    for modo, aviso in AVISOS.items():
        if not aviso.get("activo", True):
            print(f"{modo}: apagado")
            continue
        print(f"{modo}: {aviso['titulo']}")
        subprocess.run(
            [sys.executable, os.path.abspath(__file__), modo],
            input=datos, text=True, env={**os.environ, "LOGRO_PRUEBA": "1"},
        )


def main():
    problemas = []
    aplicar_config(leer_config(problemas), problemas)
    for problema in problemas:
        print(f"{CONFIG}: {problema}", file=sys.stderr)
    modo = sys.argv[1] if len(sys.argv) > 1 else "terminado"
    if modo == "probar":
        probar(problemas)
        return
    datos = entrada()
    if modo not in AVISOS and modo not in ("inicio", "respondida"):
        modo = "terminado"
    if os.environ.get("LOGRO_PRUEBA"):
        # vista previa: sin marcas ni umbral ni horario, y más corta
        texto = {
            "terminado": f"{AVISOS[modo]['detalle']} en 4m 12s",
            "error": ERRORES["rate_limit"],
        }.get(modo, AVISOS[modo]["detalle"])
        AVISOS[modo]["visible_ms"] = min(AVISOS[modo]["visible_ms"], 2500)
    else:
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
    if problemas:
        # mientras logro.json tenga algo mal, se avisa ahí en vez del detalle
        detalle = f"logro.json: {problemas[0]}"
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

# claude-code-logro

Avisos tipo "logro" de videojuego para [Claude Code](https://claude.com/claude-code): una pastilla verde en pixel art que aparece arriba al centro de la pantalla.

| Ícono | Cuándo aparece |
|---|---|
| Trofeo | Claude terminó una tarea de al menos 30 s; muestra cuánto tardó ("Claude terminó en 4m 12s") |
| Candado | Claude espera un permiso (sale unos 6 s después del pedido) |
| Signo de pregunta | Claude muestra un cuadro de opciones |
| Calavera (en rojo) | Claude se cortó por un error de la API: límite de uso, API saturada, error del servidor, etc. |

Aparece en el monitor donde está el puntero, se va sola a los pocos segundos y se cierra antes con un clic.

Elegí la carpeta según tu sistema operativo:

| Sistema | Carpeta | Estado |
|---|---|---|
| Linux | [`linux/`](linux/) | Probado en Fedora 42 con KDE sobre X11. En Wayland no está probado. |
| Windows 10/11 | [`windows/`](windows/) | **Sin probar en un Windows real**: se validó la sintaxis, el instalador y la lógica de los avisos, pero no el dibujo en pantalla. Si algo falla, abrí un issue. |

## Linux

Requisitos: escritorio gráfico, `python3` con GTK 3 (`python3-gobject`, `python3-cairo`) y `jq`. Opcional, para el sonido: `paplay` y los sonidos "ocean" de KDE Plasma; si no están, el aviso sale mudo.

```bash
git clone https://github.com/maurolando/claude-code-logro.git
cd claude-code-logro
./linux/instalar.sh
```

El instalador copia `logro-claude.py` a `~/.claude/hooks/` y la fuente Press Start 2P a `~/.local/share/fonts/`.

## Windows

Requisitos: ninguno aparte de Windows PowerShell, que ya viene con el sistema. El sonido usa los `.wav` de `C:\Windows\Media`.

```powershell
git clone https://github.com/maurolando/claude-code-logro.git
cd claude-code-logro
powershell -ExecutionPolicy Bypass -File .\windows\instalar.ps1
```

El instalador copia `logro-claude.ps1` y la fuente a `%USERPROFILE%\.claude\hooks\` (la fuente se carga desde ahí, no se instala en el sistema).

## En los dos sistemas

El instalador agrega seis hooks a `~/.claude/settings.json` sin tocar el resto y deja una copia en `settings.json.antes-de-logro`. Se puede correr más de una vez sin duplicar nada. Después hay que reiniciar Claude Code o abrir `/hooks` una vez.

## Personalizar

Cada uno cambia lo suyo en `~/.claude/logro.json` (`%USERPROFILE%\.claude\logro.json` en Windows). Ese archivo no se pisa al actualizar: el instalador solo lo crea si no existe. Todo es opcional; lo que falte o tenga un tipo inválido queda con el valor de fábrica, y si el archivo no es JSON válido se ignora entero.

| Clave | Qué hace |
|---|---|
| `minimo_s` | Desde cuántos segundos de tarea sale el trofeo. `0` para avisar siempre. De fábrica, `30`. |
| `sonido` | `false` silencia todos los avisos. |
| `no_molestar` | `{"desde": "22:00", "hasta": "08:00"}`: en ese horario no sale ningún aviso. Puede cruzar la medianoche. `null` lo apaga. |
| `color_titulo`, `color_detalle` | Color de las dos líneas de texto, en `#rrggbb`. |
| `avisos` | Cambios por aviso: `terminado`, `permiso`, `pregunta` o `error`. |

Dentro de cada aviso:

| Clave | Qué hace |
|---|---|
| `activo` | `false` lo apaga. |
| `titulo`, `detalle` | Las dos líneas de texto. Al detalle se le suma la duración y la carpeta. |
| `visible_ms` | Cuánto queda en pantalla, en milisegundos. |
| `sonido` | Nombre del archivo de sonido o ruta completa. `""` lo silencia. En Linux se busca en `/usr/share/sounds/ocean/stereo/` (`.oga`); en Windows, en `C:\Windows\Media` (`.wav`). |
| `colores` | Cuatro colores: fondo, canto claro, canto oscuro y borde. |

[`ejemplo-logro.json`](ejemplo-logro.json) tiene todas las claves, con los sonidos de Linux.

Los íconos (las grillas de 16×16 `TROFEO`, `CANDADO`, `PREGUNTA` y `CALAVERA`) se cambian en el script; eso sí se pisa al actualizar.

## Desinstalar

Borrar los hooks desde `/hooks` en Claude Code (o restaurar la copia de `settings.json`) y borrar el script de `~/.claude/hooks/`.

## Fuente

Incluye la fuente [Press Start 2P](https://fonts.google.com/specimen/Press+Start+2P), bajo la SIL Open Font License (ver `fuente/OFL-PressStart2P.txt`).

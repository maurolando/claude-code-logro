# claude-code-logro

Avisos tipo "logro" de videojuego para [Claude Code](https://claude.com/claude-code): una pastilla verde en pixel art que aparece arriba al centro de la pantalla.

| Ícono | Cuándo aparece |
|---|---|
| Trofeo | Claude terminó de responder |
| Candado | Claude espera un permiso (sale unos 6 s después del pedido) |
| Signo de pregunta | Claude muestra un cuadro de opciones |

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

El instalador agrega cuatro hooks a `~/.claude/settings.json` sin tocar el resto y deja una copia en `settings.json.antes-de-logro`. Se puede correr más de una vez sin duplicar nada. Después hay que reiniciar Claude Code o abrir `/hooks` una vez.

## Personalizar

En `~/.claude/hooks/logro-claude.py` (Linux) o `logro-claude.ps1` (Windows):

- Textos, duración y sonido de cada aviso: bloque `AVISOS` (`$Avisos` en Windows).
- Colores: constantes `VERDE`, `VERDE_CLARO`, `VERDE_OSCURO`, `BORDE`, `COLOR_TITULO`.
- Íconos: las grillas de 16×16 `TROFEO`, `CANDADO` y `PREGUNTA`.

## Desinstalar

Borrar los hooks desde `/hooks` en Claude Code (o restaurar la copia de `settings.json`) y borrar el script de `~/.claude/hooks/`.

## Fuente

Incluye la fuente [Press Start 2P](https://fonts.google.com/specimen/Press+Start+2P), bajo la SIL Open Font License (ver `fuente/OFL-PressStart2P.txt`).

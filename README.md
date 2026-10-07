# claude-code-logro

Avisos tipo "logro" de videojuego para [Claude Code](https://claude.com/claude-code): una pastilla verde en pixel art que aparece arriba al centro de la pantalla.

| Ícono | Cuándo aparece |
|---|---|
| Trofeo | Claude terminó de responder |
| Candado | Claude espera un permiso (sale unos 6 s después del pedido) |
| Signo de pregunta | Claude muestra un cuadro de opciones |

Aparece en el monitor donde está el puntero, se va sola a los pocos segundos y se cierra antes con un clic.

## Requisitos

- Linux con escritorio gráfico.
- `python3` con GTK 3 (`python3-gobject`, `python3-cairo`) y `jq`.
- Opcional, para el sonido: `paplay` y los sonidos "ocean" de KDE Plasma. Si no están, el aviso sale mudo.

Probado en Fedora 42 con KDE sobre X11. En Wayland no está probado.

## Instalar

```bash
git clone https://github.com/maurolando/claude-code-logro.git
cd claude-code-logro
./instalar.sh
```

El instalador copia `logro-claude.py` a `~/.claude/hooks/`, la fuente Press Start 2P a `~/.local/share/fonts/` y agrega cuatro hooks a `~/.claude/settings.json` sin tocar el resto (deja una copia en `settings.json.antes-de-logro`). Se puede correr más de una vez sin duplicar nada. Después hay que reiniciar Claude Code o abrir `/hooks` una vez.

## Personalizar

En `~/.claude/hooks/logro-claude.py`:

- Textos, duración y sonido de cada aviso: bloque `AVISOS`.
- Colores: constantes `VERDE`, `VERDE_CLARO`, `VERDE_OSCURO`, `BORDE`, `COLOR_TITULO`.
- Íconos: las grillas de 16×16 `TROFEO`, `CANDADO` y `PREGUNTA`.

## Desinstalar

Borrar los hooks desde `/hooks` en Claude Code (o restaurar la copia de `settings.json`) y borrar `~/.claude/hooks/logro-claude.py`.

## Fuente

Incluye la fuente [Press Start 2P](https://fonts.google.com/specimen/Press+Start+2P), bajo la SIL Open Font License (ver `OFL-PressStart2P.txt`).

#!/usr/bin/env bash
# Instala los avisos tipo "logro" de Claude Code para el usuario actual.
set -euo pipefail
aqui="$(cd "$(dirname "$0")" && pwd)"
ajustes="$HOME/.claude/settings.json"

faltan=()
command -v jq >/dev/null || faltan+=("jq")
python3 -c 'import gi, cairo; gi.require_version("Gtk", "3.0"); gi.require_version("PangoCairo", "1.0")' 2>/dev/null \
  || faltan+=("python3-gobject, python3-cairo y gtk3")
if [ ${#faltan[@]} -gt 0 ]; then
  echo "Falta instalar: ${faltan[*]}" >&2
  echo "  Fedora:        sudo dnf install jq python3-gobject python3-cairo gtk3" >&2
  echo "  Debian/Ubuntu: sudo apt install jq python3-gi python3-gi-cairo gir1.2-gtk-3.0" >&2
  exit 1
fi

mkdir -p "$HOME/.claude/hooks" "$HOME/.local/share/fonts"
install -m 755 "$aqui/logro-claude.py" "$HOME/.claude/hooks/logro-claude.py"
install -m 644 "$aqui/../fuente/PressStart2P-Regular.ttf" "$HOME/.local/share/fonts/"
fc-cache -f "$HOME/.local/share/fonts" 2>/dev/null || true

[ -f "$ajustes" ] || echo '{}' > "$ajustes"
cp "$ajustes" "$ajustes.antes-de-logro"
# agrega los hooks sin tocar los que ya haya; si ya estaban instalados no los duplica
jq --slurpfile nuevo "$aqui/hooks.json" '
  .hooks = (reduce ($nuevo[0].hooks | to_entries[]) as $e (.hooks // {};
    .[$e.key] = ((.[$e.key] // [])
      | map(select(any(.hooks[]?; (.command // "") | contains("logro-claude.py")) | not))) + $e.value))
' "$ajustes.antes-de-logro" > "$ajustes"

echo "Instalado. Copia de la configuración anterior: $ajustes.antes-de-logro"
echo "Reiniciá Claude Code (o abrí /hooks una vez) para que tome los hooks."
echo '{"cwd":"'"$PWD"'"}' | "$HOME/.claude/hooks/logro-claude.py" || true

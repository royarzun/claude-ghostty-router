#!/usr/bin/env bash
# Instalacion de claude-ghostty-router. Idempotente y reversible.
set -eu

CAR_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
CONF_DIR="$HOME/.config/claude-ghostty-router"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
GHOSTTY_CONF="${CAR_GHOSTTY_CONF:-$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty}"
MARCA="# claude-ghostty-router"
LINEA_ZSHRC="[ -f \"$CAR_SRC/shell/router.zsh\" ] && source \"$CAR_SRC/shell/router.zsh\"  $MARCA"
# Ruta absoluta a proposito: Claude Code puede arrancar con un PATH que no
# incluya ~/.local/bin, y un statusLine que no se puede ejecutar no se ve.
STATUSLINE_CMD="$BIN_DIR/claude-account statusline"

ASUMIR_SI=0
MODO=install
for arg in "$@"; do
  case "$arg" in
    --yes|-y)    ASUMIR_SI=1 ;;
    --uninstall) MODO=uninstall ;;
    *) echo "uso: install.sh [--yes] [--uninstall]" >&2; exit 1 ;;
  esac
done

confirmar() {
  [ "$ASUMIR_SI" -eq 1 ] && return 0
  printf '%s [s/N] ' "$1"
  read -r respuesta
  case "$respuesta" in s|S|si|SI) return 0 ;; *) return 1 ;; esac
}

# badge_por_perfil --install | --uninstall
# El badge vive en el settings.json de cada perfil, porque CLAUDE_CONFIG_DIR es
# justo lo que mueve el settings.json de nivel usuario a la carpeta del perfil.
# Se usa el CLI del repo y no el enlace: al desinstalar, el enlace ya no esta.
badge_por_perfil() {
  local accion="$1" dir settings rc
  local cli="$CAR_SRC/bin/claude-account"

  if ! "$cli" _config-dirs >/dev/null 2>&1; then
    echo "!!  no puedo leer los perfiles de $CONF_DIR/routes.conf: me salto el badge"
    return 0
  fi

  if [ "$accion" = "--install" ] && ! confirmar "Instalar el badge de cuenta en el settings.json de cada perfil?"; then
    return 0
  fi

  "$cli" _config-dirs | while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    settings="$dir/settings.json"
    [ "$accion" = "--install" ] && mkdir -p "$dir"
    [ -d "$dir" ] || continue

    rc=0
    if [ "$accion" = "--install" ]; then
      python3 "$CAR_SRC/lib/settings.py" "$settings" --install "$STATUSLINE_CMD" || rc=$?
    else
      python3 "$CAR_SRC/lib/settings.py" "$settings" --uninstall || rc=$?
    fi

    case "$rc" in
      0) echo "ok  statusLine $([ "$accion" = "--install" ] && echo agregado a || echo quitado de) $settings" ;;
      2) echo "ok  $settings ya estaba como toca" ;;
      3) echo "!!  $settings tiene otro statusLine: no lo toco" ;;
      *) echo "!!  no pude tocar $settings (JSON invalido o sin permisos)" ;;
    esac
  done
}

instalar() {
  mkdir -p "$BIN_DIR" "$CONF_DIR"

  # El destino puede ser: nuestro propio enlace (reinstalacion, se reemplaza),
  # o algo ajeno que no nos toca destruir. La config de Ghostty se respalda
  # antes de tocarla; un binario del usuario merece el mismo cuidado.
  if [ -e "$BIN_DIR/claude-account" ] && [ ! -L "$BIN_DIR/claude-account" ]; then
    echo "claude-account: ya hay un archivo (no un enlace) en $BIN_DIR/claude-account." >&2
    echo "  No lo toco. Muevelo o borralo y vuelve a ejecutar el instalador." >&2
    exit 1
  fi

  ln -sf "$CAR_SRC/bin/claude-account" "$BIN_DIR/claude-account"
  echo "ok  enlace en $BIN_DIR/claude-account"

  if [ -f "$CONF_DIR/routes.conf" ]; then
    echo "ok  $CONF_DIR/routes.conf ya existe (no se toca)"
  else
    cp "$CAR_SRC/routes.conf.example" "$CONF_DIR/routes.conf"
    echo "ok  creado $CONF_DIR/routes.conf — editalo con tus cuentas y rutas"
  fi

  if [ -f "$ZSHRC" ] && grep -qF "$MARCA" "$ZSHRC"; then
    echo "ok  ~/.zshrc ya carga el router"
  elif confirmar "Agregar una linea a $ZSHRC para cargar el router?"; then
    printf '\n%s\n' "$LINEA_ZSHRC" >> "$ZSHRC"
    echo "ok  linea agregada a $ZSHRC"
  fi

  badge_por_perfil --install

  # Versiones anteriores ponian no-title aqui, para sostener un titulo de tab
  # que el router ya no escribe. Mientras esa linea siga puesta, Ghostty no
  # muestra el comando en curso: se ofrece revertirla, igual que se ofrecio
  # ponerla.
  if [ -f "$GHOSTTY_CONF" ] && grep -qF "$MARCA" "$GHOSTTY_CONF"; then
    if confirmar "Quitar el no-title que dejo una version anterior en la config de Ghostty?"; then
      cp "$GHOSTTY_CONF" "$GHOSTTY_CONF.bak"
      grep -vF "$MARCA" "$GHOSTTY_CONF" > "$GHOSTTY_CONF.tmp" || true
      mv "$GHOSTTY_CONF.tmp" "$GHOSTTY_CONF"
      echo "ok  no-title revertido (backup en $GHOSTTY_CONF.bak); recarga Ghostty para verlo"
    fi
  fi

  echo
  echo "Falta un paso manual: edita $CONF_DIR/routes.conf y corre"
  echo "'claude-account login <perfil>' para cada cuenta. Si anades un perfil"
  echo "despues, vuelve a correr ./install.sh para darle su badge."
  echo
  # El diagnostico se ejecuta siempre: recien instalado va a fallar (todavia no
  # hay sesiones), y eso es exactamente lo que hay que ver.
  "$BIN_DIR/claude-account" check || true
}

desinstalar() {
  badge_por_perfil --uninstall

  rm -f "$BIN_DIR/claude-account"
  echo "ok  enlace eliminado"

  # `grep -v` devuelve 1 si no queda ninguna linea, y con `set -e` eso abortaria
  # el script justo cuando el archivo se queda vacio: por eso el `|| true`.
  if [ -f "$ZSHRC" ] && grep -qF "$MARCA" "$ZSHRC"; then
    grep -vF "$MARCA" "$ZSHRC" > "$ZSHRC.tmp" || true
    mv "$ZSHRC.tmp" "$ZSHRC"
    echo "ok  linea eliminada de $ZSHRC"
  fi

  if [ -f "$GHOSTTY_CONF" ] && grep -qF "$MARCA" "$GHOSTTY_CONF"; then
    grep -vF "$MARCA" "$GHOSTTY_CONF" > "$GHOSTTY_CONF.tmp" || true
    mv "$GHOSTTY_CONF.tmp" "$GHOSTTY_CONF"
    echo "ok  no-title revertido en la config de Ghostty"
  fi

  echo "ok  $CONF_DIR/routes.conf se conserva: es tuyo"
}

case "$MODO" in
  install)   instalar ;;
  uninstall) desinstalar ;;
esac

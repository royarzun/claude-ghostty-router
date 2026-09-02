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
FEATURES="shell-integration-features = cursor,no-sudo,no-title,no-ssh-env,no-ssh-terminfo,path"

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

instalar() {
  mkdir -p "$BIN_DIR" "$CONF_DIR"

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

  if [ -f "$GHOSTTY_CONF" ] && grep -q 'no-title' "$GHOSTTY_CONF"; then
    echo "ok  Ghostty ya tiene no-title"
  elif confirmar "Poner no-title en la config de Ghostty (con backup)?"; then
    [ -f "$GHOSTTY_CONF" ] && cp "$GHOSTTY_CONF" "$GHOSTTY_CONF.bak"
    printf '\n%s  %s\n' "$FEATURES" "$MARCA" >> "$GHOSTTY_CONF"
    echo "ok  no-title agregado (backup en $GHOSTTY_CONF.bak)"
  fi

  echo
  echo "Falta un paso manual: edita $CONF_DIR/routes.conf y corre"
  echo "'claude-account login <perfil>' para cada cuenta."
  echo
  # El diagnostico se ejecuta siempre: recien instalado va a fallar (todavia no
  # hay sesiones), y eso es exactamente lo que hay que ver.
  "$BIN_DIR/claude-account" check || true
}

desinstalar() {
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

# claude-ghostty-router — integracion de sesion zsh.
# Se auto-desactiva fuera de Ghostty y si el CLI no esta instalado.

[[ $TERM == xterm-ghostty ]] || return 0
(( $+commands[claude-account] )) || return 0

# La lee `claude-account check` para saber si el router esta cargado en esta
# shell. Se exporta para que tambien se vea desde los procesos que arranque.
typeset -g CAR_ROUTER_LOADED=1
export CAR_ROUTER_LOADED

# Sustituye a `claude` solo en sesiones de Ghostty. Toda la autoridad para negar
# el arranque vive aqui: si _launch-check falla, no se ejecuta nada.
#
# El router no pinta nada: la cuenta se ve dentro de la sesion, en el badge que
# Claude Code renderiza desde el statusLine de cada perfil.
claude() {
  local config_dir
  config_dir=$(claude-account _launch-check "$PWD") || return $?

  if [[ -n $config_dir ]]; then
    CLAUDE_CONFIG_DIR=$config_dir command claude "$@"
  else
    command claude "$@"
  fi
}

# claude-ghostty-router — integracion de sesion zsh.
# Se auto-desactiva fuera de Ghostty y si el CLI no esta instalado.

[[ $TERM == xterm-ghostty ]] || return 0
(( $+commands[claude-account] )) || return 0

zmodload -F zsh/stat b:zstat 2>/dev/null
autoload -Uz add-zsh-hook

typeset -g CAR_ROUTER_LOADED=1
export CAR_ROUTER_LOADED

# oh-my-zsh reescribe el titulo en cada precmd via termsupport. Consulta esta
# variable en tiempo de ejecucion, asi que basta con ponerla aqui: funciona sin
# importar si el router se carga antes o despues de oh-my-zsh, y solo afecta a
# las sesiones de Ghostty porque mas arriba ya volvimos si el TERM es otro.
typeset -g DISABLE_AUTO_TITLE=true
export DISABLE_AUTO_TITLE

typeset -gA _car_cache
typeset -g _car_conf=${CAR_CONF:-$HOME/.config/claude-ghostty-router/routes.conf}
typeset -g _car_conf_mtime=

# Vacia la cache si routes.conf cambio. zstat es un builtin: no crea procesos.
_car_check_conf() {
  local -a stamp
  zstat -A stamp +mtime -- $_car_conf 2>/dev/null
  local now=${stamp[1]:-0}
  if [[ $now != $_car_conf_mtime ]]; then
    _car_conf_mtime=$now
    _car_cache=()
  fi
}

# Pinta la superficie actual. Con la cache caliente son ~40 bytes y cero forks,
# por eso puede correr en cada prompt.
_car_paint() {
  _car_check_conf
  local esc=${_car_cache[$PWD]-}
  if [[ -z $esc ]]; then
    esc=$(claude-account _surface "$PWD" 2>/dev/null)
    _car_cache[$PWD]=$esc
  fi
  [[ -n $esc ]] && print -rn -- $esc
}

_car_cleanup() {
  print -rn -- $'\e]111\a'
}

# Sustituye a `claude` solo en sesiones de Ghostty. Toda la autoridad para negar
# el arranque vive aqui: si _launch-check falla, no se ejecuta nada.
claude() {
  local config_dir rc
  config_dir=$(claude-account _launch-check "$PWD") || return $?

  if [[ -n $config_dir ]]; then
    CLAUDE_CONFIG_DIR=$config_dir command claude "$@"
  else
    command claude "$@"
  fi
  rc=$?

  # Claude Code toca el titulo mientras corre: hay que devolverlo a su sitio.
  _car_paint
  return $rc
}

add-zsh-hook precmd _car_paint
add-zsh-hook zshexit _car_cleanup

_car_paint

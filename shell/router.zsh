# claude-ghostty-router — integracion de sesion zsh.
# Se auto-desactiva fuera de Ghostty y si el CLI no esta instalado.

[[ $TERM == xterm-ghostty ]] || return 0
(( $+commands[claude-account] )) || return 0

autoload -Uz add-zsh-hook

# La lee `claude-account check` para saber si el router esta cargado en esta
# shell. Se exporta para que tambien se vea desde los procesos que arranque.
typeset -g CAR_ROUTER_LOADED=1
export CAR_ROUTER_LOADED

# 1 mientras el fondo esta tenido. El bloque `always` de claude() la vacia al
# despintar, asi que si al cerrar la shell sigue puesta es que ese bloque nunca
# llego a correr.
typeset -g _car_tinted=

# Red de seguridad para el camino que el bloque `always` no cubre en esta
# shell: suspender la sesion con Ctrl-Z y cerrar el tab sin volver a ella. No
# alcanza a una subshell —`(claude)` o `claude &`— porque ahi el tenido toca
# una copia privada de esta variable y nunca vuelve; eso queda sin red.
# El guardia no es un detalle de eficiencia: sin el, cada shell de Ghostty
# escupiria un reset al salir aunque nunca hubiera corrido Claude.
_car_cleanup() {
  [[ -n $_car_tinted ]] || return 0
  claude-account _untint 2>/dev/null
}

# Sustituye a `claude` solo en sesiones de Ghostty. Toda la autoridad para negar
# el arranque vive aqui: si _launch-check falla, no se ejecuta nada.
#
# El titulo del tab no se toca: en el prompt es de Ghostty y durante la sesion
# es de Claude Code. La cuenta se ve en el badge, dentro de la sesion; el fondo
# tenido dice, desde fuera, que hay una sesion corriendo y de que perfil es.
claude() {
  local config_dir tint rc=0

  config_dir=$(claude-account _launch-check "$PWD") || return $?

  # Se tine despues de la verificacion: un arranque bloqueado no deja rastro.
  # Salida vacia = perfil sin fondo, y entonces tampoco hay que despintar.
  tint=$(claude-account _tint "$PWD" 2>/dev/null)

  {
    if [[ -n $tint ]]; then
      print -rn -- "$tint"
      _car_tinted=1
    fi

    if [[ -n $config_dir ]]; then
      CLAUDE_CONFIG_DIR=$config_dir command claude "$@"
    else
      command claude "$@"
    fi
    rc=$?
  } always {
    # `always` y no la linea siguiente: verificado con un zsh interactivo real,
    # si Claude muere por Ctrl-C zsh aborta el resto de la funcion y sin este
    # bloque el fondo se queda tenido hasta que se cierre el tab.
    if [[ -n $_car_tinted ]]; then
      claude-account _untint
      _car_tinted=
    fi
  }

  # zsh ya propaga el estado del try-list por su cuenta, pero se devuelve
  # explicito: asi el contrato no depende de esa sutileza ni de que nadie
  # anada una linea despues del bloque. En el camino del Ctrl-C no se llega
  # aqui, y de ahi el rc=0 de arriba.
  return $rc
}

add-zsh-hook zshexit _car_cleanup

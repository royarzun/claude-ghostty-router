setup() {
  load helper
  setup_fixture
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #8fbc5a" \
    "route ~/repos/miapp work"
  mkdir -p "$HOME/repos/miapp"
  export PATH="$CAR_ROOT/bin:$PATH"
}

# Corre un fragmento de zsh con el router cargado y TERM de Ghostty.
# Se limpian las variables que el propio router exporta: si estos tests corren
# desde una shell que ya lo tiene cargado, heredarlas los haria pasar (o fallar)
# por el entorno de quien los lanza y no por el codigo.
run_zsh() {
  run env -u CAR_ROUTER_LOADED -u DISABLE_AUTO_TITLE TERM=xterm-ghostty zsh -f -c "
    export CAR_CONF='$CAR_CONF'
    export PATH='$PATH'
    source '$CAR_ROOT/shell/router.zsh'
    $1
  "
}

@test "fuera de Ghostty el router no se activa" {
  run env -u CAR_ROUTER_LOADED -u DISABLE_AUTO_TITLE TERM=xterm-256color zsh -f -c "
    export CAR_CONF='$CAR_CONF'
    source '$CAR_ROOT/shell/router.zsh'
    print -r -- \"loaded=\${CAR_ROUTER_LOADED:-no}\"
  "
  [ "$output" = "loaded=no" ]
}

@test "dentro de Ghostty marca la sesion como cargada" {
  run_zsh "print -r -- \"loaded=\$CAR_ROUTER_LOADED\""
  [[ "$output" == *"loaded=1"* ]]
}

@test "cargar el router no escribe nada en la terminal" {
  # El router dejo de pintar: la cuenta se ve dentro de Claude, en el badge.
  # Un solo byte de escape aqui volveria a pisarle el tab al usuario.
  run_zsh "cd '$HOME/repos/miapp'"
  [ -z "$output" ]
}

@test "no toca el titulo automatico de oh-my-zsh" {
  # DISABLE_AUTO_TITLE existia para defender un titulo que ya no escribimos.
  run_zsh "print -r -- \"omz=\${DISABLE_AUTO_TITLE:-sin-tocar}\""
  [[ "$output" == *"omz=sin-tocar"* ]]
}

@test "el hook de salida despinta si una sesion quedo suspendida" {
  # El bloque always de claude() cubre la salida normal. Este hook cubre el
  # unico camino que no: suspender Claude con Ctrl-Z y cerrar el tab sin
  # volver a la sesion. Se simula dejando puesta la marca que ese bloque
  # habria vaciado.
  run_zsh "_car_tinted=1"
  [ "$output" = "$(printf '\033]111\007')" ]
}

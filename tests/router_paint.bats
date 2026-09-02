setup() {
  load helper
  setup_fixture
  write_conf \
    "profile personal ~/.claude royarzun@gmail.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/miapp work"
  mkdir -p "$HOME/repos/miapp" "$HOME/notas"
  export PATH="$CAR_ROOT/bin:$PATH"
}

# Corre un fragmento de zsh con el router cargado y TERM de Ghostty.
run_zsh() {
  TERM=xterm-ghostty run zsh -f -c "
    export CAR_CONF='$CAR_CONF'
    export PATH='$PATH'
    source '$CAR_ROOT/shell/router.zsh'
    $1
  "
}

@test "fuera de Ghostty el router no se activa" {
  TERM=xterm-256color run zsh -f -c "
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

@test "desactiva el auto-titulo de oh-my-zsh" {
  run_zsh "print -r -- \"omz=\$DISABLE_AUTO_TITLE\""
  [[ "$output" == *"omz=true"* ]]
}

@test "pinta el perfil del directorio actual" {
  run_zsh "cd '$HOME/repos/miapp'; _car_paint"
  [[ "$output" == *"$(printf '\033]2;work · miapp\007')"* ]]
}

@test "la segunda pintada del mismo directorio usa la cache" {
  # El source ya pinto el directorio de partida: se limpia la cache para contar
  # solo lo que cachea esta prueba.
  run_zsh "
    _car_cache=()
    cd '$HOME/repos/miapp'
    _car_paint >/dev/null
    _car_paint >/dev/null
    print -r -- \"cacheados=\${#_car_cache}\"
  "
  [[ "$output" == *"cacheados=1"* ]]
}

@test "cambiar routes.conf invalida la cache" {
  run_zsh "
    cd '$HOME/repos/miapp'
    _car_paint >/dev/null
    sleep 1
    print -r -- 'profile personal ~/.claude royarzun@gmail.com -' > '$CAR_CONF'
    _car_paint
  "
  [[ "$output" == *"personal · miapp"* ]]
}

@test "el hook de salida resetea el fondo" {
  # Se pinta un directorio teñido y se comprueba que el reset va justo despues.
  run_zsh "cd '$HOME/repos/miapp'; _car_paint; _car_cleanup"
  [[ "$output" == *"$(printf '\033]11;#171b12\007\033]111\007')" ]]
}

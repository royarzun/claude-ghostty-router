setup() {
  load helper
  setup_fixture
  CA="$CAR_ROOT/bin/claude-account"
}

@test "pinta titulo y color del perfil resuelto" {
  write_conf \
    "profile personal ~/.claude royarzun@gmail.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/miapp work"
  mkdir -p "$HOME/repos/miapp"
  run "$CA" _surface "$HOME/repos/miapp"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]2;work · miapp\007\033]11;#171b12\007')" ]
}

@test "el perfil por defecto resetea el fondo" {
  write_conf "profile personal ~/.claude royarzun@gmail.com -"
  mkdir -p "$HOME/notas"
  run "$CA" _surface "$HOME/notas"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]2;personal · notas\007\033]111\007')" ]
}

@test "funciona invocado a traves de un symlink" {
  # Asi es como se instala: ~/.local/bin/claude-account -> repo/bin/claude-account.
  # Si el CLI no resuelve el symlink, no encuentra sus propias librerias.
  write_conf "profile personal ~/.claude royarzun@gmail.com -"
  mkdir -p "$HOME/.local/bin" "$HOME/notas"
  ln -sf "$CA" "$HOME/.local/bin/claude-account"
  run "$HOME/.local/bin/claude-account" _surface "$HOME/notas"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]2;personal · notas\007\033]111\007')" ]
}

@test "sin routes.conf no pinta nada y sale con exito" {
  rm -f "$CAR_CONF"
  run "$CA" _surface "$HOME"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "con routes.conf roto avisa en el titulo pero no falla" {
  write_conf "basura aqui"
  run "$CA" _surface "$HOME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"routes.conf invalido"* ]]
  [[ "$output" == *"$(printf '\033]111\007')" ]]
}

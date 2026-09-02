setup() {
  load helper
  setup_fixture
  CA="$CAR_ROOT/bin/claude-account"
}

@test "tint emite el fondo del perfil resuelto" {
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com - -" \
    "profile work ~/.claude-work *@empresa.com #8fbc5a #171b12" \
    "route ~/repos/miapp work"
  mkdir -p "$HOME/repos/miapp"
  run "$CA" _tint "$HOME/repos/miapp"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]11;#171b12\007')" ]
}

@test "tint usa el fondo, no el color del badge" {
  # Los dos campos existen justo porque un tono legible como badge es inusable
  # como fondo. Confundirlos aqui cegaria el tab.
  write_conf \
    "profile work ~/.claude-work *@empresa.com #8fbc5a #171b12" \
    "route ~/repos/miapp work"
  mkdir -p "$HOME/repos/miapp"
  run "$CA" _tint "$HOME/repos/miapp"
  [[ "$output" != *"8fbc5a"* ]]
}

@test "un perfil sin fondo no emite nada" {
  # Salida vacia es como router.zsh sabe que no hay que despintar al salir.
  write_conf "profile personal ~/.claude tu-email@ejemplo.com #8fbc5a"
  mkdir -p "$HOME/notas"
  run "$CA" _tint "$HOME/notas"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "sin routes.conf no emite nada y sale con exito" {
  rm -f "$CAR_CONF"
  run "$CA" _tint "$HOME"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "con routes.conf roto no emite nada y sale con exito" {
  # El pintado informa, no decide: del error avisa _launch-check al bloquear
  # el arranque, con archivo y linea por stderr.
  write_conf "basura aqui"
  run "$CA" _tint "$HOME"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "tint funciona invocado a traves de un symlink" {
  # Asi es como se instala: ~/.local/bin/claude-account -> repo/bin/claude-account.
  write_conf \
    "profile work ~/.claude-work *@empresa.com #8fbc5a #171b12" \
    "route ~/repos/miapp work"
  mkdir -p "$HOME/.local/bin" "$HOME/repos/miapp"
  ln -sf "$CA" "$HOME/.local/bin/claude-account"
  run "$HOME/.local/bin/claude-account" _tint "$HOME/repos/miapp"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]11;#171b12\007')" ]
}

@test "untint emite el reset al tema" {
  run "$CA" _untint
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]111\007')" ]
}

@test "untint no necesita routes.conf" {
  # Corre al salir de Claude y en el hook zshexit: tiene que funcionar aunque
  # la config haya desaparecido o se haya roto mientras corria la sesion.
  rm -f "$CAR_CONF"
  run "$CA" _untint
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]111\007')" ]
}

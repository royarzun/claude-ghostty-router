setup() {
  load helper
  setup_fixture
  CA="$CAR_ROOT/bin/claude-account"
  write_conf \
    "profile personal ~/.claude royarzun@gmail.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/miapp work"
  mkdir -p "$HOME/repos/miapp" "$HOME/notas"
}

@test "cuenta correcta: imprime el config-dir y sale con 0" {
  make_profile ".claude-work" "ricardo@empresa.com"
  run "$CA" _launch-check "$HOME/repos/miapp"
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.claude-work" ]
}

@test "cuenta equivocada: bloquea con 5 y dice como arreglarlo" {
  make_profile ".claude-work" "royarzun@gmail.com"
  run "$CA" _launch-check "$HOME/repos/miapp"
  [ "$status" -eq 5 ]
  [[ "$output" == *"*@empresa.com"* ]]
  [[ "$output" == *"royarzun@gmail.com"* ]]
  [[ "$output" == *"claude-account login work"* ]]
}

@test "perfil sin sesion: bloquea con 3" {
  make_profile ".claude-work"
  run "$CA" _launch-check "$HOME/repos/miapp"
  [ "$status" -eq 3 ]
  [[ "$output" == *"claude-account login work"* ]]
}

@test "config-dir inexistente: bloquea con 6" {
  run "$CA" _launch-check "$HOME/repos/miapp"
  [ "$status" -eq 6 ]
  [[ "$output" == *"no existe"* ]]
}

@test "routes.conf roto: bloquea con 2 y señala la linea" {
  write_conf "profile personal ~/.claude" "basura aqui"
  run "$CA" _launch-check "$HOME/repos/miapp"
  [ "$status" -eq 2 ]
  [[ "$output" == *"linea 2"* ]]
}

@test "sin routes.conf: paso directo, sin config-dir y sin error" {
  rm -f "$CAR_CONF"
  run "$CA" _launch-check "$HOME/repos/miapp"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "perfil sin glob de email: no verifica y devuelve su config-dir" {
  write_conf "profile personal ~/.claude - -" "route ~/notas personal"
  make_profile ".claude"
  run "$CA" _launch-check "$HOME/notas"
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.claude" ]
}

@test "el perfil por defecto tambien se verifica" {
  make_profile ".claude" "otro@gmail.com"
  run "$CA" _launch-check "$HOME/notas"
  [ "$status" -eq 5 ]
  [[ "$output" == *"claude-account login personal"* ]]
}

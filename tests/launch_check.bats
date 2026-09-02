setup() {
  load helper
  setup_fixture
  CA="$CAR_ROOT/bin/claude-account"
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
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
  make_profile ".claude-work" "tu-email@ejemplo.com"
  run "$CA" _launch-check "$HOME/repos/miapp"
  [ "$status" -eq 5 ]
  [[ "$output" == *"*@empresa.com"* ]]
  [[ "$output" == *"tu-email@ejemplo.com"* ]]
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
  write_conf "profile personal ~/.claude-other - -" "route ~/notas personal"
  make_profile ".claude-other"
  run "$CA" _launch-check "$HOME/notas"
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.claude-other" ]
}

@test "el perfil por defecto tambien se verifica" {
  make_profile ".claude" "otro@gmail.com"
  run "$CA" _launch-check "$HOME/notas"
  [ "$status" -eq 5 ]
  [[ "$output" == *"claude-account login personal"* ]]
}

@test "el perfil por defecto de Claude no fuerza CLAUDE_CONFIG_DIR" {
  # Con CLAUDE_CONFIG_DIR puesto, Claude Code busca <dir>/.claude.json; sin la
  # variable usa el hermano ~/.claude.json. Forzarla para el directorio por
  # defecto le esconderia su propia configuracion al usuario.
  write_conf "profile personal ~/.claude tu-email@ejemplo.com -" "route ~/notas personal"
  make_profile ".claude" "tu-email@ejemplo.com"
  run "$CA" _launch-check "$HOME/notas"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "un perfil que no es el por defecto si define CLAUDE_CONFIG_DIR" {
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/miapp work"
  make_profile ".claude-work" "ricardo@empresa.com"
  run "$CA" _launch-check "$HOME/repos/miapp"
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.claude-work" ]
}

@test "el perfil por defecto se sigue verificando aunque no exporte la variable" {
  write_conf "profile personal ~/.claude tu-email@ejemplo.com -" "route ~/notas personal"
  make_profile ".claude" "otro@gmail.com"
  run "$CA" _launch-check "$HOME/notas"
  [ "$status" -eq 5 ]
  [[ "$output" == *"cuenta equivocada"* ]]
}

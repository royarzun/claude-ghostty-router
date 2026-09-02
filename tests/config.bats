setup() {
  load helper
  setup_fixture
  source "$CAR_ROOT/lib/config.sh"
}

@test "parsea un perfil completo y expande ~" {
  write_conf "profile work ~/.claude-work *@empresa.com #171b12"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'profile\twork\t%s/.claude-work\t*@empresa.com\t#171b12' "$HOME")" ]
}

@test "los campos opcionales quedan en guion" {
  write_conf "profile personal ~/.claude"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'profile\tpersonal\t%s/.claude\t-\t-' "$HOME")" ]
}

@test "ignora comentarios de linea completa, lineas vacias y espacios sobrantes" {
  write_conf "# comentario" "" "   # comentario indentado" "   profile personal ~/.claude   " "  "
  run config_parse "$CAR_CONF"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'profile\tpersonal\t%s/.claude\t-\t-' "$HOME")" ]
}

@test "un # a media linea es parte del campo, no un comentario" {
  # Sin esto, el color #171b12 se perderia al recortar el comentario.
  write_conf "profile work ~/.claude-work *@empresa.com #171b12"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"#171b12" ]]
}

@test "parsea rutas conservando el glob sin expandir" {
  write_conf "profile work ~/.claude-work" "route ~/repos/sotos-* work"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(printf 'route\t%s/repos/sotos-*\twork' "$HOME")" ]]
}

@test "rechaza una directiva desconocida indicando la linea" {
  write_conf "profile personal ~/.claude" "profil work ~/.claude-work"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"linea 2"* ]]
  [[ "$output" == *"profil"* ]]
}

@test "rechaza un perfil sin directorio" {
  write_conf "profile work"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"linea 1"* ]]
}

@test "rechaza un color mal formado" {
  write_conf "profile work ~/.claude-work *@empresa.com rojo"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"color"* ]]
}

@test "rechaza una ruta sin perfil" {
  write_conf "profile work ~/.claude-work" "route ~/repos/algo"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 2 ]
}

@test "rechaza campos de mas" {
  write_conf "profile work ~/.claude-work *@empresa.com #171b12 sobra"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 2 ]
}

@test "un archivo ilegible es un error de config" {
  run config_parse "$BATS_TEST_TMPDIR/no-existe.conf"
  [ "$status" -eq 2 ]
}

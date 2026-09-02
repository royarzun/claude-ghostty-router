bats_require_minimum_version 1.5.0

setup() {
  load helper
  setup_fixture
  source "$CAR_ROOT/lib/config.sh"
}

@test "parsea un perfil completo y expande ~" {
  write_conf "profile work ~/.claude-work *@empresa.com #171b12"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'profile\twork\t%s/.claude-work\t*@empresa.com\t#171b12\t-' "$HOME")" ]
}

@test "los campos opcionales quedan en guion" {
  write_conf "profile personal ~/.claude"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'profile\tpersonal\t%s/.claude\t-\t-\t-' "$HOME")" ]
}

@test "ignora comentarios de linea completa, lineas vacias y espacios sobrantes" {
  write_conf "# comentario" "" "   # comentario indentado" "   profile personal ~/.claude   " "  "
  run config_parse "$CAR_CONF"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'profile\tpersonal\t%s/.claude\t-\t-\t-' "$HOME")" ]
}

@test "un # a media linea es parte del campo, no un comentario" {
  # Sin esto, el color #171b12 se perderia al recortar el comentario.
  write_conf "profile work ~/.claude-work *@empresa.com #171b12"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'profile\twork\t%s/.claude-work\t*@empresa.com\t#171b12\t-' "$HOME")" ]
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

@test "parsea el color de fondo como quinto campo" {
  write_conf "profile work ~/.claude-work *@empresa.com #8fbc5a #171b12"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'profile\twork\t%s/.claude-work\t*@empresa.com\t#8fbc5a\t#171b12' "$HOME")" ]
}

@test "el fondo ausente queda en guion: las configs viejas siguen valiendo" {
  write_conf "profile work ~/.claude-work *@empresa.com #8fbc5a"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'profile\twork\t%s/.claude-work\t*@empresa.com\t#8fbc5a\t-' "$HOME")" ]
}

@test "rechaza un fondo mal formado" {
  write_conf "profile work ~/.claude-work *@empresa.com #8fbc5a verde"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"fondo"* ]]
}

@test "un perfil puede tener fondo sin color de badge" {
  write_conf "profile work ~/.claude-work *@empresa.com - #171b12"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'profile\twork\t%s/.claude-work\t*@empresa.com\t-\t#171b12' "$HOME")" ]
}

@test "rechaza una ruta sin perfil" {
  write_conf "profile work ~/.claude-work" "route ~/repos/algo"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 2 ]
}

@test "rechaza campos de mas" {
  write_conf "profile work ~/.claude-work *@empresa.com #171b12 #0a0a0a sobra"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 2 ]
}

@test "un archivo ilegible es un error de config" {
  run config_parse "$BATS_TEST_TMPDIR/no-existe.conf"
  [ "$status" -eq 2 ]
}

@test "tolera finales de linea CRLF" {
  printf 'profile personal ~/.claude\r\nroute ~/repos/uno personal\r\n' > "$CAR_CONF"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'profile\tpersonal\t%s/.claude\t-\t-\t-\nroute\t%s/repos/uno\tpersonal' "$HOME" "$HOME")" ]
}

@test "los errores van a stderr, no al flujo de registros" {
  write_conf "profile personal ~/.claude" "basura aqui"
  run --separate-stderr config_parse "$CAR_CONF"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"linea 2"* ]]
  # stdout solo lleva el registro valido ya emitido, nunca el mensaje de error
  [[ "$output" != *"linea 2"* ]]
}

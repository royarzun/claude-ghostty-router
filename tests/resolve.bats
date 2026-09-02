setup() {
  load helper
  setup_fixture
  source "$CAR_ROOT/lib/config.sh"
  source "$CAR_ROOT/lib/resolve.sh"
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/proyecto-uno/interno personal" \
    "route ~/repos/proyecto-uno work" \
    "route ~/repos/sotos-* work"
  car_load_config "$CAR_CONF"
}

# resolve_route imprime: perfil<TAB>proyecto<TAB>dir<TAB>glob<TAB>color<TAB>fondo

@test "coincidencia exacta de ruta" {
  mkdir -p "$HOME/repos/proyecto-uno"
  run resolve_route "$HOME/repos/proyecto-uno"
  [ "$status" -eq 0 ]
  [[ "$output" == work$'\t'proyecto-uno$'\t'* ]]
}

@test "un subdirectorio hereda la ruta del padre" {
  mkdir -p "$HOME/repos/proyecto-uno/src/hondo"
  run resolve_route "$HOME/repos/proyecto-uno/src/hondo"
  [ "$status" -eq 0 ]
  [[ "$output" == work$'\t'* ]]
}

@test "la primera ruta declarada gana: la excepcion anidada" {
  mkdir -p "$HOME/repos/proyecto-uno/interno"
  run resolve_route "$HOME/repos/proyecto-uno/interno"
  [ "$status" -eq 0 ]
  [[ "$output" == personal$'\t'* ]]
}

@test "los globs de ruta funcionan" {
  mkdir -p "$HOME/repos/sotos-chat/sub"
  run resolve_route "$HOME/repos/sotos-chat/sub"
  [ "$status" -eq 0 ]
  [[ "$output" == work$'\t'* ]]
}

@test "sin coincidencia cae al primer perfil declarado" {
  mkdir -p "$HOME/otro/sitio"
  run resolve_route "$HOME/otro/sitio"
  [ "$status" -eq 0 ]
  [[ "$output" == personal$'\t'sitio$'\t'* ]]
}

@test "emite el dir, el glob, el color y el fondo del perfil resuelto" {
  mkdir -p "$HOME/repos/proyecto-uno"
  run resolve_route "$HOME/repos/proyecto-uno"
  [ "$output" = "$(printf 'work\tproyecto-uno\t%s/.claude-work\t*@empresa.com\t#171b12\t-' "$HOME")" ]
}

@test "el proyecto de una ruta con glob sale del directorio, no del patron" {
  mkdir -p "$HOME/repos/sotos-chat"
  run resolve_route "$HOME/repos/sotos-chat"
  [[ "$output" == work$'\t'sotos-chat$'\t'* ]]
}

@test "una ruta con barra final casa igual: es lo que escribe el autocompletado" {
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/conbarra/ work"
  car_load_config "$CAR_CONF"
  mkdir -p "$HOME/repos/conbarra/src"
  run resolve_route "$HOME/repos/conbarra"
  [[ "$output" == work$'\t'* ]]
  run resolve_route "$HOME/repos/conbarra/src"
  [[ "$output" == work$'\t'* ]]
}

@test "el config-dir de un perfil tolera la barra final" {
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work/ *@empresa.com #171b12" \
    "route ~/repos/miapp work"
  car_load_config "$CAR_CONF"
  mkdir -p "$HOME/repos/miapp"
  run resolve_route "$HOME/repos/miapp"
  [ "$(printf '%s' "$output" | cut -f3)" = "$HOME/.claude-work" ]
}

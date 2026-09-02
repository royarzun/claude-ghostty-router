setup() {
  load helper
  setup_fixture
  source "$CAR_ROOT/lib/config.sh"
  source "$CAR_ROOT/lib/resolve.sh"
  write_conf \
    "profile personal ~/.claude royarzun@gmail.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/proyecto-uno/interno personal" \
    "route ~/repos/proyecto-uno work" \
    "route ~/repos/sotos-* work"
  car_load_config "$CAR_CONF"
}

# resolve_route imprime: perfil<TAB>proyecto<TAB>dir<TAB>glob<TAB>color

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

@test "emite el dir, el glob y el color del perfil resuelto" {
  mkdir -p "$HOME/repos/proyecto-uno"
  run resolve_route "$HOME/repos/proyecto-uno"
  [ "$output" = "$(printf 'work\tproyecto-uno\t%s/.claude-work\t*@empresa.com\t#171b12' "$HOME")" ]
}

@test "el proyecto de una ruta con glob sale del directorio, no del patron" {
  mkdir -p "$HOME/repos/sotos-chat"
  run resolve_route "$HOME/repos/sotos-chat"
  [[ "$output" == work$'\t'sotos-chat$'\t'* ]]
}

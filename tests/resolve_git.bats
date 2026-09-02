setup() {
  load helper
  setup_fixture
  source "$CAR_ROOT/lib/config.sh"
  source "$CAR_ROOT/lib/resolve.sh"
}

@test "un repo clonado fuera de la ruta se resuelve por su raiz" {
  make_repo "$HOME/repos/miapp"
  mkdir -p "$HOME/repos/miapp/src"
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/miapp work"
  car_load_config "$CAR_CONF"
  run resolve_route "$HOME/repos/miapp/src"
  [ "$status" -eq 0 ]
  [[ "$output" == work$'\t'miapp$'\t'* ]]
}

@test "un worktree en otro disco sigue al repositorio principal" {
  make_repo "$HOME/repos/miapp"
  git -C "$HOME/repos/miapp" worktree add -q -b rama "$HOME/scratch/rama-suelta"
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/miapp work"
  car_load_config "$CAR_CONF"
  run resolve_route "$HOME/scratch/rama-suelta"
  [ "$status" -eq 0 ]
  [[ "$output" == work$'\t'* ]]
}

@test "la etiqueta de proyecto es la raiz del repo, no el subdirectorio" {
  make_repo "$HOME/repos/miapp"
  mkdir -p "$HOME/repos/miapp/src/hondo"
  write_conf "profile personal ~/.claude tu-email@ejemplo.com -"
  car_load_config "$CAR_CONF"
  run resolve_route "$HOME/repos/miapp/src/hondo"
  [[ "$output" == personal$'\t'miapp$'\t'* ]]
}

@test "fuera de un repo la etiqueta es el basename del directorio" {
  mkdir -p "$HOME/notas/varias"
  write_conf "profile personal ~/.claude tu-email@ejemplo.com -"
  car_load_config "$CAR_CONF"
  run resolve_route "$HOME/notas/varias"
  [[ "$output" == personal$'\t'varias$'\t'* ]]
}

@test "un directorio inexistente no revienta y cae al perfil por defecto" {
  write_conf "profile personal ~/.claude tu-email@ejemplo.com -"
  car_load_config "$CAR_CONF"
  run resolve_route "$HOME/no/existe"
  [ "$status" -eq 0 ]
  [[ "$output" == personal$'\t'* ]]
}

@test "resuelve aunque la ruta pase por un symlink" {
  mkdir -p "$HOME/volumen"
  make_repo "$HOME/volumen/miapp"
  ln -s "$HOME/volumen" "$HOME/enlace"
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/volumen/miapp work"
  car_load_config "$CAR_CONF"
  run resolve_route "$HOME/enlace/miapp"
  [ "$status" -eq 0 ]
  [[ "$output" == work$'\t'miapp$'\t'* ]]
}

@test "resuelve por ruta fisica aunque el directorio no sea un repo git" {
  # Sin repo, `root` y `main` quedan vacios: si la comparacion no canonicaliza,
  # esto cae al perfil por defecto en silencio y se trabaja con otra cuenta.
  mkdir -p "$HOME/volumen/notas"
  ln -s "$HOME/volumen" "$HOME/enlace"
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/volumen/notas work"
  car_load_config "$CAR_CONF"
  run resolve_route "$HOME/enlace/notas"
  [ "$status" -eq 0 ]
  [[ "$output" == work$'\t'notas$'\t'* ]]
}

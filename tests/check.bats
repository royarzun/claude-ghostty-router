setup() {
  load helper
  setup_fixture
  CA="$CAR_ROOT/bin/claude-account"
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #8fbc5a" \
    "route ~/repos/miapp work"
}

# Los dos perfiles en orden: con sesion, con el email que toca y con badge.
perfiles_ok() {
  make_profile ".claude" "tu-email@ejemplo.com"
  make_profile ".claude-work" "ricardo@empresa.com"
  install_badge ".claude"
  install_badge ".claude-work"
  export CAR_ROUTER_LOADED=1
}

@test "todo en orden sale con 0" {
  perfiles_ok
  run "$CA" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"routes.conf valido"* ]]
}

# #8fbc5a = rgb(143, 188, 90), luminancia 163 -> texto negro. La prueba fija la
# barra completa pegada a la linea de SU perfil (no solo que aparezca en algun
# sitio del output): una muestra impresa encima del perfil anterior, o la de
# otro perfil, tambien haria pasar una comprobacion que solo buscara la
# secuencia suelta.
@test "la muestra del perfil sale con su propio fondo, debajo de su perfil" {
  perfiles_ok
  run "$CA" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"work: ricardo@empresa.com"$'\n'"       badge $(printf '\033[48;2;143;188;90;38;2;0;0;0m \033[1m#8fbc5a\033[22m \033[0m')"* ]]
  # personal no declara color ("-" en routes.conf): fijar tambien su linea
  # detecta ademas que las dos lineas no se hayan intercambiado entre si.
  [[ "$output" == *"personal: tu-email@ejemplo.com"$'\n'"       badge -"* ]]
}

@test "un perfil sin sesion hace fallar el check" {
  perfiles_ok
  rm -f "$HOME/.claude-work/.claude.json"
  run "$CA" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"work"* ]]
  [[ "$output" == *"sin sesion"* ]]
}

@test "un email que no cumple su glob hace fallar el check" {
  perfiles_ok
  make_profile ".claude-work" "tu-email@ejemplo.com"
  run "$CA" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"no coincide"* ]]
}

@test "dos perfiles con el mismo email se avisan" {
  write_conf \
    "profile personal ~/.claude - -" \
    "profile work ~/.claude-work - -"
  perfiles_ok
  make_profile ".claude-work" "tu-email@ejemplo.com"
  run "$CA" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"misma cuenta"* ]]
}

@test "un perfil sin badge hace fallar el check" {
  perfiles_ok
  rm -f "$HOME/.claude-work/settings.json"
  run "$CA" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"sin statusLine"* ]]
}

@test "un statusLine ajeno se avisa sin proponerse pisarlo" {
  perfiles_ok
  printf '{"statusLine":{"type":"command","command":"mi-script"}}\n' \
    > "$HOME/.claude-work/settings.json"
  run "$CA" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"otro statusLine"* ]]
}

@test "un settings.json corrupto se avisa" {
  perfiles_ok
  printf 'no soy json\n' > "$HOME/.claude-work/settings.json"
  run "$CA" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"no puedo leer"* ]]
}

@test "sin el router cargado en la sesion avisa" {
  perfiles_ok
  run env -u CAR_ROUTER_LOADED "$CA" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"router no esta cargado"* ]]
}

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

@test "check muestra los dos colores de cada perfil" {
  # Los campos cuarto y quinto son adyacentes y con la misma sintaxis: un
  # intercambio parsea limpio y solo se nota mirando el resultado. Verlos aqui
  # es lo unico que convierte ese fallo silencioso en uno visible.
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com - -" \
    "profile work ~/.claude-work *@empresa.com #8fbc5a #171b12" \
    "route ~/repos/miapp work"
  perfiles_ok
  run "$CA" check
  [[ "$output" == *"badge #8fbc5a"* ]]
  [[ "$output" == *"fondo #171b12"* ]]
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

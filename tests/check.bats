setup() {
  load helper
  setup_fixture
  CA="$CAR_ROOT/bin/claude-account"
  export CAR_GHOSTTY_CONF="$BATS_TEST_TMPDIR/config.ghostty"
  write_conf \
    "profile personal ~/.claude royarzun@gmail.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/miapp work"
}

@test "todo en orden sale con 0" {
  make_profile ".claude" "royarzun@gmail.com"
  make_profile ".claude-work" "ricardo@empresa.com"
  printf 'shell-integration-features = cursor,no-sudo,no-title,path\n' > "$CAR_GHOSTTY_CONF"
  export CAR_ROUTER_LOADED=1
  run "$CA" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"routes.conf valido"* ]]
}

@test "un perfil sin sesion hace fallar el check" {
  make_profile ".claude" "royarzun@gmail.com"
  make_profile ".claude-work"
  printf 'shell-integration-features = no-title\n' > "$CAR_GHOSTTY_CONF"
  export CAR_ROUTER_LOADED=1
  run "$CA" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"work"* ]]
  [[ "$output" == *"sin sesion"* ]]
}

@test "un email que no cumple su glob hace fallar el check" {
  make_profile ".claude" "royarzun@gmail.com"
  make_profile ".claude-work" "royarzun@gmail.com"
  printf 'shell-integration-features = no-title\n' > "$CAR_GHOSTTY_CONF"
  export CAR_ROUTER_LOADED=1
  run "$CA" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"no coincide"* ]]
}

@test "dos perfiles con el mismo email se avisan" {
  write_conf \
    "profile personal ~/.claude - -" \
    "profile work ~/.claude-work - -"
  make_profile ".claude" "royarzun@gmail.com"
  make_profile ".claude-work" "royarzun@gmail.com"
  printf 'shell-integration-features = no-title\n' > "$CAR_GHOSTTY_CONF"
  export CAR_ROUTER_LOADED=1
  run "$CA" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"misma cuenta"* ]]
}

@test "sin no-title en la config de Ghostty avisa" {
  make_profile ".claude" "royarzun@gmail.com"
  make_profile ".claude-work" "ricardo@empresa.com"
  printf 'theme = Github Dark Default\n' > "$CAR_GHOSTTY_CONF"
  export CAR_ROUTER_LOADED=1
  run "$CA" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"no-title"* ]]
}

@test "sin el router cargado en la sesion avisa" {
  make_profile ".claude" "royarzun@gmail.com"
  make_profile ".claude-work" "ricardo@empresa.com"
  printf 'shell-integration-features = no-title\n' > "$CAR_GHOSTTY_CONF"
  run env -u CAR_ROUTER_LOADED "$CA" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"router no esta cargado"* ]]
}

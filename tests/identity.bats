setup() {
  load helper
  setup_fixture
  source "$CAR_ROOT/lib/config.sh"
  source "$CAR_ROOT/lib/identity.sh"
}

@test "lee el email del layout interno (<dir>/.claude.json)" {
  make_profile ".claude-work" "ricardo@empresa.com"
  run identity_email "$HOME/.claude-work"
  [ "$status" -eq 0 ]
  [ "$output" = "ricardo@empresa.com" ]
}

@test "lee el email del layout hermano (<dir>.json)" {
  mkdir -p "$HOME/.claude"
  printf '{"oauthAccount":{"emailAddress":"royarzun@gmail.com"}}\n' > "$HOME/.claude.json"
  run identity_email "$HOME/.claude"
  [ "$status" -eq 0 ]
  [ "$output" = "royarzun@gmail.com" ]
}

@test "el layout interno gana sobre el hermano" {
  make_profile ".claude" "interno@example.com"
  printf '{"oauthAccount":{"emailAddress":"hermano@example.com"}}\n' > "$HOME/.claude.json"
  run identity_email "$HOME/.claude"
  [ "$output" = "interno@example.com" ]
}

@test "un directorio de perfil inexistente es error 6" {
  run identity_email "$HOME/.no-existe"
  [ "$status" -eq 6 ]
  [[ "$output" == *"no existe"* ]]
}

@test "un perfil sin archivo de identidad es error 3" {
  make_profile ".claude-work"
  run identity_email "$HOME/.claude-work"
  [ "$status" -eq 3 ]
  [[ "$output" == *"sin sesion"* ]]
}

@test "un archivo sin oauthAccount es error 3" {
  mkdir -p "$HOME/.claude-work"
  printf '{"numStartups": 3}\n' > "$HOME/.claude-work/.claude.json"
  run identity_email "$HOME/.claude-work"
  [ "$status" -eq 3 ]
}

@test "un email vacio es error 3" {
  mkdir -p "$HOME/.claude-work"
  printf '{"oauthAccount":{"emailAddress":""}}\n' > "$HOME/.claude-work/.claude.json"
  run identity_email "$HOME/.claude-work"
  [ "$status" -eq 3 ]
}

@test "un JSON corrupto es error 4" {
  mkdir -p "$HOME/.claude-work"
  printf '{roto\n' > "$HOME/.claude-work/.claude.json"
  run identity_email "$HOME/.claude-work"
  [ "$status" -eq 4 ]
  [[ "$output" == *"ilegible"* ]]
}

@test "sin python3 no se puede verificar: error 7" {
  make_profile ".claude-work" "ricardo@empresa.com"
  mkdir -p "$BATS_TEST_TMPDIR/sin-nada"
  local guardado="$PATH"
  PATH="$BATS_TEST_TMPDIR/sin-nada"
  run identity_email "$HOME/.claude-work"
  PATH="$guardado"
  [ "$status" -eq 7 ]
  [[ "$output" == *"python3"* ]]
}

@test "identity_matches acepta el glob que corresponde" {
  run identity_matches "ricardo@empresa.com" "*@empresa.com"
  [ "$status" -eq 0 ]
}

@test "identity_matches rechaza el glob que no corresponde" {
  run identity_matches "royarzun@gmail.com" "*@empresa.com"
  [ "$status" -eq 5 ]
}

@test "el glob '-' significa no verificar" {
  run identity_matches "cualquiera@example.com" "-"
  [ "$status" -eq 0 ]
}

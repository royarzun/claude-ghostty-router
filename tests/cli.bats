setup() {
  load helper
  setup_fixture
  CA="$CAR_ROOT/bin/claude-account"
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/miapp work"
  mkdir -p "$HOME/repos/miapp"
}

@test "which imprime solo el nombre del perfil" {
  run "$CA" which "$HOME/repos/miapp"
  [ "$status" -eq 0 ]
  [ "$output" = "work" ]
}

@test "which sin argumento usa el directorio actual" {
  cd "$HOME/repos/miapp"
  run "$CA" which
  [ "$output" = "work" ]
}

@test "routes lista las rutas con su perfil" {
  run "$CA" routes
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/repos/miapp"* ]]
  [[ "$output" == *"work"* ]]
}

@test "status muestra cada perfil con su email logueado" {
  make_profile ".claude" "tu-email@ejemplo.com"
  make_profile ".claude-work" "ricardo@empresa.com"
  cd "$HOME/repos/miapp"
  run "$CA"
  [ "$status" -eq 0 ]
  [[ "$output" == *"personal"* ]]
  [[ "$output" == *"tu-email@ejemplo.com"* ]]
  [[ "$output" == *"ricardo@empresa.com"* ]]
  [[ "$output" == *"work"* ]]
}

@test "status marca los perfiles sin sesion" {
  make_profile ".claude" "tu-email@ejemplo.com"
  run "$CA" status
  [[ "$output" == *"sin sesion"* ]]
}

@test "login exige un perfil existente" {
  run "$CA" login fantasma
  [ "$status" -eq 2 ]
  [[ "$output" == *"fantasma"* ]]
}

@test "login lanza claude con el CLAUDE_CONFIG_DIR del perfil" {
  make_profile ".claude-work"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/claude" <<'FALSO'
#!/bin/sh
echo "CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR"
FALSO
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  # El PATH se exporta antes de `run`: un prefijo VAR=x delante de una funcion
  # de shell no se comporta igual que delante de un comando externo.
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  run "$CA" login work
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLAUDE_CONFIG_DIR=$HOME/.claude-work"* ]]
}

@test "help lista los comandos" {
  run "$CA" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"routes"* ]]
  [[ "$output" == *"check"* ]]
}

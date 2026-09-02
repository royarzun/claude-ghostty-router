setup() {
  load helper
  setup_fixture
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/miapp work"
  mkdir -p "$HOME/repos/miapp"

  # Un claude falso que deja rastro si alguien lo ejecuta.
  export FAKE_BIN="$BATS_TEST_TMPDIR/bin"
  export RASTRO="$BATS_TEST_TMPDIR/arranco.txt"
  mkdir -p "$FAKE_BIN"
  cat > "$FAKE_BIN/claude" <<'FALSO'
#!/bin/sh
printf '%s\n' "$CLAUDE_CONFIG_DIR" > "$RASTRO"
echo "claude falso arranco"
FALSO
  chmod +x "$FAKE_BIN/claude"
}

run_zsh() {
  TERM=xterm-ghostty run zsh -f -c "
    export CAR_CONF='$CAR_CONF'
    export RASTRO='$RASTRO'
    export PATH='$FAKE_BIN:$CAR_ROOT/bin:$PATH'
    source '$CAR_ROOT/shell/router.zsh'
    $1
  "
}

@test "cuenta correcta: arranca con el CLAUDE_CONFIG_DIR del perfil" {
  make_profile ".claude-work" "ricardo@empresa.com"
  run_zsh "cd '$HOME/repos/miapp'; claude"
  [ "$status" -eq 0 ]
  [ "$(cat "$RASTRO")" = "$HOME/.claude-work" ]
}

@test "cuenta equivocada: NO arranca" {
  make_profile ".claude-work" "tu-email@ejemplo.com"
  run_zsh "cd '$HOME/repos/miapp'; claude"
  [ "$status" -eq 5 ]
  [ ! -f "$RASTRO" ]
  [[ "$output" == *"cuenta equivocada"* ]]
}

@test "perfil sin sesion: NO arranca" {
  make_profile ".claude-work"
  run_zsh "cd '$HOME/repos/miapp'; claude"
  [ "$status" -eq 3 ]
  [ ! -f "$RASTRO" ]
}

@test "routes.conf roto: NO arranca" {
  make_profile ".claude-work" "ricardo@empresa.com"
  printf 'basura aqui\n' > "$CAR_CONF"
  run_zsh "cd '$HOME/repos/miapp'; claude"
  [ "$status" -eq 2 ]
  [ ! -f "$RASTRO" ]
}

@test "los argumentos llegan intactos al binario real" {
  make_profile ".claude-work" "ricardo@empresa.com"
  cat > "$FAKE_BIN/claude" <<'FALSO'
#!/bin/sh
printf '%s\n' "$*" > "$RASTRO"
FALSO
  chmod +x "$FAKE_BIN/claude"
  run_zsh "cd '$HOME/repos/miapp'; claude --version 'con espacio'"
  [ "$(cat "$RASTRO")" = "--version con espacio" ]
}

@test "fuera de Ghostty la funcion ni siquiera existe" {
  make_profile ".claude-work" "tu-email@ejemplo.com"
  TERM=xterm-256color run zsh -f -c "
    export CAR_CONF='$CAR_CONF'
    export RASTRO='$RASTRO'
    export PATH='$FAKE_BIN:$CAR_ROOT/bin:$PATH'
    source '$CAR_ROOT/shell/router.zsh'
    cd '$HOME/repos/miapp'
    claude
  "
  [ "$status" -eq 0 ]
  [ -f "$RASTRO" ]
}

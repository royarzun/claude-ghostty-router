setup() {
  load helper
  setup_fixture
}

@test "el helper crea un HOME desechable" {
  local base
  # setup_fixture canonicaliza HOME (cd -P); comparamos contra la misma forma
  # fisica de BATS_TEST_TMPDIR, no contra el string logico.
  base="$(cd -P "$BATS_TEST_TMPDIR" && pwd)"
  [ -d "$HOME" ]
  [[ "$HOME" == "$base"* ]]
}

@test "make_profile escribe un archivo de identidad legible" {
  make_profile ".claude-test" "alguien@example.com"
  run grep -c "alguien@example.com" "$HOME/.claude-test/.claude.json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

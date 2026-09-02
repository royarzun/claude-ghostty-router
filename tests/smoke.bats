setup() {
  load helper
  setup_fixture
}

@test "el helper crea un HOME desechable" {
  [ -d "$HOME" ]
  [[ "$HOME" == "$BATS_TEST_TMPDIR"* ]]
}

@test "make_profile escribe un archivo de identidad legible" {
  make_profile ".claude-test" "alguien@example.com"
  run grep -c "alguien@example.com" "$HOME/.claude-test/.claude.json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

setup() {
  load helper
  setup_fixture
  SP="$CAR_ROOT/lib/settings.py"
  S="$HOME/settings.json"
  CMD="/x/claude-account statusline"
}

@test "agrega la clave conservando el resto del archivo" {
  printf '{"model":"opus","permissions":{"allow":["Bash"]}}\n' > "$S"
  run python3 "$SP" "$S" --install "$CMD"
  [ "$status" -eq 0 ]
  run python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['model'], d['permissions']['allow'][0], d['statusLine']['command'])" "$S"
  [ "$output" = "opus Bash $CMD" ]
}

@test "es idempotente: la segunda pasada no escribe" {
  printf '{}\n' > "$S"
  python3 "$SP" "$S" --install "$CMD"
  rm -f "$S.bak"
  run python3 "$SP" "$S" --install "$CMD"
  [ "$status" -eq 2 ]
  [ ! -f "$S.bak" ]
}

@test "respalda antes de escribir" {
  printf '{"model":"opus"}\n' > "$S"
  python3 "$SP" "$S" --install "$CMD"
  run grep -c statusLine "$S.bak"
  [ "$output" = "0" ]
}

@test "conserva el modo del archivo" {
  # ~/.claude/settings.json es 600: escribirlo no puede abrirlo a mas gente.
  printf '{}\n' > "$S"
  chmod 600 "$S"
  python3 "$SP" "$S" --install "$CMD"
  run stat -f '%Lp' "$S"
  [ "$output" = "600" ]
}

@test "un settings.json que no existe se crea cerrado" {
  run python3 "$SP" "$S" --install "$CMD"
  [ "$status" -eq 0 ]
  run stat -f '%Lp' "$S"
  [ "$output" = "600" ]
}

@test "no pisa un statusLine ajeno" {
  printf '{"statusLine":{"type":"command","command":"mi-propio-script"}}\n' > "$S"
  run python3 "$SP" "$S" --install "$CMD"
  [ "$status" -eq 3 ]
  run grep -c "mi-propio-script" "$S"
  [ "$output" = "1" ]
}

@test "actualiza el nuestro si cambio de ruta" {
  # Mover el repo cambia la ruta absoluta del comando: eso sigue siendo nuestro.
  printf '{"statusLine":{"type":"command","command":"/viejo/claude-account statusline"}}\n' > "$S"
  run python3 "$SP" "$S" --install "$CMD"
  [ "$status" -eq 0 ]
  run grep -c "/x/claude-account" "$S"
  [ "$output" = "1" ]
}

@test "un JSON corrupto no se escribe" {
  printf 'esto no es json\n' > "$S"
  run python3 "$SP" "$S" --install "$CMD"
  [ "$status" -eq 1 ]
  run cat "$S"
  [ "$output" = "esto no es json" ]
}

@test "uninstall quita solo el nuestro" {
  printf '{"model":"opus"}\n' > "$S"
  python3 "$SP" "$S" --install "$CMD"
  run python3 "$SP" "$S" --uninstall
  [ "$status" -eq 0 ]
  run grep -c "statusLine" "$S"
  [ "$output" = "0" ]
  run grep -c "opus" "$S"
  [ "$output" = "1" ]
}

@test "uninstall respeta un statusLine ajeno" {
  printf '{"statusLine":{"type":"command","command":"mi-propio-script"}}\n' > "$S"
  run python3 "$SP" "$S" --uninstall
  [ "$status" -eq 3 ]
  run grep -c "mi-propio-script" "$S"
  [ "$output" = "1" ]
}

@test "check no escribe y distingue los tres estados" {
  printf '{}\n' > "$S"
  run python3 "$SP" "$S" --check
  [ "$status" -eq 2 ]

  python3 "$SP" "$S" --install "$CMD"
  run python3 "$SP" "$S" --check
  [ "$status" -eq 0 ]

  printf '{"statusLine":{"type":"command","command":"otro"}}\n' > "$S"
  run python3 "$SP" "$S" --check
  [ "$status" -eq 3 ]
  run grep -c "otro" "$S"
  [ "$output" = "1" ]
}

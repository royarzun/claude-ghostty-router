setup() {
  load helper
  setup_fixture
  source "$CAR_ROOT/lib/config.sh"
  source "$CAR_ROOT/lib/ghostty.sh"
}

@test "el titulo sale como OSC 2 terminado en BEL" {
  run ghostty_title "work · proyecto"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]2;work · proyecto\007')" ]
}

@test "el separador UTF-8 sobrevive al saneo" {
  # bash 3.2 y los multibyte no siempre se llevan bien: si este test falla,
  # cambia el separador a ASCII en cmd_surface (" - ") y ajusta los tests.
  run ghostty_title "work · proyecto"
  [[ "$output" == *"·"* ]]
}

@test "el titulo elimina bytes de control" {
  run ghostty_title "$(printf 'mal\033]0;inyectado\007nombre')"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]2;mal]0;inyectadonombre\007')" ]
}

@test "el titulo se recorta a 60 caracteres" {
  local largo
  largo="$(printf 'x%.0s' $(seq 1 200))"
  run ghostty_title "$largo"
  [ "${#output}" -eq 65 ]   # ESC ] 2 ; + 60 caracteres + BEL
}

@test "un color valido sale como OSC 11" {
  run ghostty_bg "#171b12"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]11;#171b12\007')" ]
}

@test "el guion resetea el fondo con OSC 111" {
  run ghostty_bg "-"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]111\007')" ]
}

@test "un color invalido no emite nada y falla" {
  run ghostty_bg "rojo; rm -rf /"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "un color con longitud incorrecta falla" {
  run ghostty_bg "#abc"
  [ "$status" -eq 1 ]
}

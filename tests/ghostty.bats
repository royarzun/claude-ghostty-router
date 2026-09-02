setup() {
  load helper
  setup_fixture
  source "$CAR_ROOT/lib/ghostty.sh"
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
  # Lo que entra aqui viene de un archivo de configuracion: si se colara sin
  # validar, seria una via de inyeccion de secuencias de escape.
  run ghostty_bg "rojo; rm -rf /"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "un color con longitud incorrecta falla" {
  run ghostty_bg "#abc"
  [ "$status" -eq 1 ]
}

@test "sin argumento resetea en vez de reventar" {
  # ghostty.sh se carga en un script con `set -u`, donde un "$1" ausente
  # mataria el proceso entero y no solo esta funcion.
  run ghostty_bg
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]111\007')" ]
}

@test "una cadena vacia resetea igual que el guion" {
  run ghostty_bg ""
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]111\007')" ]
}

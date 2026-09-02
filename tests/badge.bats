setup() {
  load helper
  setup_fixture
  source "$CAR_ROOT/lib/config.sh"
  source "$CAR_ROOT/lib/badge.sh"
}

@test "un color valido pinta el texto en negrita con SGR de 24 bits" {
  run badge_color "work" "#8fbc5a"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033[1;38;2;143;188;90mwork\033[0m')" ]
}

@test "el guion devuelve el texto sin colorear" {
  run badge_color "personal" "-"
  [ "$status" -eq 0 ]
  [ "$output" = "personal" ]
}

@test "un color invalido devuelve el texto igual, sin fallar" {
  # El badge informa: aqui nada puede romperse de forma ruidosa.
  run badge_color "personal" "rojo; rm -rf /"
  [ "$status" -eq 0 ]
  [ "$output" = "personal" ]
}

@test "un color de longitud incorrecta tampoco pinta" {
  run badge_color "personal" "#abc"
  [ "$status" -eq 0 ]
  [ "$output" = "personal" ]
}

@test "el saneo elimina bytes de control" {
  # Claude Code renderiza el badge respetando ANSI: sin este filtro, un nombre
  # de carpeta hostil colaria sus propias secuencias.
  run badge_sanitize "$(printf 'mal\033[31minyectado\033[0mnombre')"
  [ "$status" -eq 0 ]
  [ "$output" = "mal[31minyectado[0mnombre" ]
}

@test "el separador UTF-8 sobrevive al saneo" {
  # bash 3.2 y los multibyte no siempre se llevan bien.
  run badge_sanitize "work · proyecto"
  [[ "$output" == *"·"* ]]
}

@test "el texto se recorta a 60 caracteres" {
  local largo
  largo="$(printf 'x%.0s' $(seq 1 200))"
  run badge_sanitize "$largo"
  [ "${#output}" -eq 60 ]
}

@test "un texto coloreado tambien pasa por el saneo" {
  run badge_color "$(printf 'ma\033[31mlo')" "#8fbc5a"
  [ "$output" = "$(printf '\033[1;38;2;143;188;90mma[31mlo\033[0m')" ]
}

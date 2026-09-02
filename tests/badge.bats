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

@test "badge_strip filtra los bytes de control sin recortar" {
  # badge_bar necesita el filtro sin el recorte: la linea entera son tres
  # campos mas separadores, y recortarla a 60 la mutilaria.
  local largo
  largo="$(printf 'x%.0s' $(seq 1 200))"
  run badge_strip "$(printf 'ma\033[31mlo')$largo"
  [ "$status" -eq 0 ]
  [ "$output" = "ma[31mlo$largo" ]
  [ "${#output}" -eq 208 ]
}

# #8fbc5a = rgb(143,188,90), luminancia 163 -> por encima del umbral -> texto negro.
@test "un color claro pinta la barra entera con texto negro" {
  run badge_bar "#8fbc5a" "work" " · ricardo@empresa.com · miapp"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033[48;2;143;188;90;38;2;0;0;0m \033[1mwork\033[22m · ricardo@empresa.com · miapp \033[0m')" ]
}

# #2d4f8b = rgb(45,79,139), luminancia 75 -> por debajo del umbral -> texto blanco.
# Es el caso que un frente fijo se comeria: con negro constante, ilegible.
@test "un color oscuro pinta la barra con texto blanco" {
  run badge_bar "#2d4f8b" "work" ""
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033[48;2;45;79;139;38;2;255;255;255m \033[1mwork\033[22m \033[0m')" ]
}

@test "el guion devuelve el texto sin barra y sin los espacios de guarda" {
  # Los espacios son parte de la barra: sin barra no hay nada que separar.
  run badge_bar "-" "personal" " · a@b.com"
  [ "$status" -eq 0 ]
  [ "$output" = "personal · a@b.com" ]
}

@test "un color invalido devuelve la linea igual, sin fallar" {
  run badge_bar "rojo; rm -rf /" "personal" " · a@b.com"
  [ "$status" -eq 0 ]
  [ "$output" = "personal · a@b.com" ]
}

@test "un color de longitud incorrecta tampoco pinta la barra" {
  run badge_bar "#abc" "personal" ""
  [ "$status" -eq 0 ]
  [ "$output" = "personal" ]
}

@test "la barra filtra los bytes de control de sus dos campos, sin recortar" {
  # Quien llama no puede colar su propia negrita ni su propio color: el filtro
  # no distingue un escape nuestro de uno que venga en un nombre de carpeta.
  local largo
  largo="$(printf 'y%.0s' $(seq 1 100))"
  run badge_bar "-" "$(printf 'ma\033[31mlo')" "$largo"
  [ "$status" -eq 0 ]
  [ "$output" = "ma[31mlo$largo" ]
}

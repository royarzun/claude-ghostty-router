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

@test "el umbral exacto de luminancia: 140 es negro, 139 es blanco" {
  # Los dos colores de los otros tests estan lejos del umbral, asi que un
  # cambio de -ge a -gt pasaria la suite sin que nadie se entere.
  run badge_fg 140 140 140
  [ "$output" = "0;0;0" ]
  run badge_fg 139 139 139
  [ "$output" = "255;255;255" ]
}

@test "un argumento no numerico en badge_fg no se evalua: sale con negro y no ejecuta nada" {
  # Bash evalua los subindices de array dentro de una expansion aritmetica, asi
  # que un argumento no numerico aqui seria ejecucion de comandos. El guardia
  # tiene que cortar antes de que esa expansion llegue a evaluarse.
  local testigo="$BATS_TEST_TMPDIR/pwned_arith"
  local malo
  malo="a[\$(touch $testigo)]"
  run badge_fg "$malo" 2 3
  [ "$status" -eq 0 ]
  [ "$output" = "0;0;0" ]
  [ ! -e "$testigo" ]
}

@test "un color en mayusculas pinta la barra igual que en minusculas" {
  # routes.conf lo escribe un humano: las mayusculas tienen que funcionar.
  run badge_bar "#8FBC5A" "work" ""
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033[48;2;143;188;90;38;2;0;0;0m \033[1mwork\033[22m \033[0m')" ]
}

@test "la barra filtra los bytes de control tambien cuando si pinta el fondo" {
  # El test anterior de filtrado solo ejercita el camino sin barra (color "-").
  run badge_bar "#8fbc5a" "$(printf 'ma\033[31mlo')" "$(printf ' · b\033[0mc')"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033[48;2;143;188;90;38;2;0;0;0m \033[1mma[31mlo\033[22m · b[0mc \033[0m')" ]
}

@test "un canal con cero a la izquierda no se lee como octal" {
  # Con el guardia filtrando a solo digitos, "008" pasa el filtro pero bash lo
  # leeria como octal invalido y badge_fg saliria con error en vez de un color.
  # 008 -> 8 en base 10: luminancia (299*8+587+114)/1000=3, por debajo del
  # umbral -> frente blanco.
  run badge_fg 008 1 1
  [ "$status" -eq 0 ]
  [ "$output" = "255;255;255" ]
}

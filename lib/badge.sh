# Emisor de las secuencias SGR del proyecto: el texto coloreado del badge, que
# renderiza Claude Code dentro de la sesion. Su hermano lib/ghostty.sh emite
# OSC, que le habla al emulador de terminal.
# No sabe que es un perfil: recibe texto y color, y emite bytes.

CAR_BADGE_MAX=60

# badge_sanitize <texto>
# El badge se arma con un nombre de carpeta y con un email leido de un archivo,
# y ninguno de los dos es texto de confianza: una carpeta puede llamarse con
# bytes de control adentro. Claude Code renderiza este texto respetando ANSI,
# asi que sin este filtro un nombre hostil podria colar sus propias secuencias.
badge_sanitize() {
  local text="$1"
  text="${text//[[:cntrl:]]/}"
  printf '%s' "${text:0:$CAR_BADGE_MAX}"
}

# badge_color <texto> <color|-> -> el texto en negrita con el color del perfil.
# Un color ausente, "-" o mal formado devuelve el texto tal cual: el badge
# informa igual sin color, y aqui nada puede fallar de forma ruidosa.
badge_color() {
  local text red green blue
  text="$(badge_sanitize "$1")"
  case "${2:--}" in
    '#'[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
      red="$(printf '%d' "0x${2:1:2}")"
      green="$(printf '%d' "0x${2:3:2}")"
      blue="$(printf '%d' "0x${2:5:2}")"
      printf '\033[1;38;2;%s;%s;%sm%s\033[0m' "$red" "$green" "$blue" "$text"
      ;;
    *)
      printf '%s' "$text"
      ;;
  esac
}

# badge_swatch <color|-> -> un bloque pintado con ese color de fondo, o nada.
# Un #rrggbb no dice si un tinte es sutil o si ciega: eso solo se ve viendolo.
# Se usa en `check`, donde el campo del fondo y el del badge son adyacentes y
# con la misma sintaxis, asi que un intercambio parsea limpio y no lo delata
# ningun mensaje. Pintado, se delata solo.
# Son espacios y no un glifo de bloque a proposito: un espacio se ve igual en
# cualquier fuente.
badge_swatch() {
  local red green blue
  case "${1:--}" in
    '#'[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
      red="$(printf '%d' "0x${1:1:2}")"
      green="$(printf '%d' "0x${1:3:2}")"
      blue="$(printf '%d' "0x${1:5:2}")"
      printf '\033[48;2;%s;%s;%sm   \033[0m' "$red" "$green" "$blue"
      ;;
  esac
}

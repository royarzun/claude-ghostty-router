# Unico emisor de secuencias de escape del proyecto.
# No sabe que es un perfil: recibe texto y color, y emite bytes.

CAR_BADGE_MAX=60

# badge_strip <texto> -> el texto sin bytes de control.
# El badge se arma con un nombre de carpeta y con un email leido de un archivo,
# y ninguno de los dos es texto de confianza: una carpeta puede llamarse con
# bytes de control adentro. Claude Code renderiza este texto respetando ANSI,
# asi que sin este filtro un nombre hostil podria colar sus propias secuencias.
badge_strip() {
  local text="$1"
  printf '%s' "${text//[[:cntrl:]]/}"
}

# badge_sanitize <texto> -> el texto filtrado y recortado a CAR_BADGE_MAX.
# El recorte va por campo y no por linea: la linea del badge son tres campos
# mas separadores, y recortarla entera a 60 la mutilaria.
badge_sanitize() {
  local text
  text="$(badge_strip "$1")"
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

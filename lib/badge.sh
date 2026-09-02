# Unico emisor de secuencias de escape del proyecto.
# No sabe que es un perfil: recibe texto y color, y emite bytes.

CAR_BADGE_MAX=60
# umbral de luminancia YIQ: a partir de aqui el frente pasa a ser negro.
CAR_BADGE_LUM=140

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

# badge_fg <r> <g> <b> -> el frente que se lee sobre ese fondo, como "R;G;B".
# Luminancia YIQ: la formula de contraste de la WCAG exige linearizar cada canal
# antes de pesarlo, y para elegir entre exactamente dos frentes -negro o blanco-
# no cambia el resultado. Aritmetica entera: bash 3.2 no tiene otra.
# Bash evalua los subindices de array dentro de una expansion aritmetica, asi
# que un argumento no numerico aqui seria ejecucion de comandos: el guardia
# corta antes de esa expansion. Hoy solo la llama badge_bar, con digitos ya
# validados contra "#rrggbb"; el guardia es para el que la llame despues.
# El 10# fuerza base 10: sin el, un canal con cero a la izquierda se leeria
# como octal y la funcion saldria con error en vez de con un color.
badge_fg() {
  case "$1$2$3" in *[!0-9]*) printf '0;0;0'; return ;; esac
  local lum=$(( (299 * 10#$1 + 587 * 10#$2 + 114 * 10#$3) / 1000 ))
  if [ "$lum" -ge "$CAR_BADGE_LUM" ]; then
    printf '0;0;0'
  else
    printf '255;255;255'
  fi
}

# badge_bar <color|-> <destacado> [resto] -> la linea entera sobre el fondo.
# El destacado va en negrita y la emite esta funcion, no quien llama: un escape
# armado por fuera se lo comeria el filtro de control, y con razon, porque el
# filtro no puede distinguirlo de uno colado por un nombre de carpeta.
# Cierra con 22m y no con 0m: un reset a mitad de linea apagaria tambien el
# fondo y partiria la barra en dos.
# Un color ausente, "-" o mal formado devuelve el texto tal cual, sin barra y
# sin los espacios de guarda: el badge informa igual sin color, y aqui nada
# puede fallar de forma ruidosa.
badge_bar() {
  local color="${1:--}" strong rest red green blue fg
  strong="$(badge_strip "${2:-}")"
  rest="$(badge_strip "${3:-}")"
  case "$color" in
    '#'[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
      red="$(printf '%d' "0x${color:1:2}")"
      green="$(printf '%d' "0x${color:3:2}")"
      blue="$(printf '%d' "0x${color:5:2}")"
      fg="$(badge_fg "$red" "$green" "$blue")"
      printf '\033[48;2;%s;%s;%s;38;2;%sm \033[1m%s\033[22m%s \033[0m' \
        "$red" "$green" "$blue" "$fg" "$strong" "$rest"
      ;;
    *)
      printf '%s%s' "$strong" "$rest"
      ;;
  esac
}

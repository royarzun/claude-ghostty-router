# Unico emisor de secuencias de escape del proyecto.
# No sabe que es un perfil: recibe texto y color, y emite bytes.

CAR_TITLE_MAX=60

# ghostty_sanitize <texto>
# El titulo viene de un nombre de carpeta, y una carpeta puede llamarse con
# bytes de control adentro. Sin este filtro, un nombre hostil podria cerrar la
# secuencia OSC y colar otra: https://dgl.cx/2024/12/ghostty-terminal-title
ghostty_sanitize() {
  local text="$1"
  text="${text//[[:cntrl:]]/}"
  printf '%s' "${text:0:$CAR_TITLE_MAX}"
}

# ghostty_title <texto> -> OSC 2 (titulo de la superficie)
ghostty_title() {
  printf '\033]2;%s\007' "$(ghostty_sanitize "$1")"
}

# ghostty_bg <color|-> -> OSC 11 (fondo) u OSC 111 (reset al tema)
ghostty_bg() {
  case "$1" in
    -|"")
      printf '\033]111\007'
      ;;
    '#'[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
      printf '\033]11;%s\007' "$1"
      ;;
    *)
      return 1
      ;;
  esac
}

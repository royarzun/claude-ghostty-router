# Emisor de las secuencias OSC del proyecto: las que hablan con el emulador de
# terminal. Su hermano lib/badge.sh emite SGR, que es otra cosa: texto
# coloreado que renderiza Claude Code dentro de la sesion.
# No sabe que es un perfil: recibe un color y emite bytes.

# ghostty_bg [color|-] -> OSC 11 (fondo) u OSC 111 (reset al tema)
# Sin argumento resetea, igual que "-": este archivo se carga en un script con
# `set -u`, donde un "$1" ausente no seria un fallo de esta funcion sino la
# muerte del proceso entero. Mismo criterio que badge_color en lib/badge.sh.
# El color sale de routes.conf, asi que se valida antes de entrar en la
# secuencia: sin esto, un valor cualquiera del archivo acabaria en el flujo de
# escapes de la terminal.
ghostty_bg() {
  case "${1:--}" in
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

setup() {
  load helper
  setup_fixture
  CA="$CAR_ROOT/bin/claude-account"
  unset CLAUDE_CONFIG_DIR
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #8fbc5a" \
    "route ~/repos/miapp work"
  mkdir -p "$HOME/repos/miapp"
}

# El badge se alimenta por stdin, asi que la tuberia va dentro de la funcion
# que `run` ejecuta.
badge() {
  statusline_json "${1:-$HOME/repos/miapp}" | "$CA" statusline
}

VERDE="$(printf '\033[1;38;2;143;188;90m')"
FIN="$(printf '\033[0m')"

@test "sin CLAUDE_CONFIG_DIR el badge es el del perfil por defecto" {
  # Es el caso real del perfil por defecto: _launch-check no exporta la
  # variable justo para no esconderle al usuario su ~/.claude.json de siempre.
  make_profile ".claude" "tu-email@ejemplo.com"
  run badge
  [ "$status" -eq 0 ]
  [ "$output" = "personal · tu-email@ejemplo.com · miapp" ]
}

@test "el CLAUDE_CONFIG_DIR heredado manda sobre la carpeta" {
  # La carpeta esta ruteada a 'work', pero lo que importa es con que cuenta
  # ESTA corriendo la sesion: si alguien esquiva el shim, el badge lo delata.
  make_profile ".claude" "tu-email@ejemplo.com"
  make_profile ".claude-work" "ricardo@empresa.com"
  CLAUDE_CONFIG_DIR="$HOME/.claude" run badge
  [ "$output" = "personal · tu-email@ejemplo.com · miapp" ]
}

@test "el perfil se pinta con su color" {
  make_profile ".claude-work" "ricardo@empresa.com"
  CLAUDE_CONFIG_DIR="$HOME/.claude-work" run badge
  [ "$output" = "${VERDE}work${FIN} · ricardo@empresa.com · miapp" ]
}

@test "una barra final en CLAUDE_CONFIG_DIR sigue casando el perfil" {
  make_profile ".claude-work" "ricardo@empresa.com"
  CLAUDE_CONFIG_DIR="$HOME/.claude-work/" run badge
  [[ "$output" == *"work"* ]]
  [[ "$output" == *"ricardo@empresa.com"* ]]
}

@test "un config-dir que ningun perfil declara sale como interrogante" {
  make_profile ".claude-otro" "quien@sabe.com"
  CLAUDE_CONFIG_DIR="$HOME/.claude-otro" run badge
  [ "$output" = "? · quien@sabe.com · miapp" ]
}

@test "un perfil sin sesion lo dice en vez de inventar" {
  make_profile ".claude-work"
  CLAUDE_CONFIG_DIR="$HOME/.claude-work" run badge
  [ "$output" = "${VERDE}work${FIN} · (sin sesion) · miapp" ]
}

@test "un archivo de identidad corrupto tambien sale como sin sesion" {
  make_profile ".claude-work"
  printf 'no soy json\n' > "$HOME/.claude-work/.claude.json"
  CLAUDE_CONFIG_DIR="$HOME/.claude-work" run badge
  [ "$output" = "${VERDE}work${FIN} · (sin sesion) · miapp" ]
}

@test "con routes.conf roto avisa y sale con exito" {
  # Es el unico canal de aviso que le queda al proyecto ahora que no pinta el
  # tab. Quien bloquea el arranque sigue siendo _launch-check.
  make_profile ".claude" "tu-email@ejemplo.com"
  write_conf "basura aqui"
  run badge
  [ "$status" -eq 0 ]
  [ "$output" = "⚠ routes.conf invalido" ]
}

@test "sin routes.conf avisa igual y no falla" {
  rm -f "$CAR_CONF"
  run badge
  [ "$status" -eq 0 ]
  [ "$output" = "⚠ routes.conf invalido" ]
}

@test "un nombre de carpeta con bytes de control se sanea" {
  make_profile ".claude" "tu-email@ejemplo.com"
  local malo
  malo="$(printf '%s/repos/ma\033[31mlo' "$HOME")"
  mkdir -p "$HOME/repos"
  run badge "$malo"
  [ "$output" = "personal · tu-email@ejemplo.com · ma[31mlo" ]
}

@test "sin JSON valido por stdin el badge sale sin carpeta" {
  make_profile ".claude" "tu-email@ejemplo.com"
  run bash -c "printf 'no soy json' | '$CA' statusline"
  [ "$status" -eq 0 ]
  [ "$output" = "personal · tu-email@ejemplo.com" ]
}

@test "funciona invocado a traves de un symlink" {
  # Asi es como se instala, y asi es como lo llama el settings.json.
  make_profile ".claude" "tu-email@ejemplo.com"
  mkdir -p "$HOME/.local/bin"
  ln -sf "$CA" "$HOME/.local/bin/claude-account"
  run bash -c "$(declare -f statusline_json); statusline_json '$HOME/repos/miapp' | '$HOME/.local/bin/claude-account' statusline"
  [ "$output" = "personal · tu-email@ejemplo.com · miapp" ]
}

# Fixtures compartidas por todos los tests.
# Cada test corre con un HOME propio y desechable: nada toca la máquina real.

CAR_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export CAR_ROOT

# Prepara un HOME falso y la ruta de una routes.conf de prueba.
# HOME se canonicaliza (cd -P) para que el symlink /var->/private/var de
# macOS no contamine los tests con una discrepancia ajena a lo que cada
# test quiere probar: git siempre emite rutas fisicas.
setup_fixture() {
  local base
  base="$(cd -P "$BATS_TEST_TMPDIR" && pwd)"
  export HOME="$base/home"
  export CAR_CONF="$base/routes.conf"
  mkdir -p "$HOME"
}

# write_conf "linea 1" "linea 2" ...
write_conf() {
  printf '%s\n' "$@" > "$CAR_CONF"
}

# make_profile <subdirectorio-de-HOME> [email]
# Sin email, crea el directorio pero sin sesión iniciada.
make_profile() {
  local dir="$HOME/$1"
  mkdir -p "$dir"
  if [ -n "${2:-}" ]; then
    printf '{"oauthAccount":{"emailAddress":"%s"}}\n' "$2" > "$dir/.claude.json"
  fi
}

# make_repo <ruta> — crea un repo git mínimo y silencioso
make_repo() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email test@example.com
  git -C "$1" config user.name test
  git -C "$1" commit -q --allow-empty -m init
}

# install_badge <subdirectorio-de-HOME>
# Deja el statusLine que instala ./install.sh en el settings.json de un perfil.
install_badge() {
  local dir="$HOME/$1"
  mkdir -p "$dir"
  printf '{"statusLine":{"type":"command","command":"/x/claude-account statusline"}}\n' \
    > "$dir/settings.json"
}

# statusline_json <directorio-del-proyecto>
# El JSON de estado que Claude Code entrega por stdin a un comando de statusLine.
# Se arma con json.dumps y no con printf porque una ruta puede traer bytes que
# hay que escapar: con printf saldria un JSON invalido y el test probaria otra
# cosa distinta de la que dice probar.
statusline_json() {
  python3 -c 'import json, sys
d = sys.argv[1]
print(json.dumps({"session_id": "abc",
                  "workspace": {"project_dir": d, "current_dir": d},
                  "model": {"display_name": "Opus"}}))' "$1"
}

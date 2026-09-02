# Lectura de la identidad de un perfil. Requiere lib/config.sh cargado.

# Este archivo se analiza solo, asi que shellcheck no ve que los CAR_* que se
# retornan vienen de lib/config.sh (siempre enteros); SC2086 es un falso
# positivo en cada `return $CAR_*` y en `return $status` (que solo guarda $?).
# shellcheck disable=SC2086
CAR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# identity_file <config-dir> -> ruta del archivo de identidad, si existe
# Prueba los dos layouts posibles: <dir>/.claude.json y <dir>.json.
identity_file() {
  local dir="${1%/}" candidate
  for candidate in "$dir/.claude.json" "$dir.json"; do
    if [ -f "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

# identity_email <config-dir> -> imprime el email logueado en ese perfil
identity_email() {
  local dir="$1" file email status

  if ! command -v python3 >/dev/null 2>&1; then
    echo "claude-account: python3 no esta disponible; no puedo verificar la cuenta" >&2
    return $CAR_ENOPYTHON
  fi
  if [ ! -d "$dir" ]; then
    echo "claude-account: el directorio del perfil no existe: $dir" >&2
    return $CAR_ENODIR
  fi
  if ! file="$(identity_file "$dir")"; then
    echo "claude-account: perfil sin sesion iniciada ($dir)" >&2
    return $CAR_ENOSESSION
  fi

  email="$(python3 "$CAR_LIB_DIR/identity.py" "$file")"
  status=$?
  case $status in
    0) printf '%s' "$email" ;;
    3) echo "claude-account: perfil sin sesion iniciada ($file no tiene oauthAccount)" >&2 ;;
    *) echo "claude-account: archivo de identidad ilegible o corrupto ($file)" >&2; status=$CAR_EJSON ;;
  esac
  return $status
}

# identity_matches <email> <glob>  -> 0 si coincide, 5 si no. "-" no verifica.
identity_matches() {
  local email="$1" glob="$2"
  [ "$glob" = "-" ] && return 0
  # shellcheck disable=SC2254
  case "$email" in
    $glob) return 0 ;;
  esac
  return $CAR_EMISMATCH
}

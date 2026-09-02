# Resolucion directorio -> perfil. Requiere lib/config.sh cargado.
# bash 3.2 no tiene arrays asociativos: se usan arrays paralelos.

CAR_P_NAME=(); CAR_P_DIR=(); CAR_P_GLOB=(); CAR_P_COLOR=()
CAR_R_PATH=(); CAR_R_PROFILE=()

# car_profile_index <nombre> -> imprime el indice, o retorna 1 si no existe
car_profile_index() {
  local name="$1" i
  for ((i = 0; i < ${#CAR_P_NAME[@]}; i++)); do
    if [ "${CAR_P_NAME[$i]}" = "$name" ]; then
      printf '%s' "$i"
      return 0
    fi
  done
  return 1
}

# car_load_config <archivo> -> puebla los arrays y valida coherencia
# shellcheck disable=SC2086 # CAR_OK/CAR_ECONFIG se definen en config.sh (enteros
# literales, sin espacios ni comodines); shellcheck analiza este archivo aislado
# y no puede verlo, por eso cree que $CAR_OK/$CAR_ECONFIG sin comillas es riesgoso.
car_load_config() {
  local file="$1" parsed kind f2 f3 f4 f5 i

  CAR_P_NAME=(); CAR_P_DIR=(); CAR_P_GLOB=(); CAR_P_COLOR=()
  CAR_R_PATH=(); CAR_R_PROFILE=()

  parsed="$(config_parse "$file")" || return $CAR_ECONFIG

  while IFS=$'\t' read -r kind f2 f3 f4 f5; do
    case "$kind" in
      profile)
        if car_profile_index "$f2" >/dev/null; then
          echo "claude-account: perfil duplicado '$f2' en $file" >&2
          return $CAR_ECONFIG
        fi
        CAR_P_NAME+=("$f2"); CAR_P_DIR+=("$f3"); CAR_P_GLOB+=("$f4"); CAR_P_COLOR+=("$f5")
        ;;
      route)
        CAR_R_PATH+=("$f2"); CAR_R_PROFILE+=("$f3")
        ;;
    esac
  done <<< "$parsed"

  if [ "${#CAR_P_NAME[@]}" -eq 0 ]; then
    echo "claude-account: $file no declara ningun perfil" >&2
    return $CAR_ECONFIG
  fi

  for ((i = 0; i < ${#CAR_R_PROFILE[@]}; i++)); do
    if ! car_profile_index "${CAR_R_PROFILE[$i]}" >/dev/null; then
      echo "claude-account: $file: la ruta ${CAR_R_PATH[$i]} apunta al perfil inexistente '${CAR_R_PROFILE[$i]}'" >&2
      return $CAR_ECONFIG
    fi
  done

  return $CAR_OK
}

# car_emit_profile <perfil> <etiqueta-proyecto>
# CAR_ECONFIG se define en config.sh (entero literal); shellcheck analiza este
# archivo aislado y no puede verlo, por eso marca el return sin comillas.
# shellcheck disable=SC2086
car_emit_profile() {
  local name="$1" label="$2" i
  i="$(car_profile_index "$name")" || {
    echo "claude-account: perfil desconocido '$name'" >&2
    return $CAR_ECONFIG
  }
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$label" "${CAR_P_DIR[$i]}" "${CAR_P_GLOB[$i]}" "${CAR_P_COLOR[$i]}"
}

# car_match_dir <directorio> -> imprime el perfil de la primera ruta que casa
car_match_dir() {
  local dir="$1" i route
  for ((i = 0; i < ${#CAR_R_PATH[@]}; i++)); do
    route="${CAR_R_PATH[$i]}"
    # `case` hace matching de patrones, no expansion de nombres de archivo:
    # el glob de la ruta casa sin tocar el disco.
    # shellcheck disable=SC2254 # $route sin comillas es intencional: es lo que
    # hace que los patrones de ruta (p.ej. "sotos-*") casen como glob.
    case "$dir" in
      $route|$route/*)
        printf '%s' "${CAR_R_PROFILE[$i]}"
        return 0
        ;;
    esac
  done
  return 1
}

# resolve_route <directorio>
# -> perfil<TAB>proyecto<TAB>config-dir<TAB>email-glob<TAB>color
resolve_route() {
  local dir="$1" label profile
  label="$(basename "$dir")"
  if profile="$(car_match_dir "$dir")"; then
    car_emit_profile "$profile" "$label"
    return $?
  fi
  car_emit_profile "${CAR_P_NAME[0]}" "$label"
}

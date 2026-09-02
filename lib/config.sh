# Parseo de routes.conf. Sin efectos secundarios: entra un archivo, salen registros.
# Compatible con bash 3.2 (el /bin/bash de macOS).

# Codigos de salida compartidos por todo el proyecto. shellcheck analiza cada
# archivo por separado y no ve que resolve.sh, identity.sh y claude-account los
# consumen tras hacer `source` de este archivo.
# shellcheck disable=SC2034
CAR_OK=0
CAR_ECONFIG=2      # routes.conf invalido o ilegible
CAR_ENOSESSION=3   # perfil sin sesion iniciada
CAR_EJSON=4        # archivo de identidad corrupto
CAR_EMISMATCH=5    # email logueado != glob esperado
CAR_ENODIR=6       # config-dir del perfil no existe
CAR_ENOPYTHON=7    # python3 ausente

# Expande un ~ inicial. No toca nada mas: los globs se conservan sin expandir,
# porque el matching de rutas se hace despues con `case`.
# Es un patron de `case` que casa el literal "~/", no una expansion: por eso
# la funcion existe.
# shellcheck disable=SC2088
car_expand_tilde() {
  case "$1" in
    "~")   printf '%s' "$HOME" ;;
    "~/"*) printf '%s' "$HOME/${1#\~/}" ;;
    *)     printf '%s' "$1" ;;
  esac
}

# config_parse <archivo>
# Imprime, en orden de aparicion:
#   profile<TAB><nombre><TAB><dir><TAB><email-glob><TAB><color>
#   route<TAB><ruta><TAB><perfil>
# Los campos opcionales ausentes salen como "-".
config_parse() {
  local file="$1"
  local lineno=0 raw kind rest name dir glob color rpath rprof extra

  if [ ! -r "$file" ]; then
    echo "claude-account: no puedo leer $file" >&2
    return $CAR_ECONFIG
  fi

  while IFS= read -r raw || [ -n "$raw" ]; do
    lineno=$((lineno + 1))
    # `read` divide por espacios y descarta los sobrantes, sin expandir globs.
    read -r kind rest <<< "$raw"
    [ -n "$kind" ] || continue
    # Solo se admiten comentarios de linea completa: un '#' a media linea es
    # parte de un campo (los colores son #rrggbb).
    case "$kind" in '#'*) continue ;; esac

    case "$kind" in
      profile)
        read -r name dir glob color extra <<< "$rest"
        if [ -z "$name" ] || [ -z "$dir" ]; then
          echo "claude-account: $file linea $lineno: profile necesita <nombre> <dir>" >&2
          return $CAR_ECONFIG
        fi
        if [ -n "$extra" ]; then
          echo "claude-account: $file linea $lineno: campos de mas ('$extra')" >&2
          return $CAR_ECONFIG
        fi
        glob="${glob:--}"
        color="${color:--}"
        case "$color" in
          -) ;;
          '#'[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) ;;
          *)
            echo "claude-account: $file linea $lineno: color invalido '$color' (usa #rrggbb o -)" >&2
            return $CAR_ECONFIG
            ;;
        esac
        printf 'profile\t%s\t%s\t%s\t%s\n' "$name" "$(car_expand_tilde "$dir")" "$glob" "$color"
        ;;
      route)
        read -r rpath rprof extra <<< "$rest"
        if [ -z "$rpath" ] || [ -z "$rprof" ]; then
          echo "claude-account: $file linea $lineno: route necesita <ruta> <perfil>" >&2
          return $CAR_ECONFIG
        fi
        if [ -n "$extra" ]; then
          echo "claude-account: $file linea $lineno: campos de mas ('$extra')" >&2
          return $CAR_ECONFIG
        fi
        printf 'route\t%s\t%s\n' "$(car_expand_tilde "$rpath")" "$rprof"
        ;;
      *)
        echo "claude-account: $file linea $lineno: directiva desconocida '$kind'" >&2
        return $CAR_ECONFIG
        ;;
    esac
  done < "$file"

  return $CAR_OK
}

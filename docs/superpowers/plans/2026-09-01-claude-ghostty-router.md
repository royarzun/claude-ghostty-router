# claude-ghostty-router — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que cada carpeta use automáticamente la cuenta Claude que le corresponde dentro de Ghostty, que la cuenta activa se vea en cada tab, y que Claude no arranque si la cuenta logueada no es la esperada.

**Architecture:** Núcleo puro en bash (parseo de config, resolución `directorio → perfil`, lectura de identidad) sin efectos secundarios; una capa de presentación que es lo único que emite secuencias OSC; un CLI `claude-account` que expone el núcleo; y una integración zsh (`router.zsh`) que pinta en cada `precmd` y sustituye `claude` por una función que verifica y bloquea.

**Tech Stack:** bash 3.2 (el `/bin/bash` de macOS — sin arrays asociativos), zsh 5.9, `python3` solo para leer JSON, `bats-core` para tests, `shellcheck` para lint. Sin dependencias nuevas más allá de bats.

**Spec:** `docs/superpowers/specs/2026-09-01-claude-ghostty-router-design.md`

**Convenciones que aplican a todo el plan:**

- Todo el código shell es compatible con **bash 3.2**: nada de `declare -A`, nada de `${var^^}`, nada de `readarray`. Sí se puede usar `+=` en arrays y `for ((...))`.
- Códigos de salida compartidos: `0` ok, `2` config inválida, `3` sin sesión, `4` JSON corrupto, `5` email no coincide, `6` config-dir inexistente, `7` sin python3.
- Los mensajes al usuario van en español y siempre dicen **qué pasó** y **qué hacer**.
- Cada tarea termina en commit. Nunca se comitea con tests en rojo.

---

## Estructura de archivos

| Archivo | Responsabilidad | Tarea que lo crea |
|---|---|---|
| `lib/config.sh` | Parsear `routes.conf` a registros. Nada más. | 3 |
| `lib/resolve.sh` | Cargar/validar los registros y responder `directorio → perfil`. | 4, 5, 6 |
| `lib/identity.py` | Extraer `oauthAccount.emailAddress` de un JSON. | 7 |
| `lib/identity.sh` | Envolver lo anterior: elegir archivo, traducir errores. | 7 |
| `lib/expiry.py` | Extraer solo `claudeAiOauth.expiresAt`. Nunca lee tokens. | 12 |
| `lib/ghostty.sh` | Emitir OSC 2 / 11 / 111 y sanear el título. Único emisor de escapes. | 8 |
| `bin/claude-account` | CLI: `_surface`, `_launch-check`, `which`, `routes`, status, `login`, `check`, `mark`. | 9–12 |
| `shell/router.zsh` | Hooks `precmd`/`zshexit` y la función `claude()`. | 13, 14 |
| `install.sh` | Instalación idempotente y `--uninstall`. | 15 |
| `tests/helper.bash` | Fixtures compartidas de los tests. | 1 |

---

### Task 1: Bootstrap del repositorio y arnés de tests

**Files:**
- Create: `~/repos/claude-ghostty-router/.gitignore`
- Create: `~/repos/claude-ghostty-router/README.md`
- Create: `~/repos/claude-ghostty-router/tests/helper.bash`
- Create: `~/repos/claude-ghostty-router/tests/smoke.bats`

- [ ] **Step 1: Instalar bats-core**

```bash
brew install bats-core
bats --version
```
Expected: `Bats 1.x.y`

- [ ] **Step 2: Crear el .gitignore**

```
.DS_Store
*.bak
tests/tmp/
```

- [ ] **Step 3: Crear el helper de tests**

Archivo `tests/helper.bash`:

```bash
# Fixtures compartidas por todos los tests.
# Cada test corre con un HOME propio y desechable: nada toca la máquina real.

CAR_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export CAR_ROOT

# Prepara un HOME falso y la ruta de una routes.conf de prueba.
setup_fixture() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export CAR_CONF="$BATS_TEST_TMPDIR/routes.conf"
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
```

- [ ] **Step 4: Escribir un test de humo que falle**

Archivo `tests/smoke.bats`:

```bash
setup() {
  load helper
  setup_fixture
}

@test "el helper crea un HOME desechable" {
  [ -d "$HOME" ]
  [[ "$HOME" == "$BATS_TEST_TMPDIR"* ]]
}

@test "make_profile escribe un archivo de identidad legible" {
  make_profile ".claude-test" "alguien@example.com"
  run grep -c "alguien@example.com" "$HOME/.claude-test/.claude.json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}
```

- [ ] **Step 5: Correr los tests**

```bash
cd ~/repos/claude-ghostty-router && bats tests/
```
Expected: `2 tests, 0 failures`

- [ ] **Step 6: Escribir el README**

Archivo `README.md`:

```markdown
# claude-ghostty-router

Enruta cada carpeta a la cuenta Claude que le corresponde, dentro de Ghostty.

- Cada tab muestra en su título y en su color de fondo a qué cuenta pertenece.
- Si la cuenta logueada no es la esperada para esa carpeta, **Claude no arranca**.
- Fuera de Ghostty todo se comporta como siempre.

Diseño: `docs/superpowers/specs/2026-09-01-claude-ghostty-router-design.md`

## Instalación

    ./install.sh

## Uso

    claude-account          # estado de perfiles y del directorio actual
    claude-account routes   # mapa carpeta -> perfil
    claude-account check    # diagnóstico completo
    claude-account login work
```

- [ ] **Step 7: Commit**

```bash
git add .gitignore README.md tests/
git commit -m "chore: estructura del repo y arnés de tests con bats"
```

---

### Task 2: Fase 0 — dónde vive el archivo de identidad

El diseño asume que con `CLAUDE_CONFIG_DIR=<dir>` la identidad queda en `<dir>/.claude.json`, pero el perfil actual la tiene en `~/.claude.json`, *fuera* del directorio. Hay que comprobarlo antes de codificar `identity.sh`. El código soportará ambos layouts igual; el experimento decide cuál se documenta como el real.

**Files:**
- Create: `docs/experiments/2026-09-01-identity-layout.md`

- [ ] **Step 1: Sondear con un CLAUDE_CONFIG_DIR desechable**

```bash
probe=$(mktemp -d)
CLAUDE_CONFIG_DIR="$probe" claude --version >/dev/null 2>&1
echo "--- dentro de $probe ---"; ls -la "$probe"
echo "--- hermano ---"; ls -la "$probe.json" 2>/dev/null || echo "(no existe)"
```
Expected: una de dos — o aparece `$probe/.claude.json`, o no aparece nada (Claude no escribe config al pedir la versión).

- [ ] **Step 2: Si el paso 1 no escribió nada, sondear con un comando que sí inicializa**

```bash
CLAUDE_CONFIG_DIR="$probe" claude mcp list >/dev/null 2>&1
ls -la "$probe"; ls -la "$probe.json" 2>/dev/null || echo "(no existe)"
```
Expected: aparece `$probe/.claude.json` (posiblemente sin `oauthAccount`, porque ese perfil no tiene sesión).

- [ ] **Step 3: Registrar el resultado**

Archivo `docs/experiments/2026-09-01-identity-layout.md` — rellenar con lo observado:

```markdown
# Layout del archivo de identidad con CLAUDE_CONFIG_DIR

**Fecha:** 2026-09-01
**Pregunta:** con `CLAUDE_CONFIG_DIR=<dir>`, ¿dónde escribe Claude Code `oauthAccount`?

## Comandos

    probe=$(mktemp -d)
    CLAUDE_CONFIG_DIR="$probe" claude --version
    CLAUDE_CONFIG_DIR="$probe" claude mcp list

## Observado

<pegar aquí la salida real de `ls -la`>

## Conclusión

Layout: `<dir>/.claude.json` | `<dir>.json` | (indeterminado, no escribe sin login)

## Consecuencia

`identity.sh` prueba `<dir>/.claude.json` y luego `<dir>.json`, en ese orden.
El experimento confirma cuál se encuentra en la práctica; el código funciona con ambos.
```

- [ ] **Step 4: Limpiar el sondeo**

```bash
rm -rf "$probe" "$probe.json"
```

- [ ] **Step 5: Commit**

```bash
git add docs/experiments/
git commit -m "docs: experimento del layout del archivo de identidad"
```

---

### Task 3: `lib/config.sh` — parseo de routes.conf

**Files:**
- Create: `lib/config.sh`
- Test: `tests/config.bats`

- [ ] **Step 1: Escribir los tests que fallan**

Archivo `tests/config.bats`:

```bash
setup() {
  load helper
  setup_fixture
  source "$CAR_ROOT/lib/config.sh"
}

@test "parsea un perfil completo y expande ~" {
  write_conf "profile work ~/.claude-work *@empresa.com #171b12"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'profile\twork\t%s/.claude-work\t*@empresa.com\t#171b12' "$HOME")" ]
}

@test "los campos opcionales quedan en guion" {
  write_conf "profile personal ~/.claude"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'profile\tpersonal\t%s/.claude\t-\t-' "$HOME")" ]
}

@test "ignora comentarios de linea completa, lineas vacias y espacios sobrantes" {
  write_conf "# comentario" "" "   # comentario indentado" "   profile personal ~/.claude   " "  "
  run config_parse "$CAR_CONF"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'profile\tpersonal\t%s/.claude\t-\t-' "$HOME")" ]
}

@test "un # a media linea es parte del campo, no un comentario" {
  # Sin esto, el color #171b12 se perderia al recortar el comentario.
  write_conf "profile work ~/.claude-work *@empresa.com #171b12"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"#171b12" ]]
}

@test "parsea rutas conservando el glob sin expandir" {
  write_conf "profile work ~/.claude-work" "route ~/repos/sotos-* work"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(printf 'route\t%s/repos/sotos-*\twork' "$HOME")" ]]
}

@test "rechaza una directiva desconocida indicando la linea" {
  write_conf "profile personal ~/.claude" "profil work ~/.claude-work"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"linea 2"* ]]
  [[ "$output" == *"profil"* ]]
}

@test "rechaza un perfil sin directorio" {
  write_conf "profile work"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"linea 1"* ]]
}

@test "rechaza un color mal formado" {
  write_conf "profile work ~/.claude-work *@empresa.com rojo"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"color"* ]]
}

@test "rechaza una ruta sin perfil" {
  write_conf "profile work ~/.claude-work" "route ~/repos/algo"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 2 ]
}

@test "rechaza campos de mas" {
  write_conf "profile work ~/.claude-work *@empresa.com #171b12 sobra"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 2 ]
}

@test "un archivo ilegible es un error de config" {
  run config_parse "$BATS_TEST_TMPDIR/no-existe.conf"
  [ "$status" -eq 2 ]
}
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

```bash
bats tests/config.bats
```
Expected: FAIL — `lib/config.sh: No such file or directory`

- [ ] **Step 3: Escribir la implementación**

Archivo `lib/config.sh`:

```bash
# Parseo de routes.conf. Sin efectos secundarios: entra un archivo, salen registros.
# Compatible con bash 3.2 (el /bin/bash de macOS).

CAR_OK=0
CAR_ECONFIG=2      # routes.conf invalido o ilegible
CAR_ENOSESSION=3   # perfil sin sesion iniciada
CAR_EJSON=4        # archivo de identidad corrupto
CAR_EMISMATCH=5    # email logueado != glob esperado
CAR_ENODIR=6       # config-dir del perfil no existe
CAR_ENOPYTHON=7    # python3 ausente

# Expande un ~ inicial. No toca nada mas: los globs se conservan sin expandir,
# porque el matching de rutas se hace despues con `case`.
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
```

- [ ] **Step 4: Correr los tests**

```bash
bats tests/config.bats && shellcheck -s bash lib/config.sh
```
Expected: `11 tests, 0 failures` y shellcheck sin salida

- [ ] **Step 5: Commit**

```bash
git add lib/config.sh tests/config.bats
git commit -m "feat: parseo de routes.conf con validacion de sintaxis"
```

---

### Task 4: `lib/resolve.sh` — carga y validación de la configuración

**Files:**
- Create: `lib/resolve.sh`
- Test: `tests/load.bats`

- [ ] **Step 1: Escribir los tests que fallan**

Archivo `tests/load.bats`:

```bash
setup() {
  load helper
  setup_fixture
  source "$CAR_ROOT/lib/config.sh"
  source "$CAR_ROOT/lib/resolve.sh"
}

@test "carga perfiles y rutas en arrays paralelos" {
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/uno work"
  car_load_config "$CAR_CONF"
  [ "${#CAR_P_NAME[@]}" -eq 2 ]
  [ "${CAR_P_NAME[0]}" = "personal" ]
  [ "${CAR_P_DIR[1]}" = "$HOME/.claude-work" ]
  [ "${CAR_P_GLOB[1]}" = "*@empresa.com" ]
  [ "${CAR_P_COLOR[1]}" = "#171b12" ]
  [ "${#CAR_R_PATH[@]}" -eq 1 ]
  [ "${CAR_R_PROFILE[0]}" = "work" ]
}

@test "rechaza una ruta que apunta a un perfil inexistente" {
  write_conf "profile personal ~/.claude" "route ~/repos/uno fantasma"
  run car_load_config "$CAR_CONF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"fantasma"* ]]
}

@test "rechaza perfiles duplicados" {
  write_conf "profile personal ~/.claude" "profile personal ~/.otro"
  run car_load_config "$CAR_CONF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"duplicado"* ]]
}

@test "rechaza una config sin ningun perfil" {
  write_conf "# solo comentarios"
  run car_load_config "$CAR_CONF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ningun perfil"* ]]
}

@test "propaga el error de sintaxis del parser" {
  write_conf "basura aqui"
  run car_load_config "$CAR_CONF"
  [ "$status" -eq 2 ]
}
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

```bash
bats tests/load.bats
```
Expected: FAIL — `lib/resolve.sh: No such file or directory`

- [ ] **Step 3: Escribir la implementación**

Archivo `lib/resolve.sh`:

```bash
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
```

- [ ] **Step 4: Correr los tests**

```bash
bats tests/load.bats && shellcheck -s bash lib/resolve.sh
```
Expected: `5 tests, 0 failures` y shellcheck sin salida

- [ ] **Step 5: Commit**

```bash
git add lib/resolve.sh tests/load.bats
git commit -m "feat: carga y validacion de perfiles y rutas"
```

---

### Task 5: `lib/resolve.sh` — resolución por ruta

**Files:**
- Modify: `lib/resolve.sh` (añadir `resolve_route` y `car_emit_profile`)
- Test: `tests/resolve.bats`

- [ ] **Step 1: Escribir los tests que fallan**

Archivo `tests/resolve.bats`:

```bash
setup() {
  load helper
  setup_fixture
  source "$CAR_ROOT/lib/config.sh"
  source "$CAR_ROOT/lib/resolve.sh"
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/proyecto-uno/interno personal" \
    "route ~/repos/proyecto-uno work" \
    "route ~/repos/sotos-* work"
  car_load_config "$CAR_CONF"
}

# resolve_route imprime: perfil<TAB>proyecto<TAB>dir<TAB>glob<TAB>color

@test "coincidencia exacta de ruta" {
  mkdir -p "$HOME/repos/proyecto-uno"
  run resolve_route "$HOME/repos/proyecto-uno"
  [ "$status" -eq 0 ]
  [[ "$output" == work$'\t'proyecto-uno$'\t'* ]]
}

@test "un subdirectorio hereda la ruta del padre" {
  mkdir -p "$HOME/repos/proyecto-uno/src/hondo"
  run resolve_route "$HOME/repos/proyecto-uno/src/hondo"
  [ "$status" -eq 0 ]
  [[ "$output" == work$'\t'* ]]
}

@test "la primera ruta declarada gana: la excepcion anidada" {
  mkdir -p "$HOME/repos/proyecto-uno/interno"
  run resolve_route "$HOME/repos/proyecto-uno/interno"
  [ "$status" -eq 0 ]
  [[ "$output" == personal$'\t'* ]]
}

@test "los globs de ruta funcionan" {
  mkdir -p "$HOME/repos/sotos-chat/sub"
  run resolve_route "$HOME/repos/sotos-chat/sub"
  [ "$status" -eq 0 ]
  [[ "$output" == work$'\t'* ]]
}

@test "sin coincidencia cae al primer perfil declarado" {
  mkdir -p "$HOME/otro/sitio"
  run resolve_route "$HOME/otro/sitio"
  [ "$status" -eq 0 ]
  [[ "$output" == personal$'\t'sitio$'\t'* ]]
}

@test "emite el dir, el glob y el color del perfil resuelto" {
  mkdir -p "$HOME/repos/proyecto-uno"
  run resolve_route "$HOME/repos/proyecto-uno"
  [ "$output" = "$(printf 'work\tproyecto-uno\t%s/.claude-work\t*@empresa.com\t#171b12' "$HOME")" ]
}

@test "el proyecto de una ruta con glob sale del directorio, no del patron" {
  mkdir -p "$HOME/repos/sotos-chat"
  run resolve_route "$HOME/repos/sotos-chat"
  [[ "$output" == work$'\t'sotos-chat$'\t'* ]]
}
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

```bash
bats tests/resolve.bats
```
Expected: FAIL — `resolve_route: command not found`

- [ ] **Step 3: Añadir la implementación al final de `lib/resolve.sh`**

```bash
# car_emit_profile <perfil> <etiqueta-proyecto>
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
```

- [ ] **Step 4: Correr los tests**

```bash
bats tests/resolve.bats && shellcheck -s bash lib/resolve.sh
```
Expected: `7 tests, 0 failures`. Si shellcheck marca SC2254 (`$route` sin comillas en `case`), añadir `# shellcheck disable=SC2254` sobre el `case`: el glob sin comillas es intencional.

- [ ] **Step 5: Commit**

```bash
git add lib/resolve.sh tests/resolve.bats
git commit -m "feat: resolucion de perfil por prefijo de ruta y glob"
```

---

### Task 6: `lib/resolve.sh` — fallback por repositorio git y worktrees

**Files:**
- Modify: `lib/resolve.sh` (reescribir `resolve_route`)
- Test: `tests/resolve_git.bats`

- [ ] **Step 1: Escribir los tests que fallan**

Archivo `tests/resolve_git.bats`:

```bash
setup() {
  load helper
  setup_fixture
  source "$CAR_ROOT/lib/config.sh"
  source "$CAR_ROOT/lib/resolve.sh"
}

@test "un repo clonado fuera de la ruta se resuelve por su raiz" {
  make_repo "$HOME/repos/miapp"
  mkdir -p "$HOME/repos/miapp/src"
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/miapp work"
  car_load_config "$CAR_CONF"
  run resolve_route "$HOME/repos/miapp/src"
  [ "$status" -eq 0 ]
  [[ "$output" == work$'\t'miapp$'\t'* ]]
}

@test "un worktree en otro disco sigue al repositorio principal" {
  make_repo "$HOME/repos/miapp"
  git -C "$HOME/repos/miapp" worktree add -q -b rama "$HOME/scratch/rama-suelta"
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/miapp work"
  car_load_config "$CAR_CONF"
  run resolve_route "$HOME/scratch/rama-suelta"
  [ "$status" -eq 0 ]
  [[ "$output" == work$'\t'* ]]
}

@test "la etiqueta de proyecto es la raiz del repo, no el subdirectorio" {
  make_repo "$HOME/repos/miapp"
  mkdir -p "$HOME/repos/miapp/src/hondo"
  write_conf "profile personal ~/.claude tu-email@ejemplo.com -"
  car_load_config "$CAR_CONF"
  run resolve_route "$HOME/repos/miapp/src/hondo"
  [[ "$output" == personal$'\t'miapp$'\t'* ]]
}

@test "fuera de un repo la etiqueta es el basename del directorio" {
  mkdir -p "$HOME/notas/varias"
  write_conf "profile personal ~/.claude tu-email@ejemplo.com -"
  car_load_config "$CAR_CONF"
  run resolve_route "$HOME/notas/varias"
  [[ "$output" == personal$'\t'varias$'\t'* ]]
}

@test "un directorio inexistente no revienta y cae al perfil por defecto" {
  write_conf "profile personal ~/.claude tu-email@ejemplo.com -"
  car_load_config "$CAR_CONF"
  run resolve_route "$HOME/no/existe"
  [ "$status" -eq 0 ]
  [[ "$output" == personal$'\t'* ]]
}
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

```bash
bats tests/resolve_git.bats
```
Expected: FAIL — el worktree y la etiqueta por raíz de repo dan `personal`/etiqueta equivocada

- [ ] **Step 3: Reemplazar `resolve_route` en `lib/resolve.sh`**

Sustituir la función `resolve_route` completa por esta versión:

```bash
# car_git_root <directorio> -> raiz del arbol de trabajo, o cadena vacia
car_git_root() {
  git -C "$1" rev-parse --show-toplevel 2>/dev/null || printf ''
}

# car_git_main <directorio> -> raiz del repositorio principal.
# En un worktree, --git-common-dir es absoluto y apunta al .git del repo original.
car_git_main() {
  local common
  common="$(git -C "$1" rev-parse --git-common-dir 2>/dev/null)" || return 1
  case "$common" in
    /*) dirname "$common" ;;
    *)  return 1 ;;
  esac
}

# resolve_route <directorio>
# -> perfil<TAB>proyecto<TAB>config-dir<TAB>email-glob<TAB>color
#
# Candidatos, en orden: el directorio, la raiz de su repo, el repo principal
# (que difiere solo en worktrees). El primero que case una ruta gana.
resolve_route() {
  local dir="$1" root main label cand profile
  root="$(car_git_root "$dir")"
  if [ -n "$root" ]; then
    label="$(basename "$root")"
    main="$(car_git_main "$dir")" || main=""
  else
    label="$(basename "$dir")"
    main=""
  fi

  for cand in "$dir" "$root" "$main"; do
    [ -n "$cand" ] || continue
    if profile="$(car_match_dir "$cand")"; then
      car_emit_profile "$profile" "$label"
      return $?
    fi
  done

  car_emit_profile "${CAR_P_NAME[0]}" "$label"
}
```

- [ ] **Step 4: Correr todos los tests de resolución**

```bash
bats tests/resolve.bats tests/resolve_git.bats && shellcheck -s bash lib/resolve.sh
```
Expected: `12 tests, 0 failures` — los siete de la Task 5 siguen pasando

- [ ] **Step 5: Commit**

```bash
git add lib/resolve.sh tests/resolve_git.bats
git commit -m "feat: fallback de resolucion por raiz de repo y worktrees"
```

---

### Task 7: `lib/identity.py` y `lib/identity.sh` — email logueado

**Files:**
- Create: `lib/identity.py`
- Create: `lib/identity.sh`
- Test: `tests/identity.bats`

- [ ] **Step 1: Escribir los tests que fallan**

Archivo `tests/identity.bats`:

```bash
setup() {
  load helper
  setup_fixture
  source "$CAR_ROOT/lib/config.sh"
  source "$CAR_ROOT/lib/identity.sh"
}

@test "lee el email del layout interno (<dir>/.claude.json)" {
  make_profile ".claude-work" "ricardo@empresa.com"
  run identity_email "$HOME/.claude-work"
  [ "$status" -eq 0 ]
  [ "$output" = "ricardo@empresa.com" ]
}

@test "lee el email del layout hermano (<dir>.json)" {
  mkdir -p "$HOME/.claude"
  printf '{"oauthAccount":{"emailAddress":"tu-email@ejemplo.com"}}\n' > "$HOME/.claude.json"
  run identity_email "$HOME/.claude"
  [ "$status" -eq 0 ]
  [ "$output" = "tu-email@ejemplo.com" ]
}

@test "el layout interno gana sobre el hermano" {
  make_profile ".claude" "interno@example.com"
  printf '{"oauthAccount":{"emailAddress":"hermano@example.com"}}\n' > "$HOME/.claude.json"
  run identity_email "$HOME/.claude"
  [ "$output" = "interno@example.com" ]
}

@test "un directorio de perfil inexistente es error 6" {
  run identity_email "$HOME/.no-existe"
  [ "$status" -eq 6 ]
  [[ "$output" == *"no existe"* ]]
}

@test "un perfil sin archivo de identidad es error 3" {
  make_profile ".claude-work"
  run identity_email "$HOME/.claude-work"
  [ "$status" -eq 3 ]
  [[ "$output" == *"sin sesion"* ]]
}

@test "un archivo sin oauthAccount es error 3" {
  mkdir -p "$HOME/.claude-work"
  printf '{"numStartups": 3}\n' > "$HOME/.claude-work/.claude.json"
  run identity_email "$HOME/.claude-work"
  [ "$status" -eq 3 ]
}

@test "un email vacio es error 3" {
  mkdir -p "$HOME/.claude-work"
  printf '{"oauthAccount":{"emailAddress":""}}\n' > "$HOME/.claude-work/.claude.json"
  run identity_email "$HOME/.claude-work"
  [ "$status" -eq 3 ]
}

@test "un JSON corrupto es error 4" {
  mkdir -p "$HOME/.claude-work"
  printf '{roto\n' > "$HOME/.claude-work/.claude.json"
  run identity_email "$HOME/.claude-work"
  [ "$status" -eq 4 ]
  [[ "$output" == *"ilegible"* ]]
}

@test "sin python3 no se puede verificar: error 7" {
  make_profile ".claude-work" "ricardo@empresa.com"
  mkdir -p "$BATS_TEST_TMPDIR/sin-nada"
  local guardado="$PATH"
  PATH="$BATS_TEST_TMPDIR/sin-nada"
  run identity_email "$HOME/.claude-work"
  PATH="$guardado"
  [ "$status" -eq 7 ]
  [[ "$output" == *"python3"* ]]
}

@test "identity_matches acepta el glob que corresponde" {
  run identity_matches "ricardo@empresa.com" "*@empresa.com"
  [ "$status" -eq 0 ]
}

@test "identity_matches rechaza el glob que no corresponde" {
  run identity_matches "tu-email@ejemplo.com" "*@empresa.com"
  [ "$status" -eq 5 ]
}

@test "el glob '-' significa no verificar" {
  run identity_matches "cualquiera@example.com" "-"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

```bash
bats tests/identity.bats
```
Expected: FAIL — `lib/identity.sh: No such file or directory`

- [ ] **Step 3: Escribir el lector de JSON**

Archivo `lib/identity.py`:

```python
#!/usr/bin/env python3
"""Imprime oauthAccount.emailAddress del archivo de identidad de un perfil.

Nunca lee ni imprime tokens: solo ese campo.
Codigos de salida: 0 ok, 3 sin sesion, 4 archivo ilegible o corrupto.
"""

import json
import sys

EXIT_OK = 0
EXIT_NO_SESSION = 3
EXIT_BAD_JSON = 4


def main() -> int:
    if len(sys.argv) != 2:
        return EXIT_BAD_JSON
    try:
        with open(sys.argv[1], "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return EXIT_BAD_JSON
    if not isinstance(data, dict):
        return EXIT_BAD_JSON
    account = data.get("oauthAccount")
    if not isinstance(account, dict):
        return EXIT_NO_SESSION
    email = account.get("emailAddress")
    if not isinstance(email, str) or not email:
        return EXIT_NO_SESSION
    print(email)
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Escribir el envoltorio shell**

Archivo `lib/identity.sh`:

```bash
# Lectura de la identidad de un perfil. Requiere lib/config.sh cargado.

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
```

- [ ] **Step 5: Correr los tests**

```bash
bats tests/identity.bats && shellcheck -s bash lib/identity.sh && python3 -m py_compile lib/identity.py
```
Expected: `12 tests, 0 failures`, shellcheck limpio, compilación de python sin errores

- [ ] **Step 6: Commit**

```bash
git add lib/identity.py lib/identity.sh tests/identity.bats
git commit -m "feat: lectura del email logueado por perfil, con ambos layouts"
```

---

### Task 8: `lib/ghostty.sh` — secuencias OSC y saneo del título

**Files:**
- Create: `lib/ghostty.sh`
- Test: `tests/ghostty.bats`

- [ ] **Step 1: Escribir los tests que fallan**

Archivo `tests/ghostty.bats`:

```bash
setup() {
  load helper
  setup_fixture
  source "$CAR_ROOT/lib/config.sh"
  source "$CAR_ROOT/lib/ghostty.sh"
}

@test "el titulo sale como OSC 2 terminado en BEL" {
  run ghostty_title "work · proyecto"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]2;work · proyecto\007')" ]
}

@test "el separador UTF-8 sobrevive al saneo" {
  # bash 3.2 y los multibyte no siempre se llevan bien: si este test falla,
  # cambia el separador a ASCII en cmd_surface (" - ") y ajusta los tests.
  run ghostty_title "work · proyecto"
  [[ "$output" == *"·"* ]]
}

@test "el titulo elimina bytes de control" {
  run ghostty_title "$(printf 'mal\033]0;inyectado\007nombre')"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]2;mal]0;inyectadonombre\007')" ]
}

@test "el titulo se recorta a 60 caracteres" {
  local largo
  largo="$(printf 'x%.0s' $(seq 1 200))"
  run ghostty_title "$largo"
  [ "${#output}" -eq 65 ]   # ESC ] 2 ; + 60 caracteres + BEL
}

@test "un color valido sale como OSC 11" {
  run ghostty_bg "#171b12"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]11;#171b12\007')" ]
}

@test "el guion resetea el fondo con OSC 111" {
  run ghostty_bg "-"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]111\007')" ]
}

@test "un color invalido no emite nada y falla" {
  run ghostty_bg "rojo; rm -rf /"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "un color con longitud incorrecta falla" {
  run ghostty_bg "#abc"
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

```bash
bats tests/ghostty.bats
```
Expected: FAIL — `lib/ghostty.sh: No such file or directory`

- [ ] **Step 3: Escribir la implementación**

Archivo `lib/ghostty.sh`:

```bash
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
```

- [ ] **Step 4: Correr los tests**

```bash
bats tests/ghostty.bats && shellcheck -s bash lib/ghostty.sh
```
Expected: `8 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add lib/ghostty.sh tests/ghostty.bats
git commit -m "feat: emision de OSC 2/11/111 con saneo del titulo"
```

---

### Task 9: `bin/claude-account _surface` — pintado de una superficie

**Files:**
- Create: `bin/claude-account`
- Test: `tests/surface.bats`

- [ ] **Step 1: Escribir los tests que fallan**

Archivo `tests/surface.bats`:

```bash
setup() {
  load helper
  setup_fixture
  CA="$CAR_ROOT/bin/claude-account"
}

@test "pinta titulo y color del perfil resuelto" {
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/miapp work"
  mkdir -p "$HOME/repos/miapp"
  run "$CA" _surface "$HOME/repos/miapp"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]2;work · miapp\007\033]11;#171b12\007')" ]
}

@test "el perfil por defecto resetea el fondo" {
  write_conf "profile personal ~/.claude tu-email@ejemplo.com -"
  mkdir -p "$HOME/notas"
  run "$CA" _surface "$HOME/notas"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]2;personal · notas\007\033]111\007')" ]
}

@test "funciona invocado a traves de un symlink" {
  # Asi es como se instala: ~/.local/bin/claude-account -> repo/bin/claude-account.
  # Si el CLI no resuelve el symlink, no encuentra sus propias librerias.
  write_conf "profile personal ~/.claude tu-email@ejemplo.com -"
  mkdir -p "$HOME/.local/bin" "$HOME/notas"
  ln -sf "$CA" "$HOME/.local/bin/claude-account"
  run "$HOME/.local/bin/claude-account" _surface "$HOME/notas"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]2;personal · notas\007\033]111\007')" ]
}

@test "sin routes.conf no pinta nada y sale con exito" {
  rm -f "$CAR_CONF"
  run "$CA" _surface "$HOME"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "con routes.conf roto avisa en el titulo pero no falla" {
  write_conf "basura aqui"
  run "$CA" _surface "$HOME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"routes.conf invalido"* ]]
  [[ "$output" == *"$(printf '\033]111\007')" ]]
}
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

```bash
bats tests/surface.bats
```
Expected: FAIL — `bin/claude-account: No such file or directory`

- [ ] **Step 3: Escribir el esqueleto del CLI con `_surface`**

Archivo `bin/claude-account` (marcar ejecutable en el paso 4):

```bash
#!/usr/bin/env bash
# claude-account — inspeccion y control del enrutado de cuentas Claude.
set -u

# Se instala como symlink en ~/.local/bin, y macOS no tiene `readlink -f`:
# hay que seguir la cadena a mano para encontrar las librerias del repo.
car_self="${BASH_SOURCE[0]}"
while [ -L "$car_self" ]; do
  car_link_dir="$(cd "$(dirname "$car_self")" && pwd)"
  car_self="$(readlink "$car_self")"
  case "$car_self" in
    /*) ;;
    *) car_self="$car_link_dir/$car_self" ;;
  esac
done
CAR_ROOT_DIR="$(cd "$(dirname "$car_self")/.." && pwd)"

. "$CAR_ROOT_DIR/lib/config.sh"
. "$CAR_ROOT_DIR/lib/resolve.sh"
. "$CAR_ROOT_DIR/lib/identity.sh"
. "$CAR_ROOT_DIR/lib/ghostty.sh"

CAR_CONF="${CAR_CONF:-$HOME/.config/claude-ghostty-router/routes.conf}"

# _surface <directorio>
# Emite los escapes que marcan esta superficie. Nunca falla: el pintado informa,
# no decide. Un routes.conf roto se ve en el titulo; quien bloquea es el shim.
cmd_surface() {
  local dir="${1:-$PWD}" record profile label pdir pglob color

  [ -f "$CAR_CONF" ] || return 0

  if ! car_load_config "$CAR_CONF" 2>/dev/null; then
    ghostty_title "⚠ routes.conf invalido"
    ghostty_bg "-"
    return 0
  fi

  if ! record="$(resolve_route "$dir" 2>/dev/null)"; then
    ghostty_title "⚠ routes.conf invalido"
    ghostty_bg "-"
    return 0
  fi

  IFS=$'\t' read -r profile label pdir pglob color <<< "$record"
  ghostty_title "$profile · $label"
  ghostty_bg "$color" || ghostty_bg "-"
  return 0
}

main() {
  local command="${1:-status}"
  shift || true
  case "$command" in
    _surface) cmd_surface "$@" ;;
    *)
      echo "claude-account: comando desconocido '$command'" >&2
      return 1
      ;;
  esac
}

main "$@"
```

- [ ] **Step 4: Hacerlo ejecutable y correr los tests**

```bash
chmod +x bin/claude-account
bats tests/surface.bats && shellcheck -s bash bin/claude-account
```
Expected: `5 tests, 0 failures`. Shellcheck marcará `pdir`/`pglob` como asignadas y no usadas (SC2034): son los campos del registro que este comando no necesita; añadir `# shellcheck disable=SC2034` sobre el `read`.

- [ ] **Step 5: Commit**

```bash
git add bin/claude-account tests/surface.bats
git commit -m "feat: comando _surface que pinta la superficie actual"
```

---

### Task 10: `bin/claude-account _launch-check` — la verificación fail-closed

Es el corazón del proyecto: la única pieza autorizada a impedir que Claude arranque.

**Files:**
- Modify: `bin/claude-account` (añadir `cmd_launch_check` y su entrada en `main`)
- Test: `tests/launch_check.bats`

- [ ] **Step 1: Escribir los tests que fallan**

Archivo `tests/launch_check.bats`:

```bash
setup() {
  load helper
  setup_fixture
  CA="$CAR_ROOT/bin/claude-account"
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/miapp work"
  mkdir -p "$HOME/repos/miapp" "$HOME/notas"
}

@test "cuenta correcta: imprime el config-dir y sale con 0" {
  make_profile ".claude-work" "ricardo@empresa.com"
  run "$CA" _launch-check "$HOME/repos/miapp"
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.claude-work" ]
}

@test "cuenta equivocada: bloquea con 5 y dice como arreglarlo" {
  make_profile ".claude-work" "tu-email@ejemplo.com"
  run "$CA" _launch-check "$HOME/repos/miapp"
  [ "$status" -eq 5 ]
  [[ "$output" == *"*@empresa.com"* ]]
  [[ "$output" == *"tu-email@ejemplo.com"* ]]
  [[ "$output" == *"claude-account login work"* ]]
}

@test "perfil sin sesion: bloquea con 3" {
  make_profile ".claude-work"
  run "$CA" _launch-check "$HOME/repos/miapp"
  [ "$status" -eq 3 ]
  [[ "$output" == *"claude-account login work"* ]]
}

@test "config-dir inexistente: bloquea con 6" {
  run "$CA" _launch-check "$HOME/repos/miapp"
  [ "$status" -eq 6 ]
  [[ "$output" == *"no existe"* ]]
}

@test "routes.conf roto: bloquea con 2 y señala la linea" {
  write_conf "profile personal ~/.claude" "basura aqui"
  run "$CA" _launch-check "$HOME/repos/miapp"
  [ "$status" -eq 2 ]
  [[ "$output" == *"linea 2"* ]]
}

@test "sin routes.conf: paso directo, sin config-dir y sin error" {
  rm -f "$CAR_CONF"
  run "$CA" _launch-check "$HOME/repos/miapp"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "perfil sin glob de email: no verifica y devuelve su config-dir" {
  write_conf "profile personal ~/.claude - -" "route ~/notas personal"
  make_profile ".claude"
  run "$CA" _launch-check "$HOME/notas"
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.claude" ]
}

@test "el perfil por defecto tambien se verifica" {
  make_profile ".claude" "otro@gmail.com"
  run "$CA" _launch-check "$HOME/notas"
  [ "$status" -eq 5 ]
  [[ "$output" == *"claude-account login personal"* ]]
}
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

```bash
bats tests/launch_check.bats
```
Expected: FAIL — `comando desconocido '_launch-check'`

- [ ] **Step 3: Añadir `cmd_launch_check` a `bin/claude-account`**

Insertar antes de la función `main`:

```bash
# _launch-check <directorio>
# Exito: imprime el config-dir verificado (o nada si no hay routes.conf).
# Fallo: explica en stderr y devuelve el codigo del motivo. Sin excepciones:
# si no se puede verificar, no se arranca.
cmd_launch_check() {
  local dir="${1:-$PWD}" record profile label config_dir glob color email status

  [ -f "$CAR_CONF" ] || return 0

  car_load_config "$CAR_CONF" || return $CAR_ECONFIG
  record="$(resolve_route "$dir")" || return $CAR_ECONFIG
  # shellcheck disable=SC2034
  IFS=$'\t' read -r profile label config_dir glob color <<< "$record"

  if [ "$glob" = "-" ]; then
    printf '%s' "$config_dir"
    return 0
  fi

  email="$(identity_email "$config_dir")"
  status=$?
  if [ $status -ne 0 ]; then
    echo "claude-account: no arranco Claude en $label (perfil '$profile')." >&2
    echo "  Arregla la sesion con: claude-account login $profile" >&2
    return $status
  fi

  if ! identity_matches "$email" "$glob"; then
    echo "claude-account: cuenta equivocada para $label (perfil '$profile')." >&2
    echo "  esperaba: $glob" >&2
    echo "  logueada: $email" >&2
    echo "  Arreglalo con: claude-account login $profile" >&2
    return $CAR_EMISMATCH
  fi

  printf '%s' "$config_dir"
  return 0
}
```

Y añadir la rama al `case` de `main`, justo después de `_surface`:

```bash
    _launch-check) cmd_launch_check "$@" ;;
```

- [ ] **Step 4: Correr los tests**

```bash
bats tests/launch_check.bats && shellcheck -s bash bin/claude-account
```
Expected: `8 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add bin/claude-account tests/launch_check.bats
git commit -m "feat: verificacion fail-closed antes de arrancar Claude"
```

---

### Task 11: `bin/claude-account` — comandos humanos

**Files:**
- Modify: `bin/claude-account` (añadir `which`, `routes`, `status`, `login`, `mark`, `help`)
- Test: `tests/cli.bats`

- [ ] **Step 1: Escribir los tests que fallan**

Archivo `tests/cli.bats`:

```bash
setup() {
  load helper
  setup_fixture
  CA="$CAR_ROOT/bin/claude-account"
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/miapp work"
  mkdir -p "$HOME/repos/miapp"
}

@test "which imprime solo el nombre del perfil" {
  run "$CA" which "$HOME/repos/miapp"
  [ "$status" -eq 0 ]
  [ "$output" = "work" ]
}

@test "which sin argumento usa el directorio actual" {
  cd "$HOME/repos/miapp"
  run "$CA" which
  [ "$output" = "work" ]
}

@test "routes lista las rutas con su perfil" {
  run "$CA" routes
  [ "$status" -eq 0 ]
  [[ "$output" == *"$HOME/repos/miapp"* ]]
  [[ "$output" == *"work"* ]]
}

@test "status muestra cada perfil con su email logueado" {
  make_profile ".claude" "tu-email@ejemplo.com"
  make_profile ".claude-work" "ricardo@empresa.com"
  cd "$HOME/repos/miapp"
  run "$CA"
  [ "$status" -eq 0 ]
  [[ "$output" == *"personal"* ]]
  [[ "$output" == *"tu-email@ejemplo.com"* ]]
  [[ "$output" == *"ricardo@empresa.com"* ]]
  [[ "$output" == *"work"* ]]
}

@test "status marca los perfiles sin sesion" {
  make_profile ".claude" "tu-email@ejemplo.com"
  run "$CA" status
  [[ "$output" == *"sin sesion"* ]]
}

@test "login exige un perfil existente" {
  run "$CA" login fantasma
  [ "$status" -eq 2 ]
  [[ "$output" == *"fantasma"* ]]
}

@test "login lanza claude con el CLAUDE_CONFIG_DIR del perfil" {
  make_profile ".claude-work"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/claude" <<'FALSO'
#!/bin/sh
echo "CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR"
FALSO
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  # El PATH se exporta antes de `run`: un prefijo VAR=x delante de una funcion
  # de shell no se comporta igual que delante de un comando externo.
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  run "$CA" login work
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLAUDE_CONFIG_DIR=$HOME/.claude-work"* ]]
}

@test "help lista los comandos" {
  run "$CA" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"routes"* ]]
  [[ "$output" == *"check"* ]]
}
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

```bash
bats tests/cli.bats
```
Expected: FAIL — `comando desconocido 'which'`

- [ ] **Step 3: Añadir los comandos a `bin/claude-account`**

Insertar antes de `main`:

```bash
cmd_which() {
  local dir="${1:-$PWD}" record profile label pdir pglob color
  car_load_config "$CAR_CONF" || return $CAR_ECONFIG
  record="$(resolve_route "$dir")" || return $CAR_ECONFIG
  # shellcheck disable=SC2034
  IFS=$'\t' read -r profile label pdir pglob color <<< "$record"
  printf '%s\n' "$profile"
}

cmd_routes() {
  local i
  car_load_config "$CAR_CONF" || return $CAR_ECONFIG
  if [ "${#CAR_R_PATH[@]}" -eq 0 ]; then
    echo "(sin rutas: todo cae en el perfil por defecto '${CAR_P_NAME[0]}')"
    return 0
  fi
  for ((i = 0; i < ${#CAR_R_PATH[@]}; i++)); do
    printf '%-50s %s\n' "${CAR_R_PATH[$i]}" "${CAR_R_PROFILE[$i]}"
  done
}

cmd_status() {
  local i email status record profile here pdir pglob color

  car_load_config "$CAR_CONF" || return $CAR_ECONFIG

  echo "Perfiles:"
  for ((i = 0; i < ${#CAR_P_NAME[@]}; i++)); do
    email="$(identity_email "${CAR_P_DIR[$i]}" 2>/dev/null)"
    status=$?
    if [ $status -eq 0 ]; then
      printf '  %-10s %-40s %s\n' "${CAR_P_NAME[$i]}" "${CAR_P_DIR[$i]}" "$email"
    else
      printf '  %-10s %-40s %s\n' "${CAR_P_NAME[$i]}" "${CAR_P_DIR[$i]}" "(sin sesion)"
    fi
  done

  record="$(resolve_route "$PWD")" || return $CAR_ECONFIG
  # shellcheck disable=SC2034
  IFS=$'\t' read -r profile here pdir pglob color <<< "$record"
  echo
  echo "Directorio actual: $here -> perfil '$profile'"
}

cmd_login() {
  local name="${1:-}" index dir
  if [ -z "$name" ]; then
    echo "claude-account: uso: claude-account login <perfil>" >&2
    return $CAR_ECONFIG
  fi
  car_load_config "$CAR_CONF" || return $CAR_ECONFIG
  if ! index="$(car_profile_index "$name")"; then
    echo "claude-account: no existe el perfil '$name' en $CAR_CONF" >&2
    return $CAR_ECONFIG
  fi
  dir="${CAR_P_DIR[$index]}"
  mkdir -p "$dir"
  echo "claude-account: abriendo Claude en el perfil '$name' ($dir)."
  echo "  Dentro, ejecuta /login para iniciar sesion. Luego sal con /exit."
  # Unico camino que no verifica, y tiene que serlo: su proposito es crear la
  # sesion que despues se verifica. Un perfil vacio nunca podria loguearse.
  CLAUDE_CONFIG_DIR="$dir" command claude
}

cmd_help() {
  cat <<'AYUDA'
claude-account — enrutado de cuentas Claude por carpeta, dentro de Ghostty

  claude-account                estado de los perfiles y del directorio actual
  claude-account routes         mapa carpeta -> perfil
  claude-account which [dir]    perfil de un directorio
  claude-account check          diagnostico completo
  claude-account login <perfil> inicia sesion en un perfil
  claude-account mark           repinta la superficie actual
AYUDA
}
```

Y ampliar el `case` de `main`:

```bash
    _surface)      cmd_surface "$@" ;;
    _launch-check) cmd_launch_check "$@" ;;
    which)         cmd_which "$@" ;;
    routes)        cmd_routes "$@" ;;
    status)        cmd_status "$@" ;;
    login)         cmd_login "$@" ;;
    mark)          cmd_surface "$PWD" ;;
    help|-h|--help) cmd_help ;;
```

- [ ] **Step 4: Correr los tests**

```bash
bats tests/cli.bats && shellcheck -s bash bin/claude-account
```
Expected: `8 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add bin/claude-account tests/cli.bats
git commit -m "feat: comandos which, routes, status, login y help"
```

---

### Task 12: `bin/claude-account check` — diagnóstico

**Files:**
- Create: `lib/expiry.py`
- Modify: `bin/claude-account` (añadir `cmd_check`)
- Test: `tests/check.bats`

- [ ] **Step 1: Escribir los tests que fallan**

Archivo `tests/check.bats`:

```bash
setup() {
  load helper
  setup_fixture
  CA="$CAR_ROOT/bin/claude-account"
  export CAR_GHOSTTY_CONF="$BATS_TEST_TMPDIR/config.ghostty"
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/miapp work"
}

@test "todo en orden sale con 0" {
  make_profile ".claude" "tu-email@ejemplo.com"
  make_profile ".claude-work" "ricardo@empresa.com"
  printf 'shell-integration-features = cursor,no-sudo,no-title,path\n' > "$CAR_GHOSTTY_CONF"
  export CAR_ROUTER_LOADED=1
  run "$CA" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"routes.conf valido"* ]]
}

@test "un perfil sin sesion hace fallar el check" {
  make_profile ".claude" "tu-email@ejemplo.com"
  make_profile ".claude-work"
  printf 'shell-integration-features = no-title\n' > "$CAR_GHOSTTY_CONF"
  export CAR_ROUTER_LOADED=1
  run "$CA" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"work"* ]]
  [[ "$output" == *"sin sesion"* ]]
}

@test "un email que no cumple su glob hace fallar el check" {
  make_profile ".claude" "tu-email@ejemplo.com"
  make_profile ".claude-work" "tu-email@ejemplo.com"
  printf 'shell-integration-features = no-title\n' > "$CAR_GHOSTTY_CONF"
  export CAR_ROUTER_LOADED=1
  run "$CA" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"no coincide"* ]]
}

@test "dos perfiles con el mismo email se avisan" {
  write_conf \
    "profile personal ~/.claude - -" \
    "profile work ~/.claude-work - -"
  make_profile ".claude" "tu-email@ejemplo.com"
  make_profile ".claude-work" "tu-email@ejemplo.com"
  printf 'shell-integration-features = no-title\n' > "$CAR_GHOSTTY_CONF"
  export CAR_ROUTER_LOADED=1
  run "$CA" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"misma cuenta"* ]]
}

@test "sin no-title en la config de Ghostty avisa" {
  make_profile ".claude" "tu-email@ejemplo.com"
  make_profile ".claude-work" "ricardo@empresa.com"
  printf 'theme = Github Dark Default\n' > "$CAR_GHOSTTY_CONF"
  export CAR_ROUTER_LOADED=1
  run "$CA" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"no-title"* ]]
}

@test "sin el router cargado en la sesion avisa" {
  make_profile ".claude" "tu-email@ejemplo.com"
  make_profile ".claude-work" "ricardo@empresa.com"
  printf 'shell-integration-features = no-title\n' > "$CAR_GHOSTTY_CONF"
  run env -u CAR_ROUTER_LOADED "$CA" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"router no esta cargado"* ]]
}
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

```bash
bats tests/check.bats
```
Expected: FAIL — `comando desconocido 'check'`

- [ ] **Step 3: Escribir el lector de expiración**

Archivo `lib/expiry.py`:

```python
#!/usr/bin/env python3
"""Imprime claudeAiOauth.expiresAt (epoch en milisegundos) de un .credentials.json.

Lee exclusivamente ese campo: los tokens no se leen ni se imprimen nunca.
Codigos de salida: 0 ok, 3 sin campo, 4 archivo ilegible o corrupto.
"""

import json
import sys

EXIT_OK = 0
EXIT_MISSING = 3
EXIT_BAD_JSON = 4


def main() -> int:
    if len(sys.argv) != 2:
        return EXIT_BAD_JSON
    try:
        with open(sys.argv[1], "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return EXIT_BAD_JSON
    if not isinstance(data, dict):
        return EXIT_BAD_JSON
    oauth = data.get("claudeAiOauth")
    if not isinstance(oauth, dict):
        return EXIT_MISSING
    expires = oauth.get("expiresAt")
    if not isinstance(expires, (int, float)):
        return EXIT_MISSING
    print(int(expires))
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Añadir `cmd_check` a `bin/claude-account`**

Insertar antes de `main`:

```bash
CAR_GHOSTTY_CONF="${CAR_GHOSTTY_CONF:-$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty}"

car_check_ok=0
car_check_bad=0

car_ok()   { printf '  ok   %s\n' "$1"; car_check_ok=$((car_check_ok + 1)); }
car_fail() { printf '  FALLA %s\n' "$1"; car_check_bad=$((car_check_bad + 1)); }

cmd_check() {
  local i j email status expires now dias creds

  car_check_ok=0
  car_check_bad=0

  echo "Configuracion"
  if car_load_config "$CAR_CONF" 2>/dev/null; then
    car_ok "routes.conf valido (${#CAR_P_NAME[@]} perfiles, ${#CAR_R_PATH[@]} rutas)"
  else
    car_fail "routes.conf invalido o ausente: $CAR_CONF"
    car_load_config "$CAR_CONF"
    return 1
  fi

  echo "Sesion"
  if [ -n "${CAR_ROUTER_LOADED:-}" ]; then
    car_ok "el router esta cargado en esta shell"
  else
    car_fail "el router no esta cargado en esta shell (abre un tab nuevo, o revisa ~/.zshrc)"
  fi

  if [ -f "$CAR_GHOSTTY_CONF" ]; then
    if grep -q 'no-title' "$CAR_GHOSTTY_CONF"; then
      car_ok "Ghostty tiene no-title en shell-integration-features"
    else
      car_fail "Ghostty reescribira el titulo: falta no-title en shell-integration-features"
    fi
  else
    car_fail "no encuentro la config de Ghostty en $CAR_GHOSTTY_CONF"
  fi

  echo "Perfiles"
  for ((i = 0; i < ${#CAR_P_NAME[@]}; i++)); do
    email="$(identity_email "${CAR_P_DIR[$i]}" 2>/dev/null)"
    status=$?
    if [ $status -ne 0 ]; then
      car_fail "${CAR_P_NAME[$i]}: sin sesion -> claude-account login ${CAR_P_NAME[$i]}"
      continue
    fi
    if identity_matches "$email" "${CAR_P_GLOB[$i]}"; then
      car_ok "${CAR_P_NAME[$i]}: $email"
    else
      car_fail "${CAR_P_NAME[$i]}: $email no coincide con ${CAR_P_GLOB[$i]}"
    fi

    creds="${CAR_P_DIR[$i]}/.credentials.json"
    if [ -f "$creds" ] && expires="$(python3 "$CAR_ROOT_DIR/lib/expiry.py" "$creds" 2>/dev/null)"; then
      now=$(( $(date +%s) * 1000 ))
      if [ "$expires" -lt "$now" ]; then
        echo "       (token vencido; Claude lo renovara al arrancar)"
      else
        dias=$(( (expires - now) / 86400000 ))
        [ "$dias" -le 3 ] && echo "       (el token vence en $dias dias)"
      fi
    fi
  done

  for ((i = 0; i < ${#CAR_P_NAME[@]}; i++)); do
    for ((j = i + 1; j < ${#CAR_P_NAME[@]}; j++)); do
      local a b
      a="$(identity_email "${CAR_P_DIR[$i]}" 2>/dev/null)" || continue
      b="$(identity_email "${CAR_P_DIR[$j]}" 2>/dev/null)" || continue
      if [ "$a" = "$b" ]; then
        car_fail "${CAR_P_NAME[$i]} y ${CAR_P_NAME[$j]} usan la misma cuenta ($a)"
      fi
    done
  done

  echo
  echo "$car_check_ok en orden, $car_check_bad por arreglar"
  [ "$car_check_bad" -eq 0 ]
}
```

Y añadir la rama al `case` de `main`:

```bash
    check) cmd_check "$@" ;;
```

- [ ] **Step 5: Correr los tests**

```bash
bats tests/check.bats && shellcheck -s bash bin/claude-account && python3 -m py_compile lib/expiry.py
```
Expected: `6 tests, 0 failures`

- [ ] **Step 6: Commit**

```bash
git add lib/expiry.py bin/claude-account tests/check.bats
git commit -m "feat: comando check con diagnostico de config, sesion y perfiles"
```

---

### Task 13: `shell/router.zsh` — pintado por prompt con caché

**Files:**
- Create: `shell/router.zsh`
- Test: `tests/router_paint.bats`

- [ ] **Step 1: Escribir los tests que fallan**

Los tests corren zsh en un subproceso: es la única forma honesta de probar hooks de zsh desde bats.

Archivo `tests/router_paint.bats`:

```bash
setup() {
  load helper
  setup_fixture
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/miapp work"
  mkdir -p "$HOME/repos/miapp" "$HOME/notas"
  export PATH="$CAR_ROOT/bin:$PATH"
}

# Corre un fragmento de zsh con el router cargado y TERM de Ghostty.
run_zsh() {
  TERM=xterm-ghostty run zsh -f -c "
    export CAR_CONF='$CAR_CONF'
    export PATH='$PATH'
    source '$CAR_ROOT/shell/router.zsh'
    $1
  "
}

@test "fuera de Ghostty el router no se activa" {
  TERM=xterm-256color run zsh -f -c "
    export CAR_CONF='$CAR_CONF'
    source '$CAR_ROOT/shell/router.zsh'
    print -r -- \"loaded=\${CAR_ROUTER_LOADED:-no}\"
  "
  [ "$output" = "loaded=no" ]
}

@test "dentro de Ghostty marca la sesion como cargada" {
  run_zsh "print -r -- \"loaded=\$CAR_ROUTER_LOADED\""
  [[ "$output" == *"loaded=1"* ]]
}

@test "desactiva el auto-titulo de oh-my-zsh" {
  run_zsh "print -r -- \"omz=\$DISABLE_AUTO_TITLE\""
  [[ "$output" == *"omz=true"* ]]
}

@test "pinta el perfil del directorio actual" {
  run_zsh "cd '$HOME/repos/miapp'; _car_paint"
  [[ "$output" == *"$(printf '\033]2;work · miapp\007')"* ]]
}

@test "la segunda pintada del mismo directorio usa la cache" {
  # El source ya pinto el directorio de partida: se limpia la cache para contar
  # solo lo que cachea esta prueba.
  run_zsh "
    _car_cache=()
    cd '$HOME/repos/miapp'
    _car_paint >/dev/null
    _car_paint >/dev/null
    print -r -- \"cacheados=\${#_car_cache}\"
  "
  [[ "$output" == *"cacheados=1"* ]]
}

@test "cambiar routes.conf invalida la cache" {
  run_zsh "
    cd '$HOME/repos/miapp'
    _car_paint >/dev/null
    sleep 1
    print -r -- 'profile personal ~/.claude tu-email@ejemplo.com -' > '$CAR_CONF'
    _car_paint
  "
  [[ "$output" == *"personal · miapp"* ]]
}

@test "el hook de salida resetea el fondo" {
  # Se pinta un directorio teñido y se comprueba que el reset va justo despues.
  run_zsh "cd '$HOME/repos/miapp'; _car_paint; _car_cleanup"
  [[ "$output" == *"$(printf '\033]11;#171b12\007\033]111\007')" ]]
}
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

```bash
bats tests/router_paint.bats
```
Expected: FAIL — `shell/router.zsh: no such file or directory`

- [ ] **Step 3: Escribir la implementación**

Archivo `shell/router.zsh`:

```zsh
# claude-ghostty-router — integracion de sesion zsh.
# Se auto-desactiva fuera de Ghostty y si el CLI no esta instalado.

[[ $TERM == xterm-ghostty ]] || return 0
(( $+commands[claude-account] )) || return 0

zmodload -F zsh/stat b:zstat 2>/dev/null
autoload -Uz add-zsh-hook

typeset -g CAR_ROUTER_LOADED=1
export CAR_ROUTER_LOADED

# oh-my-zsh reescribe el titulo en cada precmd via termsupport. Consulta esta
# variable en tiempo de ejecucion, asi que basta con ponerla aqui: funciona sin
# importar si el router se carga antes o despues de oh-my-zsh, y solo afecta a
# las sesiones de Ghostty porque mas arriba ya volvimos si el TERM es otro.
typeset -g DISABLE_AUTO_TITLE=true
export DISABLE_AUTO_TITLE

typeset -gA _car_cache
typeset -g _car_conf=${CAR_CONF:-$HOME/.config/claude-ghostty-router/routes.conf}
typeset -g _car_conf_mtime=

# Vacia la cache si routes.conf cambio. zstat es un builtin: no crea procesos.
_car_check_conf() {
  local -a stamp
  zstat -A stamp +mtime -- $_car_conf 2>/dev/null
  local now=${stamp[1]:-0}
  if [[ $now != $_car_conf_mtime ]]; then
    _car_conf_mtime=$now
    _car_cache=()
  fi
}

# Pinta la superficie actual. Con la cache caliente son ~40 bytes y cero forks,
# por eso puede correr en cada prompt.
_car_paint() {
  _car_check_conf
  local esc=${_car_cache[$PWD]-}
  if [[ -z $esc ]]; then
    esc=$(claude-account _surface "$PWD" 2>/dev/null)
    _car_cache[$PWD]=$esc
  fi
  [[ -n $esc ]] && print -rn -- $esc
}

_car_cleanup() {
  print -rn -- $'\e]111\a'
}

add-zsh-hook precmd _car_paint
add-zsh-hook zshexit _car_cleanup

_car_paint
```

- [ ] **Step 4: Correr los tests**

```bash
bats tests/router_paint.bats
```
Expected: `7 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add shell/router.zsh tests/router_paint.bats
git commit -m "feat: pintado de la superficie por prompt con cache invalidada por mtime"
```

---

### Task 14: `shell/router.zsh` — la función `claude()`

**Files:**
- Modify: `shell/router.zsh` (añadir la función `claude`)
- Test: `tests/router_claude.bats`

- [ ] **Step 1: Escribir los tests que fallan**

La propiedad que importa no es el mensaje de error: es que el binario real **no se ejecutó**. Por eso el `claude` falso deja un rastro en disco y el test comprueba su ausencia.

Archivo `tests/router_claude.bats`:

```bash
setup() {
  load helper
  setup_fixture
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/miapp work"
  mkdir -p "$HOME/repos/miapp"

  # Un claude falso que deja rastro si alguien lo ejecuta.
  export FAKE_BIN="$BATS_TEST_TMPDIR/bin"
  export RASTRO="$BATS_TEST_TMPDIR/arranco.txt"
  mkdir -p "$FAKE_BIN"
  cat > "$FAKE_BIN/claude" <<'FALSO'
#!/bin/sh
printf '%s\n' "$CLAUDE_CONFIG_DIR" > "$RASTRO"
echo "claude falso arranco"
FALSO
  chmod +x "$FAKE_BIN/claude"
}

run_zsh() {
  TERM=xterm-ghostty run zsh -f -c "
    export CAR_CONF='$CAR_CONF'
    export RASTRO='$RASTRO'
    export PATH='$FAKE_BIN:$CAR_ROOT/bin:$PATH'
    source '$CAR_ROOT/shell/router.zsh'
    $1
  "
}

@test "cuenta correcta: arranca con el CLAUDE_CONFIG_DIR del perfil" {
  make_profile ".claude-work" "ricardo@empresa.com"
  run_zsh "cd '$HOME/repos/miapp'; claude"
  [ "$status" -eq 0 ]
  [ "$(cat "$RASTRO")" = "$HOME/.claude-work" ]
}

@test "cuenta equivocada: NO arranca" {
  make_profile ".claude-work" "tu-email@ejemplo.com"
  run_zsh "cd '$HOME/repos/miapp'; claude"
  [ "$status" -eq 5 ]
  [ ! -f "$RASTRO" ]
  [[ "$output" == *"cuenta equivocada"* ]]
}

@test "perfil sin sesion: NO arranca" {
  make_profile ".claude-work"
  run_zsh "cd '$HOME/repos/miapp'; claude"
  [ "$status" -eq 3 ]
  [ ! -f "$RASTRO" ]
}

@test "routes.conf roto: NO arranca" {
  make_profile ".claude-work" "ricardo@empresa.com"
  printf 'basura aqui\n' > "$CAR_CONF"
  run_zsh "cd '$HOME/repos/miapp'; claude"
  [ "$status" -eq 2 ]
  [ ! -f "$RASTRO" ]
}

@test "los argumentos llegan intactos al binario real" {
  make_profile ".claude-work" "ricardo@empresa.com"
  cat > "$FAKE_BIN/claude" <<'FALSO'
#!/bin/sh
printf '%s\n' "$*" > "$RASTRO"
FALSO
  chmod +x "$FAKE_BIN/claude"
  run_zsh "cd '$HOME/repos/miapp'; claude --version 'con espacio'"
  [ "$(cat "$RASTRO")" = "--version con espacio" ]
}

@test "fuera de Ghostty la funcion ni siquiera existe" {
  make_profile ".claude-work" "tu-email@ejemplo.com"
  TERM=xterm-256color run zsh -f -c "
    export CAR_CONF='$CAR_CONF'
    export RASTRO='$RASTRO'
    export PATH='$FAKE_BIN:$CAR_ROOT/bin:$PATH'
    source '$CAR_ROOT/shell/router.zsh'
    cd '$HOME/repos/miapp'
    claude
  "
  [ "$status" -eq 0 ]
  [ -f "$RASTRO" ]
}
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

```bash
bats tests/router_claude.bats
```
Expected: FAIL — el `claude` falso arranca siempre; los tests de bloqueo fallan porque `$RASTRO` existe

- [ ] **Step 3: Añadir la función a `shell/router.zsh`**

Insertar antes de las líneas `add-zsh-hook`:

```zsh
# Sustituye a `claude` solo en sesiones de Ghostty. Toda la autoridad para negar
# el arranque vive aqui: si _launch-check falla, no se ejecuta nada.
claude() {
  local config_dir rc
  config_dir=$(claude-account _launch-check "$PWD") || return $?

  if [[ -n $config_dir ]]; then
    CLAUDE_CONFIG_DIR=$config_dir command claude "$@"
  else
    command claude "$@"
  fi
  rc=$?

  # Claude Code toca el titulo mientras corre: hay que devolverlo a su sitio.
  _car_paint
  return $rc
}
```

- [ ] **Step 4: Correr los tests**

```bash
bats tests/router_claude.bats
```
Expected: `6 tests, 0 failures`

- [ ] **Step 5: Correr la batería completa**

```bash
bats tests/
```
Expected: todos los archivos en verde, `0 failures`

- [ ] **Step 6: Commit**

```bash
git add shell/router.zsh tests/router_claude.bats
git commit -m "feat: funcion claude() que bloquea si la cuenta no corresponde"
```

---

### Task 15: `install.sh` — instalación idempotente y reversible

**Files:**
- Create: `install.sh`
- Create: `routes.conf.example`
- Test: `tests/install.bats`

- [ ] **Step 1: Escribir el ejemplo de configuración**

Archivo `routes.conf.example`:

```conf
# claude-ghostty-router — rutas de carpetas a cuentas Claude.
#
#   profile <nombre> <config-dir> [email-glob] [color-de-fondo]
#     email-glob: patron que DEBE cumplir la cuenta logueada. "-" = no verificar.
#     color:      #rrggbb del fondo de la superficie. "-" = respetar el tema.
#
#   route <ruta> <perfil>
#     Gana la primera ruta declarada: declara las excepciones antes que el padre.
#     Se permiten globs. Un subdirectorio hereda la ruta de su padre, y una
#     carpeta dentro de un repo git hereda la ruta de la raiz del repo.
#
# El primer perfil declarado es el perfil por defecto.

profile personal  ~/.claude       tu-email@ejemplo.com  -
profile work      ~/.claude-work  *@tuempresa.com     #171b12

# route ~/repos/proyecto-de-trabajo  work
# route ~/repos/cliente-*            work
```

- [ ] **Step 2: Escribir los tests que fallan**

Archivo `tests/install.bats`:

```bash
setup() {
  load helper
  setup_fixture
  export ZDOTDIR="$HOME"
  mkdir -p "$HOME/.local/bin" "$HOME/Library/Application Support/com.mitchellh.ghostty"
  export CAR_GHOSTTY_CONF="$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
  printf 'theme = Github Dark Default\n' > "$CAR_GHOSTTY_CONF"
  printf 'export ZSH="$HOME/.oh-my-zsh"\n' > "$HOME/.zshrc"
  unset CAR_CONF
}

@test "instala el enlace, la config, la linea del zshrc y no-title" {
  run "$CAR_ROOT/install.sh" --yes
  [ "$status" -eq 0 ]
  [ -L "$HOME/.local/bin/claude-account" ]
  [ -f "$HOME/.config/claude-ghostty-router/routes.conf" ]
  grep -q "router.zsh" "$HOME/.zshrc"
  grep -q "no-title" "$CAR_GHOSTTY_CONF"
}

@test "es idempotente: dos instalaciones dejan una sola linea en el zshrc" {
  "$CAR_ROOT/install.sh" --yes
  run "$CAR_ROOT/install.sh" --yes
  [ "$status" -eq 0 ]
  [ "$(grep -c 'router.zsh' "$HOME/.zshrc")" -eq 1 ]
}

@test "nunca pisa una routes.conf existente" {
  mkdir -p "$HOME/.config/claude-ghostty-router"
  printf 'profile mio ~/.claude\n' > "$HOME/.config/claude-ghostty-router/routes.conf"
  "$CAR_ROOT/install.sh" --yes
  run cat "$HOME/.config/claude-ghostty-router/routes.conf"
  [ "$output" = "profile mio ~/.claude" ]
}

@test "respalda la config de Ghostty antes de tocarla" {
  "$CAR_ROOT/install.sh" --yes
  [ -f "$CAR_GHOSTTY_CONF.bak" ]
  run grep -c "no-title" "$CAR_GHOSTTY_CONF.bak"
  [ "$output" = "0" ]
}

@test "uninstall revierte enlace, linea y no-title" {
  "$CAR_ROOT/install.sh" --yes
  run "$CAR_ROOT/install.sh" --uninstall --yes
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/bin/claude-account" ]
  run grep -c "router.zsh" "$HOME/.zshrc"
  [ "$output" = "0" ]
  run grep -c "no-title" "$CAR_GHOSTTY_CONF"
  [ "$output" = "0" ]
}

@test "uninstall conserva routes.conf: es del usuario" {
  "$CAR_ROOT/install.sh" --yes
  "$CAR_ROOT/install.sh" --uninstall --yes
  [ -f "$HOME/.config/claude-ghostty-router/routes.conf" ]
}
```

- [ ] **Step 3: Correr los tests para verificar que fallan**

```bash
bats tests/install.bats
```
Expected: FAIL — `install.sh: No such file or directory`

- [ ] **Step 4: Escribir el instalador**

Archivo `install.sh` (marcar ejecutable en el paso 5):

```bash
#!/usr/bin/env bash
# Instalacion de claude-ghostty-router. Idempotente y reversible.
set -eu

CAR_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
CONF_DIR="$HOME/.config/claude-ghostty-router"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
GHOSTTY_CONF="${CAR_GHOSTTY_CONF:-$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty}"
MARCA="# claude-ghostty-router"
LINEA_ZSHRC="[ -f \"$CAR_SRC/shell/router.zsh\" ] && source \"$CAR_SRC/shell/router.zsh\"  $MARCA"
FEATURES="shell-integration-features = cursor,no-sudo,no-title,no-ssh-env,no-ssh-terminfo,path"

ASUMIR_SI=0
MODO=install
for arg in "$@"; do
  case "$arg" in
    --yes|-y)    ASUMIR_SI=1 ;;
    --uninstall) MODO=uninstall ;;
    *) echo "uso: install.sh [--yes] [--uninstall]" >&2; exit 1 ;;
  esac
done

confirmar() {
  [ "$ASUMIR_SI" -eq 1 ] && return 0
  printf '%s [s/N] ' "$1"
  read -r respuesta
  case "$respuesta" in s|S|si|SI) return 0 ;; *) return 1 ;; esac
}

instalar() {
  mkdir -p "$BIN_DIR" "$CONF_DIR"

  ln -sf "$CAR_SRC/bin/claude-account" "$BIN_DIR/claude-account"
  echo "ok  enlace en $BIN_DIR/claude-account"

  if [ -f "$CONF_DIR/routes.conf" ]; then
    echo "ok  $CONF_DIR/routes.conf ya existe (no se toca)"
  else
    cp "$CAR_SRC/routes.conf.example" "$CONF_DIR/routes.conf"
    echo "ok  creado $CONF_DIR/routes.conf — editalo con tus cuentas y rutas"
  fi

  if [ -f "$ZSHRC" ] && grep -qF "$MARCA" "$ZSHRC"; then
    echo "ok  ~/.zshrc ya carga el router"
  elif confirmar "Agregar una linea a $ZSHRC para cargar el router?"; then
    printf '\n%s\n' "$LINEA_ZSHRC" >> "$ZSHRC"
    echo "ok  linea agregada a $ZSHRC"
  fi

  if [ -f "$GHOSTTY_CONF" ] && grep -q 'no-title' "$GHOSTTY_CONF"; then
    echo "ok  Ghostty ya tiene no-title"
  elif confirmar "Poner no-title en la config de Ghostty (con backup)?"; then
    [ -f "$GHOSTTY_CONF" ] && cp "$GHOSTTY_CONF" "$GHOSTTY_CONF.bak"
    printf '\n%s  %s\n' "$FEATURES" "$MARCA" >> "$GHOSTTY_CONF"
    echo "ok  no-title agregado (backup en $GHOSTTY_CONF.bak)"
  fi

  echo
  echo "Falta un paso manual: edita $CONF_DIR/routes.conf y corre"
  echo "'claude-account login <perfil>' para cada cuenta."
  echo
  # El diagnostico se ejecuta siempre: recien instalado va a fallar (todavia no
  # hay sesiones), y eso es exactamente lo que hay que ver.
  "$BIN_DIR/claude-account" check || true
}

desinstalar() {
  rm -f "$BIN_DIR/claude-account"
  echo "ok  enlace eliminado"

  # `grep -v` devuelve 1 si no queda ninguna linea, y con `set -e` eso abortaria
  # el script justo cuando el archivo se queda vacio: por eso el `|| true`.
  if [ -f "$ZSHRC" ] && grep -qF "$MARCA" "$ZSHRC"; then
    grep -vF "$MARCA" "$ZSHRC" > "$ZSHRC.tmp" || true
    mv "$ZSHRC.tmp" "$ZSHRC"
    echo "ok  linea eliminada de $ZSHRC"
  fi

  if [ -f "$GHOSTTY_CONF" ] && grep -qF "$MARCA" "$GHOSTTY_CONF"; then
    grep -vF "$MARCA" "$GHOSTTY_CONF" > "$GHOSTTY_CONF.tmp" || true
    mv "$GHOSTTY_CONF.tmp" "$GHOSTTY_CONF"
    echo "ok  no-title revertido en la config de Ghostty"
  fi

  echo "ok  $CONF_DIR/routes.conf se conserva: es tuyo"
}

case "$MODO" in
  install)   instalar ;;
  uninstall) desinstalar ;;
esac
```

- [ ] **Step 5: Hacerlo ejecutable y correr los tests**

```bash
chmod +x install.sh
bats tests/install.bats && shellcheck -s bash install.sh
```
Expected: `6 tests, 0 failures`

- [ ] **Step 6: Correr la batería completa y el lint de todo**

```bash
bats tests/ && shellcheck -s bash bin/claude-account install.sh lib/*.sh
```
Expected: `0 failures`, shellcheck sin salida

- [ ] **Step 7: Commit**

```bash
git add install.sh routes.conf.example tests/install.bats
git commit -m "feat: instalador idempotente con desinstalacion"
```

---

### Task 16: Puesta en marcha real

Todo lo anterior corre contra fixtures. Esta tarea es la única que toca la máquina de verdad, y **requiere al usuario**: hay que iniciar sesión en la cuenta de trabajo a mano.

**Files:**
- Modify: `~/.config/claude-ghostty-router/routes.conf` (fuera del repo)

- [ ] **Step 1: Instalar**

```bash
cd ~/repos/claude-ghostty-router && ./install.sh
```
Expected: cuatro líneas `ok` y la instrucción final

- [ ] **Step 2: Pedir al usuario los tres datos pendientes**

Preguntar y anotar: el **email de la cuenta de trabajo**, el **directorio del perfil** (por defecto `~/.claude-work`) y **qué repos de `~/repos` van a `work`**.

- [ ] **Step 3: Escribir la routes.conf real**

Editar `~/.config/claude-ghostty-router/routes.conf` con los datos del paso 2. Verificar:

```bash
claude-account routes
```
Expected: la lista de rutas con su perfil, sin errores

- [ ] **Step 4: Iniciar sesión en el perfil de trabajo**

```bash
claude-account login work
```
El usuario ejecuta `/login` dentro de Claude, completa el flujo del navegador y sale con `/exit`.

- [ ] **Step 5: Confirmar el layout del archivo de identidad**

```bash
ls -la ~/.claude-work/.claude.json ~/.claude-work.json 2>&1
```
Expected: existe uno de los dos. Actualizar la conclusión de `docs/experiments/2026-09-01-identity-layout.md` con lo observado ahora que sí hay una sesión real.

- [ ] **Step 6: Diagnóstico completo en un tab nuevo de Ghostty**

Abrir un tab nuevo (para que cargue el router) y correr:

```bash
claude-account check
```
Expected: `N en orden, 0 por arreglar`

- [ ] **Step 7: Verificación visual a mano**

En Ghostty, con dos tabs:

```bash
# tab 1
cd ~/repos/<un-repo-de-work>   # el titulo dice "work · <repo>" y el fondo se tiñe
# tab 2
cd ~/repos/<un-repo-personal>  # el titulo dice "personal · <repo>", fondo del tema
```
Expected: cada tab conserva su título y su color al saltar entre ellos.

- [ ] **Step 8: Verificar el bloqueo de verdad**

Editar temporalmente `routes.conf` para que un repo personal apunte a `work`, y ahí:

```bash
claude
```
Expected: no arranca; el mensaje dice qué esperaba, qué encontró y `claude-account login work`. Revertir la edición después.

- [ ] **Step 9: Commit del resultado del experimento**

```bash
git add docs/experiments/
git commit -m "docs: confirmacion del layout de identidad con una sesion real"
```

---

## Notas de ejecución

- **El orden importa.** Las tareas 3→8 construyen el núcleo de abajo hacia arriba; 9→12 lo exponen; 13→14 lo enchufan a la shell. Ninguna tarea usa algo que una tarea posterior define.
- **Task 2 no bloquea.** `identity.sh` soporta los dos layouts, así que si el experimento queda indeterminado se sigue igual y se cierra en la Task 16, paso 5.
- **Task 16 no es automatizable**: el `/login` es interactivo y necesita al usuario frente al navegador.

# El tinte de fondo sobre el badge — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el fondo del tab de Ghostty se tiña con el color de fondo del perfil mientras corre una sesión de Claude, y vuelva al color del tema al salir, sin tocar el badge.

**Architecture:** `routes.conf` gana un quinto campo opcional, el color de fondo, separado del color del badge porque los dos medios piden valores opuestos. Vuelve `lib/ghostty.sh` como emisor de OSC, hermano de `lib/badge.sh` (que emite SGR). El CLI gana `_tint` y `_untint`, y `shell/router.zsh` los usa alrededor de la sesión dentro de su `claude()`.

**Tech Stack:** bash 3.2 (`bin/`, `lib/`), zsh (`shell/router.zsh`), bats-core, shellcheck.

**Spec:** [docs/superpowers/specs/2026-09-02-tinte-sobre-badge-design.md](../specs/2026-09-02-tinte-sobre-badge-design.md)

**Base:** `8effa16` (feat: badge de cuenta en el statusLine de Claude Code). 127 tests verdes, shellcheck limpio.

---

## Contexto para quien implemente

Este repo enruta carpetas a cuentas de Claude Code dentro de Ghostty. Convenciones que hay
que respetar sin excepción:

1. **Comentarios, nombres de test y mensajes de commit en español sin tildes.** Es la
   convención del repo; míralo antes de escribir.
2. **Los comentarios explican el porqué, no el qué.** Mira cualquier archivo de `lib/`.
3. **bash 3.2** en `bin/` y `lib/`: sin `declare -A`, sin `${var^^}`, sin `mapfile`. Arrays
   paralelos, no asociativos.
4. **Cada emisor de escapes en su archivo.** `lib/badge.sh` emite SGR (texto coloreado que
   renderiza Claude Code). `lib/ghostty.sh` emite OSC (habla con el emulador). Ningún otro
   archivo escribe `\033[` ni `\033]` a mano.
5. **El pintado informa, no decide.** `_tint` y `_untint` no fallan nunca. Quien bloquea el
   arranque es `_launch-check`, y falla cerrado.

Comandos:

```sh
bats tests/                                                 # toda la suite
bats tests/config.bats                                      # un archivo
shellcheck -s bash bin/claude-account install.sh lib/*.sh   # lint
```

## Estructura de archivos

| Archivo | Qué pasa con él | Task |
|---|---|---|
| `lib/config.sh` | Parsea el quinto campo; se extrae `car_check_color` para no duplicar la validación. | 1 |
| `lib/resolve.sh` | Array `CAR_P_TINT`; el registro de `resolve_route` gana un sexto campo. | 1 |
| `bin/claude-account` | Los tres lectores posicionales del registro; luego `_tint`/`_untint`. | 1, 3 |
| `lib/ghostty.sh` | Vuelve, con `ghostty_bg` y nada más. | 2 |
| `lib/badge.sh` | Solo el comentario de cabecera. | 2 |
| `shell/router.zsh` | El teñido alrededor de la sesión. | 4 |
| `bin/claude-account` | ...y que `check` muestre los dos colores de cada perfil. | 5 |
| `routes.conf.example`, `README.md` | El quinto campo. | 5 |

---

### Task 1: El quinto campo, del parseo al registro

`routes.conf` pasa de `profile <nombre> <dir> [glob] [color]` a
`profile <nombre> <dir> [glob] [color] [fondo]`. El campo es opcional y su ausencia es `-`,
así que toda config existente sigue valiendo.

**Files:**
- Modify: `lib/config.sh` (validación y emisión), `lib/resolve.sh` (arrays y registro), `bin/claude-account` (`cmd_launch_check`, `cmd_which`, `cmd_status`)
- Modify: `tests/config.bats`, `tests/load.bats`, `tests/resolve.bats`

- [ ] **Step 1: Actualizar los tests que fijan el registro exacto**

Cinco tests existentes comparan el registro campo por campo y ahora esperan uno más.

En `tests/config.bats`, el test `"parsea un perfil completo y expande ~"`:

```bash
  [ "$output" = "$(printf 'profile\twork\t%s/.claude-work\t*@empresa.com\t#171b12\t-' "$HOME")" ]
```

El test `"los campos opcionales quedan en guion"`:

```bash
  [ "$output" = "$(printf 'profile\tpersonal\t%s/.claude\t-\t-\t-' "$HOME")" ]
```

El test `"ignora comentarios de linea completa, lineas vacias y espacios sobrantes"`, misma
línea:

```bash
  [ "$output" = "$(printf 'profile\tpersonal\t%s/.claude\t-\t-\t-' "$HOME")" ]
```

El test `"tolera finales de linea CRLF"`:

```bash
  [ "$output" = "$(printf 'profile\tpersonal\t%s/.claude\t-\t-\t-\nroute\t%s/repos/uno\tpersonal' "$HOME" "$HOME")" ]
```

El test `"rechaza campos de mas"` ahora necesita seis campos para tener uno de más:

```bash
@test "rechaza campos de mas" {
  write_conf "profile work ~/.claude-work *@empresa.com #171b12 #0a0a0a sobra"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 2 ]
}
```

En `tests/resolve.bats`, el comentario que documenta el registro y el test
`"emite el dir, el glob y el color del perfil resuelto"`:

```bash
# resolve_route imprime: perfil<TAB>proyecto<TAB>dir<TAB>glob<TAB>color<TAB>fondo
```
```bash
@test "emite el dir, el glob, el color y el fondo del perfil resuelto" {
  mkdir -p "$HOME/repos/proyecto-uno"
  run resolve_route "$HOME/repos/proyecto-uno"
  [ "$output" = "$(printf 'work\tproyecto-uno\t%s/.claude-work\t*@empresa.com\t#171b12\t-' "$HOME")" ]
}
```

- [ ] **Step 2: Añadir los tests del campo nuevo**

En `tests/config.bats`, después de `"rechaza un color mal formado"`:

```bash
@test "parsea el color de fondo como quinto campo" {
  write_conf "profile work ~/.claude-work *@empresa.com #8fbc5a #171b12"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'profile\twork\t%s/.claude-work\t*@empresa.com\t#8fbc5a\t#171b12' "$HOME")" ]
}

@test "el fondo ausente queda en guion: las configs viejas siguen valiendo" {
  write_conf "profile work ~/.claude-work *@empresa.com #8fbc5a"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(printf '#8fbc5a\t-')" ]]
}

@test "rechaza un fondo mal formado" {
  write_conf "profile work ~/.claude-work *@empresa.com #8fbc5a verde"
  run config_parse "$CAR_CONF"
  [ "$status" -eq 2 ]
  [[ "$output" == *"fondo"* ]]
}
```

En `tests/load.bats`, el test `"carga perfiles y rutas en arrays paralelos"` pasa a ser:

```bash
@test "carga perfiles y rutas en arrays paralelos" {
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #8fbc5a #171b12" \
    "route ~/repos/uno work"
  car_load_config "$CAR_CONF"
  [ "${#CAR_P_NAME[@]}" -eq 2 ]
  [ "${CAR_P_NAME[0]}" = "personal" ]
  [ "${CAR_P_DIR[1]}" = "$HOME/.claude-work" ]
  [ "${CAR_P_GLOB[1]}" = "*@empresa.com" ]
  [ "${CAR_P_COLOR[1]}" = "#8fbc5a" ]
  [ "${CAR_P_TINT[1]}" = "#171b12" ]
  [ "${CAR_P_TINT[0]}" = "-" ]
  [ "${#CAR_R_PATH[@]}" -eq 1 ]
  [ "${CAR_R_PROFILE[0]}" = "work" ]
}
```

- [ ] **Step 3: Correr los tests para verificar que fallan**

Run: `bats tests/config.bats tests/load.bats tests/resolve.bats`
Expected: fallan los que fijan el registro exacto (esperan seis campos y llegan cinco), los
tres nuevos de `config.bats` y el de `load.bats` (`CAR_P_TINT` no existe).

- [ ] **Step 4: Extraer la validación de color en `lib/config.sh`**

La validación se va a usar dos veces, así que se extrae antes de duplicarla. Añade esta
función justo antes de `config_parse`, después de `car_strip_trailing_slash`:

```bash
# car_check_color <valor> <archivo> <linea> <etiqueta>
# "-" o #rrggbb pasan. Cualquier otra cosa aborta nombrando el campo: hay dos
# colores por perfil y el mensaje tiene que decir cual de los dos esta mal.
car_check_color() {
  case "$1" in
    -) return 0 ;;
    '#'[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) return 0 ;;
  esac
  echo "claude-account: $2 linea $3: $4 invalido '$1' (usa #rrggbb o -)" >&2
  return 1
}
```

- [ ] **Step 5: Parsear el quinto campo**

En `lib/config.sh`, actualiza el comentario de cabecera de `config_parse`:

```bash
# config_parse <archivo>
# Imprime, en orden de aparicion:
#   profile<TAB><nombre><TAB><dir><TAB><email-glob><TAB><color><TAB><fondo>
#   route<TAB><ruta><TAB><perfil>
# Los campos opcionales ausentes salen como "-".
```

Añade `tint` a los locales:

```bash
  local lineno=0 raw kind rest name dir glob color tint rpath rprof extra
```

Cambia el `read` del bloque `profile` para tomar el campo nuevo antes de `extra`:

```bash
        read -r name dir glob color tint extra <<< "$rest"
```

Y sustituye todo el bloque que va desde `glob="${glob:--}"` hasta el `printf` por:

```bash
        glob="${glob:--}"
        color="${color:--}"
        tint="${tint:--}"
        car_check_color "$color" "$file" "$lineno" "color" || return $CAR_ECONFIG
        car_check_color "$tint" "$file" "$lineno" "fondo" || return $CAR_ECONFIG
        printf 'profile\t%s\t%s\t%s\t%s\t%s\n' "$name" "$(car_strip_trailing_slash "$(car_expand_tilde "$dir")")" "$glob" "$color" "$tint"
```

- [ ] **Step 6: El array y el registro en `lib/resolve.sh`**

La declaración de arriba del archivo:

```bash
CAR_P_NAME=(); CAR_P_DIR=(); CAR_P_GLOB=(); CAR_P_COLOR=(); CAR_P_TINT=()
CAR_R_PATH=(); CAR_R_PROFILE=()
```

En `car_load_config`, los locales y el mismo reseteo:

```bash
  local file="$1" parsed kind f2 f3 f4 f5 f6 i

  CAR_P_NAME=(); CAR_P_DIR=(); CAR_P_GLOB=(); CAR_P_COLOR=(); CAR_P_TINT=()
  CAR_R_PATH=(); CAR_R_PROFILE=()
```

El `read` del bucle y el `+=` del caso `profile`:

```bash
  while IFS=$'\t' read -r kind f2 f3 f4 f5 f6; do
```
```bash
        CAR_P_NAME+=("$f2"); CAR_P_DIR+=("$f3"); CAR_P_GLOB+=("$f4"); CAR_P_COLOR+=("$f5")
        CAR_P_TINT+=("$f6")
```

En `car_emit_profile`, el `printf` pasa a seis campos:

```bash
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$name" "$label" "${CAR_P_DIR[$i]}" "${CAR_P_GLOB[$i]}" "${CAR_P_COLOR[$i]}" "${CAR_P_TINT[$i]}"
```

Y el comentario de `resolve_route`:

```bash
# resolve_route <directorio>
# -> perfil<TAB>proyecto<TAB>config-dir<TAB>email-glob<TAB>color<TAB>fondo
```

- [ ] **Step 7: Los tres lectores posicionales del registro**

`read -r a b c d e` con seis campos mete `color<TAB>fondo` entero en `e`. Los tres
consumidores tienen que declarar la variable nueva aunque no la usen.

En `bin/claude-account`, `cmd_launch_check`:

```bash
  local dir="${1:-$PWD}" record profile label config_dir glob color tint email status default_dir
```
```bash
  # color y tint no se usan en esta ruta: solo hacen falta para pintar.
  # shellcheck disable=SC2034
  IFS=$'\t' read -r profile label config_dir glob color tint <<< "$record"
```

`cmd_which` entero:

```bash
cmd_which() {
  local dir="${1:-$PWD}" record profile label pdir pglob color tint
  car_load_config "$CAR_CONF" || return $CAR_ECONFIG
  record="$(resolve_route "$dir")" || return $CAR_ECONFIG
  # shellcheck disable=SC2034
  IFS=$'\t' read -r profile label pdir pglob color tint <<< "$record"
  printf '%s\n' "$profile"
}
```

`cmd_status`, en sus locales y en su `read`:

```bash
  local i email status record profile here pdir pglob color tint
```
```bash
  # shellcheck disable=SC2034
  IFS=$'\t' read -r profile here pdir pglob color tint <<< "$record"
```

- [ ] **Step 8: Correr los tests**

Run: `bats tests/`
Expected: 0 `not ok`. Deberían ser 130 (127 de base más los 3 nuevos de `config.bats`);
comprueba el número real y quédate con él para el README de la Task 5.

- [ ] **Step 9: Lint**

Run: `shellcheck -s bash bin/claude-account install.sh lib/*.sh`
Expected: sin salida.

- [ ] **Step 10: Commit**

```bash
git add lib/config.sh lib/resolve.sh bin/claude-account tests/config.bats tests/load.bats tests/resolve.bats
git commit -m "feat: quinto campo en routes.conf para el color de fondo

El badge colorea texto y el tab colorea fondo: un tono legible como
badge es inusable como fondo y al reves. Cada medio elige el suyo. El
campo es opcional, asi que las configs existentes siguen valiendo."
```

---

### Task 2: `lib/ghostty.sh` vuelve

Un archivo por medio: `badge.sh` emite SGR para el texto que renderiza Claude Code,
`ghostty.sh` emite OSC para hablar con el emulador.

**Files:**
- Create: `lib/ghostty.sh`, `tests/ghostty.bats`
- Modify: `lib/badge.sh` (solo el comentario de cabecera)

- [ ] **Step 1: Escribir los tests**

Crea `tests/ghostty.bats`:

```bash
setup() {
  load helper
  setup_fixture
  source "$CAR_ROOT/lib/ghostty.sh"
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
  # Lo que entra aqui viene de un archivo de configuracion: si se colara sin
  # validar, seria una via de inyeccion de secuencias de escape.
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

Run: `bats tests/ghostty.bats`
Expected: los 4 fallan — `lib/ghostty.sh` no existe, el `source` del `setup` revienta.

- [ ] **Step 3: Crear `lib/ghostty.sh`**

```bash
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
```

- [ ] **Step 4: Corregir el comentario de cabecera de `lib/badge.sh`**

Ya no es el único emisor de escapes. Sustituye sus dos primeras líneas por:

```bash
# Emisor de las secuencias SGR del proyecto: el texto coloreado del badge, que
# renderiza Claude Code dentro de la sesion. Su hermano lib/ghostty.sh emite
# OSC, que le habla al emulador de terminal.
# No sabe que es un perfil: recibe texto y color, y emite bytes.
```

- [ ] **Step 5: Correr los tests**

Run: `bats tests/ghostty.bats tests/badge.bats`
Expected: 4 PASS en `ghostty.bats`; `badge.bats` sigue verde.

- [ ] **Step 6: Lint**

Run: `shellcheck -s bash bin/claude-account install.sh lib/*.sh`
Expected: sin salida.

- [ ] **Step 7: Commit**

```bash
git add lib/ghostty.sh lib/badge.sh tests/ghostty.bats
git commit -m "feat: lib/ghostty.sh emite las secuencias OSC

Un archivo por medio: badge.sh colorea texto que renderiza Claude Code,
ghostty.sh le habla al emulador de terminal."
```

---

### Task 3: `_tint` y `_untint` en el CLI

**Files:**
- Create: `tests/tint.bats`
- Modify: `bin/claude-account` (el `source` de librerias, dos funciones nuevas, el `case` de `main`)

- [ ] **Step 1: Escribir los tests**

Crea `tests/tint.bats`:

```bash
setup() {
  load helper
  setup_fixture
  CA="$CAR_ROOT/bin/claude-account"
}

@test "tint emite el fondo del perfil resuelto" {
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com - -" \
    "profile work ~/.claude-work *@empresa.com #8fbc5a #171b12" \
    "route ~/repos/miapp work"
  mkdir -p "$HOME/repos/miapp"
  run "$CA" _tint "$HOME/repos/miapp"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]11;#171b12\007')" ]
}

@test "tint usa el fondo, no el color del badge" {
  # Los dos campos existen justo porque un tono legible como badge es inusable
  # como fondo. Confundirlos aqui cegaria el tab, y el badge se volveria
  # ilegible: la asercion negativa fija cual de los dos sale.
  write_conf \
    "profile work ~/.claude-work *@empresa.com #8fbc5a #171b12" \
    "route ~/repos/miapp work"
  mkdir -p "$HOME/repos/miapp"
  run "$CA" _tint "$HOME/repos/miapp"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]11;#171b12\007')" ]
  [[ "$output" != *"8fbc5a"* ]]
}

@test "un perfil sin fondo no emite nada" {
  # Salida vacia es como router.zsh sabe que no hay que despintar al salir.
  write_conf "profile personal ~/.claude tu-email@ejemplo.com #8fbc5a"
  mkdir -p "$HOME/notas"
  run "$CA" _tint "$HOME/notas"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "sin routes.conf no emite nada y sale con exito" {
  rm -f "$CAR_CONF"
  run "$CA" _tint "$HOME"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "con routes.conf roto no emite nada y sale con exito" {
  # El pintado informa, no decide: del error avisa _launch-check al bloquear
  # el arranque, con archivo y linea por stderr.
  write_conf "basura aqui"
  run "$CA" _tint "$HOME"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "tint funciona invocado a traves de un symlink" {
  # Asi es como se instala: ~/.local/bin/claude-account -> repo/bin/claude-account.
  write_conf \
    "profile work ~/.claude-work *@empresa.com #8fbc5a #171b12" \
    "route ~/repos/miapp work"
  mkdir -p "$HOME/.local/bin" "$HOME/repos/miapp"
  ln -sf "$CA" "$HOME/.local/bin/claude-account"
  run "$HOME/.local/bin/claude-account" _tint "$HOME/repos/miapp"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]11;#171b12\007')" ]
}

@test "untint emite el reset al tema" {
  run "$CA" _untint
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]111\007')" ]
}

@test "untint no necesita routes.conf" {
  # Corre al salir de Claude y en el hook zshexit: tiene que funcionar aunque
  # la config haya desaparecido o se haya roto mientras corria la sesion.
  rm -f "$CAR_CONF"
  run "$CA" _untint
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]111\007')" ]
}
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

Run: `bats tests/tint.bats`
Expected: fallan con `claude-account: comando desconocido '_tint'` (y `'_untint'`).

- [ ] **Step 3: Cargar la libreria nueva**

En `bin/claude-account`, añade la línea que falta al bloque de `source` (junto a
`config.sh`, `resolve.sh`, `identity.sh`, `badge.sh`):

```bash
. "$CAR_ROOT_DIR/lib/ghostty.sh"
```

- [ ] **Step 4: Añadir los dos comandos**

En `bin/claude-account`, justo antes del comentario `# _launch-check <directorio>`:

```bash
# _tint <directorio>
# Emite el color de fondo del perfil de ese directorio. Nunca falla: el pintado
# informa, no decide. De un routes.conf roto avisa _launch-check al bloquear el
# arranque, con archivo y linea por stderr.
# Salida vacia significa "no hay nada que tenir", y router.zsh la usa para
# saltarse el _untint de salida.
cmd_tint() {
  local dir="${1:-$PWD}" record tint

  [ -f "$CAR_CONF" ] || return 0
  car_load_config "$CAR_CONF" 2>/dev/null || return 0
  record="$(resolve_route "$dir" 2>/dev/null)" || return 0

  # Solo hace falta el ultimo campo, asi que no se desmonta el registro entero:
  # mismo criterio que cmd_which con el primero.
  tint="${record##*$'\t'}"
  [ "$tint" = "-" ] && return 0
  ghostty_bg "$tint" || return 0
  return 0
}

# _untint
# Devuelve el fondo al color del tema. No lee configuracion a proposito: corre
# al salir de Claude y en el hook zshexit, donde routes.conf puede haber
# desaparecido o roto sin que eso deba dejar el tab tenido.
cmd_untint() {
  ghostty_bg "-"
}
```

- [ ] **Step 5: Registrar los comandos en `main`**

En el `case` de `main()`, añade las dos ramas justo antes de `_launch-check`:

```bash
    _tint)         cmd_tint "$@" ;;
    _untint)       cmd_untint ;;
```

`cmd_help` no se toca: son comandos internos, como `_launch-check` y `_config-dirs`, y
ninguno de esos se anuncia.

- [ ] **Step 6: Correr los tests**

Run: `bats tests/`
Expected: 0 `not ok`. Apunta el número total para el README.

- [ ] **Step 7: Lint**

Run: `shellcheck -s bash bin/claude-account install.sh lib/*.sh`
Expected: sin salida.

- [ ] **Step 8: Commit**

```bash
git add bin/claude-account tests/tint.bats
git commit -m "feat: comandos _tint y _untint

Resuelven el fondo de un directorio y el reset al tema. Ninguno falla
nunca: quien bloquea el arranque es _launch-check."
```

---

### Task 4: `claude()` tiñe alrededor de la sesión

El corazón del cambio.

**Files:**
- Modify: `shell/router.zsh`
- Modify: `tests/router_claude.bats` (el `write_conf` del setup y cuatro tests nuevos), `tests/router_load.bats` (un test nuevo)

- [ ] **Step 1: Dar fondo al perfil de prueba de `router_claude.bats`**

En su `setup()`, el `write_conf` pasa a declarar los dos colores:

```bash
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com - -" \
    "profile work ~/.claude-work *@empresa.com #8fbc5a #171b12" \
    "route ~/repos/miapp work"
```

- [ ] **Step 2: Añadir los tests del teñido**

Al final de `tests/router_claude.bats`:

```bash
@test "tine el fondo antes de lanzar y lo devuelve al tema al salir" {
  make_profile ".claude-work" "ricardo@empresa.com"
  run_zsh "cd '$HOME/repos/miapp'; claude"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$(printf '\033]11;#171b12\007')"* ]]
  [[ "$output" == *"$(printf '\033]111\007')" ]]
}

@test "una cuenta equivocada no tine nada" {
  # El pintado va despues de _launch-check a proposito: un arranque bloqueado
  # no debe dejar rastro en el tab.
  make_profile ".claude-work" "tu-email@ejemplo.com"
  run_zsh "cd '$HOME/repos/miapp'; claude"
  [ "$status" -eq 5 ]
  [[ "$output" != *"$(printf '\033]11;')"* ]]
  [[ "$output" != *"$(printf '\033]111\007')"* ]]
}

@test "un perfil sin fondo no emite ningun escape" {
  make_profile ".claude" "tu-email@ejemplo.com"
  run_zsh "cd '$HOME'; claude"
  [ "$status" -eq 0 ]
  [[ "$output" != *"$(printf '\033]11;')"* ]]
  [[ "$output" != *"$(printf '\033]111\007')"* ]]
}

@test "despinta aunque Claude salga con codigo distinto de cero" {
  make_profile ".claude-work" "ricardo@empresa.com"
  cat > "$FAKE_BIN/claude" <<'FALSO'
#!/bin/sh
exit 3
FALSO
  chmod +x "$FAKE_BIN/claude"
  run_zsh "cd '$HOME/repos/miapp'; claude"
  [ "$status" -eq 3 ]
  [[ "$output" == *"$(printf '\033]111\007')" ]]
}
```

- [ ] **Step 3: Añadir el test del hook de salida en `tests/router_load.bats`**

Al final del archivo:

```bash
@test "el hook de salida despinta si una sesion quedo suspendida" {
  # El bloque always de claude() cubre la salida normal. Este hook cubre el
  # unico camino que no: suspender Claude con Ctrl-Z y cerrar el tab sin
  # volver a la sesion. Se simula dejando puesta la marca que ese bloque
  # habria vaciado.
  run_zsh "_car_tinted=1"
  [ "$output" = "$(printf '\033]111\007')" ]
}
```

El test que ya existe, `"cargar el router no escribe nada en la terminal"`, sigue valiendo
tal cual y ahora prueba algo más: que el guardia del hook funciona, porque sin él ese
`zshexit` escupiría un reset en toda shell de Ghostty.

- [ ] **Step 4: Correr los tests para verificar que fallan**

Run: `bats tests/router_claude.bats tests/router_load.bats`
Expected: fallan los 4 nuevos de `router_claude.bats` (no se emite ningún escape todavía) y
el nuevo de `router_load.bats` (`_car_tinted` no existe y el hook no está).

- [ ] **Step 5: Reescribir `shell/router.zsh`**

Reemplaza el archivo entero por:

```zsh
# claude-ghostty-router — integracion de sesion zsh.
# Se auto-desactiva fuera de Ghostty y si el CLI no esta instalado.

[[ $TERM == xterm-ghostty ]] || return 0
(( $+commands[claude-account] )) || return 0

autoload -Uz add-zsh-hook

# La lee `claude-account check` para saber si el router esta cargado en esta
# shell. Se exporta para que tambien se vea desde los procesos que arranque.
typeset -g CAR_ROUTER_LOADED=1
export CAR_ROUTER_LOADED

# 1 mientras el fondo esta tenido. El bloque `always` de claude() la vacia al
# despintar, asi que si al cerrar la shell sigue puesta es que ese bloque nunca
# llego a correr.
typeset -g _car_tinted=

# Red de seguridad para el unico camino que el bloque `always` no cubre:
# suspender la sesion con Ctrl-Z y cerrar el tab sin volver a ella. El guardia
# no es un detalle de eficiencia: sin el, cada shell de Ghostty escupiria un
# reset al salir aunque nunca hubiera corrido Claude.
_car_cleanup() {
  [[ -n $_car_tinted ]] || return 0
  claude-account _untint 2>/dev/null
}

# Sustituye a `claude` solo en sesiones de Ghostty. Toda la autoridad para negar
# el arranque vive aqui: si _launch-check falla, no se ejecuta nada.
#
# El titulo del tab no se toca: en el prompt es de Ghostty y durante la sesion
# es de Claude Code. La cuenta se ve en el badge, dentro de la sesion; el fondo
# tenido dice, desde fuera, que hay una sesion corriendo y de que perfil es.
claude() {
  local config_dir tint rc=0

  config_dir=$(claude-account _launch-check "$PWD") || return $?

  # Se tine despues de la verificacion: un arranque bloqueado no deja rastro.
  # Salida vacia = perfil sin fondo, y entonces tampoco hay que despintar.
  tint=$(claude-account _tint "$PWD" 2>/dev/null)

  {
    if [[ -n $tint ]]; then
      print -rn -- $tint
      _car_tinted=1
    fi

    if [[ -n $config_dir ]]; then
      CLAUDE_CONFIG_DIR=$config_dir command claude "$@"
    else
      command claude "$@"
    fi
    rc=$?
  } always {
    # `always` y no la linea siguiente: si Claude muere por SIGINT, zsh aborta
    # el resto de la funcion y el fondo se quedaria tenido. Por lo mismo rc
    # arranca en 0: en ese camino nunca llega a asignarse.
    if [[ -n $_car_tinted ]]; then
      claude-account _untint
      _car_tinted=
    fi
  }

  return $rc
}

add-zsh-hook zshexit _car_cleanup
```

- [ ] **Step 6: Correr los tests**

Run: `bats tests/router_claude.bats tests/router_load.bats`
Expected: 10 PASS en `router_claude.bats`, 5 PASS en `router_load.bats`.

- [ ] **Step 7: Suite completa**

Run: `bats tests/`
Expected: 0 `not ok`.

- [ ] **Step 8: Commit**

```bash
git add shell/router.zsh tests/router_claude.bats tests/router_load.bats
git commit -m "feat: el fondo del tab se tine mientras corre Claude

El badge dice que cuenta desde dentro de la sesion; el fondo dice que
hay sesion desde fuera. El despintado va en un bloque always para que un
SIGINT no deje el tab tenido."
```

---

### Task 5: Diagnóstico y documentación

Los campos cuarto y quinto son adyacentes, con la misma sintaxis `#rrggbb` y significados
opuestos. Intercambiarlos parsea limpio, sale con 0, y produce un badge ilegible y ningún
tinte: el fallo caracteristico de esta feature es **silencioso**, y este repo trata el
silencio como el peor resultado posible. `check` existe justo para eso.

**Files:**
- Modify: `bin/claude-account` (`cmd_check`), `tests/check.bats`, `routes.conf.example`, `README.md`

- [ ] **Step 0: Que `check` muestre los dos colores de cada perfil**

Primero el test. En `tests/check.bats`, después de `"todo en orden sale con 0"`:

```bash
@test "check muestra los dos colores de cada perfil" {
  # Los campos cuarto y quinto son adyacentes y con la misma sintaxis: un
  # intercambio parsea limpio y solo se nota mirando el resultado. Verlos aqui
  # es lo unico que convierte ese fallo silencioso en uno visible.
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com - -" \
    "profile work ~/.claude-work *@empresa.com #8fbc5a #171b12" \
    "route ~/repos/miapp work"
  perfiles_ok
  run "$CA" check
  [[ "$output" == *"badge #8fbc5a"* ]]
  [[ "$output" == *"fondo #171b12"* ]]
}
```

Ojo con el `setup()` de ese archivo: define su propia `write_conf` y `perfiles_ok` crea los
perfiles. Lee el archivo entero antes de tocarlo y respeta el orden que ya usa.

Luego, en `cmd_check`, dentro del bucle de `Perfiles`, después de la línea que reporta el
email (`car_ok "${CAR_P_NAME[$i]}: $email"` y su rama de fallo), añade una línea informativa
—no un `car_ok`, que contaria como comprobación— con los dos colores del perfil:

```bash
    printf '       badge %s · fondo %s\n' "${CAR_P_COLOR[$i]}" "${CAR_P_TINT[$i]}"
```

Es una línea informativa, con la misma sangría que ya usa el aviso de token por vencer.

- [ ] **Step 1: `routes.conf.example`**

Sustituye el bloque de comentario del `profile` y las dos líneas de ejemplo:

```
#   profile <nombre> <config-dir> [email-glob] [color-del-badge] [color-de-fondo]
#     email-glob: patron que DEBE cumplir la cuenta logueada. "-" = no verificar.
#     badge:      #rrggbb con el que se pinta el nombre del perfil en el badge
#                 que se ve dentro de Claude Code. "-" = sin color. Elige un
#                 tono LEGIBLE sobre el fondo de tu tema.
#     fondo:      #rrggbb del fondo del tab mientras corre Claude en una
#                 carpeta de ese perfil. "-" = no tenir. Elige un tinte APENAS
#                 PERCEPTIBLE sobre tu fondo habitual: se reconoce de reojo sin
#                 arruinar el tema. El color que sirve de badge ciega de fondo.
```

```
profile personal  ~/.claude       tu-email@ejemplo.com  -        -
profile work      ~/.claude-work  *@tuempresa.com       #e0a458  #171b12
```

- [ ] **Step 2: `README.md`**

Lee el README entero antes de tocarlo: describe el proyecto tal como quedó tras el badge, y
hay que añadirle el tinte sin contradecir nada de lo que ya dice.

Los puntos que hay que cubrir, sin prescribir la redacción exacta:

- La lista de viñetas de la introducción gana el tinte como señal complementaria del badge:
  el badge dice **qué cuenta** desde dentro de la sesión, el fondo dice **hay sesión** desde
  fuera. Un tab en el prompt y un tab con Claude corriendo hoy no se distinguen sin mirar el
  contenido.
- La sección de configuración documenta el quinto campo con la misma distinción que
  `routes.conf.example`: badge legible, fondo apenas perceptible. Es el error fácil de
  cometer y cuesta una frase evitarlo.
- La tabla de arquitectura gana la fila de `lib/ghostty.sh` y precisa la de `lib/badge.sh`:
  uno emite OSC al emulador, el otro SGR para Claude Code.
- Donde se describa `shell/router.zsh`, explicar que el despintado va en un bloque `always`
  para que un `SIGINT` no deje el tab teñido, y que el hook `zshexit` es la red para la
  sesión suspendida con Ctrl-Z.
- Actualizar el número de tests de la sección de Desarrollo con el real.

- [ ] **Step 3: Verificar el número de tests que pusiste**

Run: `bats tests/ 2>&1 | tail -3`
Comprueba que el número del README coincide con el que sale aquí.

- [ ] **Step 4: Commit**

```bash
git add bin/claude-account tests/check.bats routes.conf.example README.md
git commit -m "feat: check muestra los dos colores de cada perfil

Los campos son adyacentes, con la misma sintaxis y significados
opuestos: intercambiarlos parsea limpio. Verlos es lo que convierte
ese fallo silencioso en uno visible."
```

---

### Task 6: Verificación final

- [ ] **Step 1: Suite completa**

Run: `bats tests/`
Expected: 0 `not ok`, ningún test saltado.

- [ ] **Step 2: Lint**

Run: `shellcheck -s bash bin/claude-account install.sh lib/*.sh`
Expected: sin salida.

- [ ] **Step 3: Comprobar que ningún escape se emite fuera de su archivo**

Run: `grep -rn '033\[\|033\]' bin lib shell install.sh`
Expected: aciertos solo en `lib/ghostty.sh` (OSC) y `lib/badge.sh` (SGR).

- [ ] **Step 4: Comprobar que una config vieja sigue valiendo**

El quinto campo es opcional, y romper las configs existentes sería el peor fallo de este
cambio. Compruébalo de verdad, con una config de cuatro campos:

```bash
printf 'profile personal ~/.claude tu-email@ejemplo.com -\nprofile work ~/.claude-work *@empresa.com #e0a458\n' > "$BATS_TMPDIR/car-vieja.conf"
CAR_CONF="$BATS_TMPDIR/car-vieja.conf" ./bin/claude-account routes
CAR_CONF="$BATS_TMPDIR/car-vieja.conf" ./bin/claude-account _tint "$HOME"
rm -f "$BATS_TMPDIR/car-vieja.conf"
```
Expected: `routes` funciona sin errores, y `_tint` no emite nada ni falla.
(Si `BATS_TMPDIR` no está definida fuera de bats, usa cualquier directorio temporal.)

- [ ] **Step 5: Prueba manual en Ghostty**

Ningún test cubre esto, porque depende de un emulador real:

1. Añade un fondo a un perfil en tu `routes.conf` y abre un tab nuevo de Ghostty.
2. En el prompt: fondo del tema, título de Ghostty.
3. `cd` a una carpeta de ese perfil y lanza `claude` — el fondo se tiñe y el badge aparece.
4. Sal con `/exit`: el fondo vuelve al del tema.
5. Vuelve a entrar y sal con doble Ctrl-C: el fondo vuelve igual. Este es el camino que
   cubre el bloque `always`.
6. Entra, suspende con Ctrl-Z y cierra el tab. Abre uno nuevo: no hereda ningún color.

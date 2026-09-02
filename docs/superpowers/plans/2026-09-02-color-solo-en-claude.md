# El color solo mientras Claude corre — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el fondo de la terminal se tiña con el color del perfil solo mientras corre una sesión de Claude, y vuelva al color del tema al salir.

**Architecture:** El pintado deja de ocurrir en cada `precmd` y pasa a vivir dentro de la función `claude()` de `shell/router.zsh`, el único punto que sabe cuándo empieza y termina una sesión. `bin/claude-account` cambia su comando `_surface` (título + color) por dos comandos de color puro, `_tint` y `_untint`. El router deja de escribir títulos, lo que arrastra la eliminación de `ghostty_title`, `DISABLE_AUTO_TITLE`, la caché por directorio y el paso de `no-title` del instalador.

**Tech Stack:** bash 3.2 (`bin/`, `lib/`, `install.sh`), zsh (`shell/router.zsh`), bats-core para tests, shellcheck para lint.

**Spec:** [docs/superpowers/specs/2026-09-02-color-solo-en-claude-design.md](../specs/2026-09-02-color-solo-en-claude-design.md)

---

## Contexto para quien implemente

Este repo enruta carpetas a cuentas de Claude Code dentro de Ghostty. Tres reglas del
proyecto que hay que respetar en cada tarea:

1. **`lib/ghostty.sh` es el único sitio que emite secuencias OSC.** Ningún otro archivo
   escribe `\033]...` a mano. (Hoy `shell/router.zsh` incumple esto en `_car_cleanup`; la
   Task 4 lo arregla.)
2. **El pintado informa, no decide.** Los comandos de pintado nunca fallan ni bloquean nada.
   Quien bloquea el arranque de Claude es siempre `_launch-check`, y falla cerrado.
3. **bash 3.2.** Nada de `declare -A`, `${var^^}`, `mapfile` ni arrays asociativos en
   `bin/`, `lib/` e `install.sh`. `shell/router.zsh` sí es zsh y puede usar zsh.

Los tests corren con un `HOME` desechable (`tests/helper.bash`), así que nunca tocan la
máquina real. El repo está en 106 tests verdes antes de empezar.

Comandos que se usan en todo el plan:

```sh
bats tests/                                                        # toda la suite
bats tests/tint.bats                                               # un archivo
shellcheck -s bash bin/claude-account install.sh lib/*.sh          # lint
```

## Estructura de archivos

| Archivo | Qué pasa con él | Task |
|---|---|---|
| `lib/ghostty.sh` | Se queda solo con `ghostty_bg`. Se borran `ghostty_title`, `ghostty_sanitize`, `CAR_TITLE_MAX`. | 2 |
| `bin/claude-account` | `cmd_surface` → `cmd_tint` (solo color); nuevo `cmd_untint`; se va `mark`; `check` deja de exigir `no-title`. | 1, 3, 5 |
| `shell/router.zsh` | Pierde caché, `precmd`, `DISABLE_AUTO_TITLE`. El color pasa a `claude()`. | 4 |
| `install.sh` | Deja de añadir `no-title`; ofrece revertir el que ya puso. | 6 |
| `tests/surface.bats` | Se borra; nace `tests/tint.bats`. | 1 |
| `tests/ghostty.bats` | Pierde los 4 tests de título. | 2 |
| `tests/router_paint.bats` | Se reduce a los 2 tests de activación del router. | 4 |
| `tests/router_claude.bats` | Gana los 4 tests de teñido/despintado. | 4 |
| `tests/check.bats` | Pierde el test de `no-title`; los demás dejan de escribirlo. | 5 |
| `tests/install.bats` | Se ajusta a un instalador que no añade `no-title` y sí lo revierte. | 6 |
| `README.md` | Introducción, instalación, uso diario, arquitectura, seguridad, limitaciones. | 7 |

El orden importa: la Task 1 crea `_tint`/`_untint` antes de que la Task 4 los use, y la
Task 2 no puede borrar `ghostty_title` hasta que la Task 1 haya quitado su único llamador.

---

### Task 1: `_tint` y `_untint` en el CLI

Sustituye `_surface` (título + color) por dos comandos de color puro. `_tint` resuelve el
perfil de un directorio y emite su color; `_untint` emite el reset al tema y no necesita ni
directorio ni `routes.conf`.

**Files:**
- Create: `tests/tint.bats`
- Delete: `tests/surface.bats`
- Modify: `bin/claude-account:25-53` (`cmd_surface` → `cmd_tint` + `cmd_untint`), `bin/claude-account:270-283` (el `case` de `main`)

- [ ] **Step 1: Escribir los tests nuevos**

Crea `tests/tint.bats` con este contenido exacto:

```bash
setup() {
  load helper
  setup_fixture
  CA="$CAR_ROOT/bin/claude-account"
}

@test "tint emite el color del perfil resuelto" {
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/miapp work"
  mkdir -p "$HOME/repos/miapp"
  run "$CA" _tint "$HOME/repos/miapp"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]11;#171b12\007')" ]
}

@test "tint no emite titulo: el router ya no toca el titulo del tab" {
  write_conf \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/miapp work"
  mkdir -p "$HOME/repos/miapp"
  run "$CA" _tint "$HOME/repos/miapp"
  [[ "$output" != *"$(printf '\033]2;')"* ]]
}

@test "un perfil con color '-' no emite nada" {
  # Sin color no hay nada que tenir, y por tanto nada que despintar al salir:
  # router.zsh usa la salida vacia para saltarse el _untint.
  write_conf "profile personal ~/.claude tu-email@ejemplo.com -"
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
  # El pintado informa, no decide: quien avisa del error es _launch-check al
  # bloquear el arranque, con archivo y linea por stderr.
  write_conf "basura aqui"
  run "$CA" _tint "$HOME"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "tint funciona invocado a traves de un symlink" {
  # Asi es como se instala: ~/.local/bin/claude-account -> repo/bin/claude-account.
  # Si el CLI no resuelve el symlink, no encuentra sus propias librerias.
  write_conf \
    "profile work ~/.claude-work *@empresa.com #171b12" \
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
  # Corre en el camino de salida y en el hook zshexit: tiene que funcionar
  # aunque la config haya desaparecido o se haya roto mientras corria Claude.
  rm -f "$CAR_CONF"
  run "$CA" _untint
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033]111\007')" ]
}
```

Y borra el archivo viejo:

```bash
git rm tests/surface.bats
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

Run: `bats tests/tint.bats`
Expected: los 8 tests FALLAN con `claude-account: comando desconocido '_tint'` (y `'_untint'`).

- [ ] **Step 3: Reemplazar `cmd_surface` por `cmd_tint` y `cmd_untint`**

En `bin/claude-account`, sustituye el bloque completo de `cmd_surface` (líneas 25–53, desde
el comentario `# _surface <directorio>` hasta su `}`) por:

```bash
# _tint <directorio>
# Emite el color de fondo del perfil de ese directorio. Nunca falla: el pintado
# informa, no decide. Un routes.conf roto lo denuncia _launch-check al bloquear
# el arranque, con archivo y linea por stderr.
# Salida vacia significa "no hay nada que tenir", y router.zsh la usa para
# saltarse el _untint de salida.
cmd_tint() {
  local dir="${1:-$PWD}" record profile label pdir pglob color

  [ -f "$CAR_CONF" ] || return 0
  car_load_config "$CAR_CONF" 2>/dev/null || return 0
  record="$(resolve_route "$dir" 2>/dev/null)" || return 0

  # Todo el registro menos el color son campos que este comando no necesita.
  # shellcheck disable=SC2034
  IFS=$'\t' read -r profile label pdir pglob color <<< "$record"
  [ "$color" = "-" ] && return 0
  ghostty_bg "$color" || return 0
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

- [ ] **Step 4: Cambiar el `case` de `main`**

En `bin/claude-account`, dentro de `main()`, sustituye estas dos líneas:

```bash
    _surface)      cmd_surface "$@" ;;
```
```bash
    mark)          cmd_surface "$PWD" ;;
```

por, respectivamente:

```bash
    _tint)         cmd_tint "$@" ;;
    _untint)       cmd_untint ;;
```

y borra la línea de `mark` sin reemplazo. El `case` queda así:

```bash
  case "$command" in
    _tint)         cmd_tint "$@" ;;
    _untint)       cmd_untint ;;
    _launch-check) cmd_launch_check "$@" ;;
    which)         cmd_which "$@" ;;
    routes)        cmd_routes "$@" ;;
    status)        cmd_status "$@" ;;
    login)         cmd_login "$@" ;;
    check)         cmd_check "$@" ;;
    help|-h|--help) cmd_help ;;
    *)
      echo "claude-account: comando desconocido '$command'" >&2
      return 1
      ;;
  esac
```

- [ ] **Step 5: Quitar `mark` de la ayuda**

En `cmd_help`, borra la última línea del heredoc:

```
  claude-account mark           repinta la superficie actual
```

- [ ] **Step 6: Correr los tests**

Run: `bats tests/tint.bats && bats tests/cli.bats`
Expected: los 8 de `tint.bats` PASAN; `cli.bats` sigue verde.

- [ ] **Step 7: Lint**

Run: `shellcheck -s bash bin/claude-account`
Expected: sin salida.

- [ ] **Step 8: Commit**

```bash
git add bin/claude-account tests/tint.bats tests/surface.bats
git commit -m "feat: _tint y _untint reemplazan a _surface

El pintado pasa a ser solo color. El titulo deja de ser responsabilidad
del router, y con el se va el subcomando mark, que repintaba la
superficie en el prompt."
```

---

### Task 2: `lib/ghostty.sh` se queda solo con el color

Tras la Task 1 nadie llama a `ghostty_title`. Al no emitir nunca un título, la vía de
inyección de escapes por nombre de carpeta deja de existir en vez de quedar mitigada, y el
sanitizador que la mitigaba deja de tener sentido.

**Files:**
- Modify: `lib/ghostty.sh:1-19` (borrar `CAR_TITLE_MAX`, `ghostty_sanitize`, `ghostty_title`)
- Modify: `tests/ghostty.bats:1-32` (borrar los 4 tests de título)

- [ ] **Step 1: Verificar que de verdad no queda ningún llamador**

Run: `grep -rn 'ghostty_title\|ghostty_sanitize\|CAR_TITLE_MAX' bin lib shell install.sh tests`
Expected: solo aciertos en `lib/ghostty.sh` y `tests/ghostty.bats`. Si aparece cualquier otro
archivo, para: la Task 1 quedó incompleta.

- [ ] **Step 2: Borrar los tests de título**

En `tests/ghostty.bats`, borra los cuatro `@test` de título —`"el titulo sale como OSC 2
terminado en BEL"`, `"el separador UTF-8 sobrevive al saneo"`, `"el titulo elimina bytes de
control"` y `"el titulo se recorta a 60 caracteres"`— dejando el archivo así:

```bash
setup() {
  load helper
  setup_fixture
  source "$CAR_ROOT/lib/config.sh"
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
  run ghostty_bg "rojo; rm -rf /"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "un color con longitud incorrecta falla" {
  run ghostty_bg "#abc"
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 3: Reducir `lib/ghostty.sh`**

Reemplaza el archivo entero por:

```bash
# Unico emisor de secuencias de escape del proyecto.
# No sabe que es un perfil: recibe un color y emite bytes.
#
# El router no escribe titulos: el titulo del tab es de Ghostty cuando no hay
# sesion, y de Claude Code mientras la hay. Por eso aqui no hay OSC 2 ni el
# saneo que hacia falta para emitirlo sin abrir una via de inyeccion con el
# nombre de una carpeta: https://dgl.cx/2024/12/ghostty-terminal-title

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

Run: `bats tests/ghostty.bats && bats tests/tint.bats`
Expected: 4 PASS en `ghostty.bats`, 8 PASS en `tint.bats`.

- [ ] **Step 5: Lint**

Run: `shellcheck -s bash lib/ghostty.sh`
Expected: sin salida.

- [ ] **Step 6: Commit**

```bash
git add lib/ghostty.sh tests/ghostty.bats
git commit -m "refactor: ghostty.sh solo emite color

Sin titulo emitido, el saneo de nombres de carpeta deja de tener
llamadores y la via de inyeccion que mitigaba deja de existir."
```

---

### Task 3: `_launch-check` sin cambios — solo verificación

No hay nada que modificar en `cmd_launch_check`. Esta tarea existe para dejar constancia de
que se comprobó, porque la Task 4 depende de su contrato exacto: **imprime el config-dir, o
nada, y falla con un código distinto de cero cuando bloquea.**

**Files:**
- Read only: `bin/claude-account` (`cmd_launch_check`)

- [ ] **Step 1: Confirmar que la suite de arranque sigue verde**

Run: `bats tests/launch_check.bats tests/router_claude.bats`
Expected: todo PASS. Si algo falla aquí, arréglalo antes de seguir: la Task 4 reescribe la
función `claude()` y necesita una base verde para saber qué rompió.

- [ ] **Step 2: Sin commit**

Esta tarea no cambia archivos.

---

### Task 4: El color pasa a la función `claude()`

El corazón del cambio. `shell/router.zsh` deja de pintar en cada prompt y pinta solo
alrededor de la sesión.

**Files:**
- Modify: `shell/router.zsh` (archivo entero)
- Modify: `tests/router_paint.bats` (reducir a los 2 tests de activación)
- Modify: `tests/router_claude.bats` (añadir 4 tests de teñido)

- [ ] **Step 1: Reducir `tests/router_paint.bats`**

De los 7 tests, cinco prueban maquinaria que va a desaparecer (caché, invalidación por
mtime, `DISABLE_AUTO_TITLE`, pintado en `precmd`, reset por `zshexit` tras pintar en el
prompt). Reemplaza el archivo entero por:

```bash
setup() {
  load helper
  setup_fixture
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/miapp work"
  mkdir -p "$HOME/repos/miapp"
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

@test "cargar el router no tine nada: en el prompt el tab es un tab normal" {
  # Antes se pintaba en cada precmd y al hacer source. Ahora el color solo
  # existe mientras corre Claude.
  run_zsh "cd '$HOME/repos/miapp'"
  [ -z "$output" ]
}

@test "el router no toca el titulo del tab" {
  run_zsh "cd '$HOME/repos/miapp'"
  [[ "$output" != *"$(printf '\033]2;')"* ]]
}

@test "el hook de salida despinta si una sesion quedo suspendida" {
  # El bloque always de claude() cubre la salida normal. Este hook cubre el
  # unico camino que no: suspender Claude con Ctrl-Z y cerrar el tab sin
  # volver a la sesion. Se simula dejando puesta la marca que ese bloque
  # habria vaciado.
  run_zsh "_car_tinted=1"
  [ "$output" = "$(printf '\033]111\007')" ]
}
```

- [ ] **Step 2: Añadir los tests de teñido a `tests/router_claude.bats`**

Añade estos cuatro `@test` al final del archivo, sin tocar los que ya están:

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

@test "un perfil con color '-' no emite ningun escape" {
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

- [ ] **Step 3: Correr los tests para verificar que fallan**

Run: `bats tests/router_paint.bats tests/router_claude.bats`
Expected: FALLAN los 3 nuevos de `router_paint.bats` (el router todavía pinta al hacer
source y `_car_tinted` no existe) y los 4 nuevos de `router_claude.bats` (todavía se llama a `_surface`, que ya no
existe, así que no se emite ningún color).

- [ ] **Step 4: Reescribir `shell/router.zsh`**

Reemplaza el archivo entero por:

```zsh
# claude-ghostty-router — integracion de sesion zsh.
# Se auto-desactiva fuera de Ghostty y si el CLI no esta instalado.

[[ $TERM == xterm-ghostty ]] || return 0
(( $+commands[claude-account] )) || return 0

autoload -Uz add-zsh-hook

typeset -g CAR_ROUTER_LOADED=1
export CAR_ROUTER_LOADED

# 1 mientras el fondo esta tenido. El bloque `always` de claude() lo vacia al
# despintar, asi que si al cerrar la shell sigue puesto es que ese bloque nunca
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
# El color del perfil es la unica marca del tab, y dura exactamente lo que dura
# la sesion. El titulo no se toca: mientras Claude corre es suyo, y en el prompt
# es de Ghostty.
claude() {
  local config_dir tint rc=0

  config_dir=$(claude-account _launch-check "$PWD") || return $?

  # Se tine despues de la verificacion: un arranque bloqueado no deja rastro.
  # Salida vacia = perfil sin color, y entonces tampoco hay que despintar.
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
    # el resto de la funcion y el color se quedaria pegado al tab. Por lo mismo
    # rc arranca en 0: en ese camino nunca llega a asignarse.
    if [[ -n $_car_tinted ]]; then
      claude-account _untint
      _car_tinted=
    fi
  }

  return $rc
}

add-zsh-hook zshexit _car_cleanup
```

- [ ] **Step 5: Correr los tests**

Run: `bats tests/router_paint.bats tests/router_claude.bats`
Expected: 5 PASS en `router_paint.bats`, 10 PASS en `router_claude.bats`.

- [ ] **Step 6: Commit**

```bash
git add shell/router.zsh tests/router_paint.bats tests/router_claude.bats
git commit -m "feat: el color solo mientras Claude corre

El pintado sale de precmd y entra en claude(), con el despintado en un
bloque always para que un SIGINT no deje el tab tenido. Se van la cache
por directorio, su invalidacion por mtime y DISABLE_AUTO_TITLE: sin
pintado en cada prompt no tienen razon de ser."
```

---

### Task 5: `check` deja de exigir `no-title`

El diagnóstico comprueba que Ghostty tenga `no-title` para que no pise nuestro título.
Ya no hay título nuestro que proteger.

**Files:**
- Modify: `bin/claude-account:215-224` (el bloque de `$CAR_GHOSTTY_CONF` en `cmd_check`)
- Modify: `bin/claude-account:214` (`CAR_GHOSTTY_CONF`, si queda sin uso)
- Modify: `tests/check.bats` (borrar el test de `no-title` y las escrituras del archivo)

- [ ] **Step 1: Ajustar `tests/check.bats`**

Borra el `@test "sin no-title en la config de Ghostty avisa"` completo. En los cinco tests
restantes, borra la línea `printf 'shell-integration-features = ...' > "$CAR_GHOSTTY_CONF"`
y, en `setup()`, la línea `export CAR_GHOSTTY_CONF="$BATS_TEST_TMPDIR/config.ghostty"`.
El archivo queda así:

```bash
setup() {
  load helper
  setup_fixture
  CA="$CAR_ROOT/bin/claude-account"
  write_conf \
    "profile personal ~/.claude tu-email@ejemplo.com -" \
    "profile work ~/.claude-work *@empresa.com #171b12" \
    "route ~/repos/miapp work"
}

@test "todo en orden sale con 0" {
  make_profile ".claude" "tu-email@ejemplo.com"
  make_profile ".claude-work" "ricardo@empresa.com"
  export CAR_ROUTER_LOADED=1
  run "$CA" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"routes.conf valido"* ]]
}

@test "check no mira la config de Ghostty" {
  # El router ya no escribe titulos, asi que no-title dejo de hacer falta.
  make_profile ".claude" "tu-email@ejemplo.com"
  make_profile ".claude-work" "ricardo@empresa.com"
  export CAR_ROUTER_LOADED=1
  run "$CA" check
  [ "$status" -eq 0 ]
  [[ "$output" != *"no-title"* ]]
  [[ "$output" != *"Ghostty"* ]]
}

@test "un perfil sin sesion hace fallar el check" {
  make_profile ".claude" "tu-email@ejemplo.com"
  make_profile ".claude-work"
  export CAR_ROUTER_LOADED=1
  run "$CA" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"work"* ]]
  [[ "$output" == *"sin sesion"* ]]
}

@test "un email que no cumple su glob hace fallar el check" {
  make_profile ".claude" "tu-email@ejemplo.com"
  make_profile ".claude-work" "tu-email@ejemplo.com"
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
  export CAR_ROUTER_LOADED=1
  run "$CA" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"misma cuenta"* ]]
}

@test "sin el router cargado en la sesion avisa" {
  make_profile ".claude" "tu-email@ejemplo.com"
  make_profile ".claude-work" "ricardo@empresa.com"
  run env -u CAR_ROUTER_LOADED "$CA" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"router no esta cargado"* ]]
}
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

Run: `bats tests/check.bats`
Expected: FALLA `"check no mira la config de Ghostty"` — el `check` actual imprime
`FALLA no encuentro la config de Ghostty en ...` porque el archivo ya no se crea.

- [ ] **Step 3: Quitar el bloque de Ghostty de `cmd_check`**

En `bin/claude-account`, borra este bloque entero de `cmd_check`:

```bash
  if [ -f "$CAR_GHOSTTY_CONF" ]; then
    if grep -q 'no-title' "$CAR_GHOSTTY_CONF"; then
      car_ok "Ghostty tiene no-title en shell-integration-features"
    else
      car_fail "Ghostty reescribira el titulo: falta no-title en shell-integration-features"
    fi
  else
    car_fail "no encuentro la config de Ghostty en $CAR_GHOSTTY_CONF"
  fi
```

Borra también la línea que define la variable, que se queda sin ningún uso:

```bash
CAR_GHOSTTY_CONF="${CAR_GHOSTTY_CONF:-$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty}"
```

- [ ] **Step 4: Correr los tests**

Run: `bats tests/check.bats`
Expected: 6 PASS.

- [ ] **Step 5: Lint**

Run: `shellcheck -s bash bin/claude-account`
Expected: sin salida.

- [ ] **Step 6: Commit**

```bash
git add bin/claude-account tests/check.bats
git commit -m "refactor: check deja de exigir no-title en Ghostty

Sin titulo escrito por el router, no hay nada que proteger de que
Ghostty lo pise."
```

---

### Task 6: El instalador deja de poner `no-title` y ofrece revertirlo

Mientras `no-title` siga en la config de Ghostty, el usuario no ve el comando en curso en el
título del tab, y ahora sin ninguna contrapartida. El instalador reconoce su propia marca y
ofrece quitarla.

**Files:**
- Modify: `install.sh:12` (`FEATURES`, queda sin uso), `install.sh:58-67` (bloque de instalación de `no-title`)
- Modify: `tests/install.bats:12-19` y `:33-52`

- [ ] **Step 1: Ajustar `tests/install.bats`**

Sustituye los tests `"instala el enlace, la config, la linea del zshrc y no-title"`,
`"respalda la config de Ghostty antes de tocarla"` y `"uninstall revierte enlace, linea y
no-title"` por estos cuatro. El resto del archivo no se toca:

```bash
@test "instala el enlace, la config y la linea del zshrc" {
  run "$CAR_ROOT/install.sh" --yes
  [ "$status" -eq 0 ]
  [ -L "$HOME/.local/bin/claude-account" ]
  [ -f "$HOME/.config/claude-ghostty-router/routes.conf" ]
  grep -q "router.zsh" "$HOME/.zshrc"
}

@test "no añade no-title a la config de Ghostty" {
  run "$CAR_ROOT/install.sh" --yes
  [ "$status" -eq 0 ]
  run grep -c "no-title" "$CAR_GHOSTTY_CONF"
  [ "$output" = "0" ]
}

@test "revierte el no-title que dejo una version anterior, con backup" {
  # Migracion: el instalador viejo metia esta linea con su marca al final.
  printf '\nshell-integration-features = cursor,no-title,path  # claude-ghostty-router\n' \
    >> "$CAR_GHOSTTY_CONF"
  run "$CAR_ROOT/install.sh" --yes
  [ "$status" -eq 0 ]
  run grep -c "no-title" "$CAR_GHOSTTY_CONF"
  [ "$output" = "0" ]
  [ -f "$CAR_GHOSTTY_CONF.bak" ]
  run grep -c "no-title" "$CAR_GHOSTTY_CONF.bak"
  [ "$output" = "1" ]
}

@test "no toca una linea de Ghostty que no sea nuestra" {
  # Sin la marca no es nuestra: el usuario pudo poner no-title por su cuenta.
  printf 'shell-integration-features = no-title\n' > "$CAR_GHOSTTY_CONF"
  run "$CAR_ROOT/install.sh" --yes
  [ "$status" -eq 0 ]
  run grep -c "no-title" "$CAR_GHOSTTY_CONF"
  [ "$output" = "1" ]
}

@test "uninstall revierte enlace, linea y no-title" {
  # El no-title se escribe DESPUES de instalar: install.sh --yes ahora lo
  # revierte el solo, y entonces este test no probaria nada de uninstall.
  "$CAR_ROOT/install.sh" --yes
  printf '\nshell-integration-features = no-title  # claude-ghostty-router\n' \
    >> "$CAR_GHOSTTY_CONF"
  run "$CAR_ROOT/install.sh" --uninstall --yes
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/bin/claude-account" ]
  run grep -c "router.zsh" "$HOME/.zshrc"
  [ "$output" = "0" ]
  run grep -c "no-title" "$CAR_GHOSTTY_CONF"
  [ "$output" = "0" ]
}
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

Run: `bats tests/install.bats`
Expected: FALLAN `"no añade no-title a la config de Ghostty"` (el instalador todavía lo
añade) y `"revierte el no-title que dejo una version anterior, con backup"` (todavía no
revierte nada al instalar).

- [ ] **Step 3: Sustituir el bloque de instalación por uno de migración**

En `install.sh`, dentro de `instalar()`, reemplaza este bloque:

```bash
  if [ -f "$GHOSTTY_CONF" ] && grep -q 'no-title' "$GHOSTTY_CONF"; then
    echo "ok  Ghostty ya tiene no-title"
  elif confirmar "Poner no-title en la config de Ghostty (con backup)?"; then
    [ -f "$GHOSTTY_CONF" ] && cp "$GHOSTTY_CONF" "$GHOSTTY_CONF.bak"
    printf '\n%s  %s\n' "$FEATURES" "$MARCA" >> "$GHOSTTY_CONF"
    echo "ok  no-title agregado (backup en $GHOSTTY_CONF.bak)"
  fi
```

por:

```bash
  # Migracion desde la version que marcaba el titulo del tab: ese marcado
  # necesitaba no-title para que Ghostty no lo pisara. Ya no hay titulo
  # nuestro, y mientras esa linea siga puesta el usuario no ve el comando en
  # curso en el titulo a cambio de nada. Solo se toca la linea con nuestra
  # marca: un no-title que el usuario puso por su cuenta no es asunto nuestro.
  if [ -f "$GHOSTTY_CONF" ] && grep -qF "$MARCA" "$GHOSTTY_CONF"; then
    if confirmar "Quitar el no-title que puso una version anterior (con backup)?"; then
      cp "$GHOSTTY_CONF" "$GHOSTTY_CONF.bak"
      grep -vF "$MARCA" "$GHOSTTY_CONF" > "$GHOSTTY_CONF.tmp" || true
      mv "$GHOSTTY_CONF.tmp" "$GHOSTTY_CONF"
      echo "ok  no-title revertido (backup en $GHOSTTY_CONF.bak)"
    fi
  fi
```

Borra también la línea que define `FEATURES`, que se queda sin uso:

```bash
FEATURES="shell-integration-features = cursor,no-sudo,no-title,no-ssh-env,no-ssh-terminfo,path"
```

`desinstalar()` no se toca: su bloque de reversión sigue haciendo falta para las máquinas
que aún tengan la línea.

- [ ] **Step 4: Correr los tests**

Run: `bats tests/install.bats`
Expected: 9 PASS.

- [ ] **Step 5: Lint**

Run: `shellcheck -s bash install.sh`
Expected: sin salida.

- [ ] **Step 6: Commit**

```bash
git add install.sh tests/install.bats
git commit -m "feat: el instalador revierte el no-title que ya no hace falta

Deja de añadirlo, y ofrece quitar el que puso una version anterior para
devolver el titulo del comando en curso de Ghostty."
```

---

### Task 7: README

El README abre afirmando que cada tab muestra su cuenta «en su título y en su color de
fondo». Deja de ser cierto en cuanto la Task 4 entra.

**Files:**
- Modify: `README.md` (introducción, instalación, uso diario, cómo decide, arquitectura, seguridad, limitaciones)

- [ ] **Step 1: Corregir la introducción**

Sustituye las tres viñetas de arriba por:

```markdown
- Mientras corre Claude, **el fondo del tab toma el color de la cuenta**. Al salir, vuelve
  al color de tu tema.
- Si la cuenta logueada no es la esperada para esa carpeta, **Claude no arranca**.
- Fuera de Ghostty todo se comporta exactamente como antes.
```

Y en la sección «El problema», sustituye la frase final:

```markdown
Si trabajas con varios proyectos en tabs distintos de la misma ventana, lanzar Claude en el
proyecto equivocado con la cuenta equivocada es silencioso.
```

- [ ] **Step 2: Corregir la instalación**

La lista de pasos pasa de cinco a cuatro: borra el punto 4 (`Pone no-title en...`) y
renumera. Sustituye los dos párrafos que lo explicaban —el que empieza «Ese paso 4 hace
falta porque...» hasta «...y solo dentro de Ghostty.»— por:

```markdown
Si vienes de una versión anterior, el instalador detecta el `no-title` que dejó en tu config
de Ghostty y ofrece quitarlo, con backup: ya no hace falta, y mientras siga ahí Ghostty no te
muestra el comando en curso en el título.
```

- [ ] **Step 3: Corregir la descripción del campo `color`**

En la sección «Configuración», sustituye la viñeta del color por:

```markdown
- `color` es el fondo `#rrggbb` **mientras corre Claude** en una carpeta de ese perfil. `-`
  no tiñe nada. Conviene un tinte apenas perceptible sobre tu fondo habitual: reconocible de
  reojo, sin arruinar el tema.
```

- [ ] **Step 4: Quitar `mark` del uso diario**

En el bloque de «Uso diario», borra la línea:

```
claude-account mark           # repinta la superficie actual
```

- [ ] **Step 5: Corregir «Cuando bloquea»**

Sustituye el párrafo que empieza «Un `routes.conf` roto además se *ve*...» por:

```markdown
Un `routes.conf` roto se explica solo: el mensaje de error trae el archivo y la línea del
fallo. Quien detiene el arranque es siempre el shim, nunca el pintado.
```

- [ ] **Step 6: Corregir la arquitectura**

En la tabla, sustituye la fila de `lib/ghostty.sh`:

```markdown
| `lib/ghostty.sh` | Único emisor de secuencias OSC del proyecto. Solo color. |
```

Y sustituye los tres párrafos que siguen a la tabla —desde «`shell/router.zsh` se
auto-desactiva...» hasta «...que nadie comprobó.»— por:

```markdown
`shell/router.zsh` se auto-desactiva si `TERM != xterm-ghostty`, así que no afecta a scripts,
cron ni a la terminal integrada de un editor. No hace nada en el prompt: todo su trabajo
ocurre alrededor de la sesión de Claude, que es el único momento en que el color dice algo.

El despintado va en un bloque `always` de zsh, no en la línea siguiente a `command claude`.
Si Claude muere por `SIGINT`, zsh aborta el resto de la función; `always` corre igual, y el
tab no se queda teñido.

**El hook nunca exporta `CLAUDE_CONFIG_DIR`.** La variable se define únicamente en el proceso
de Claude ya verificado, para que ningún script que esquive la función acabe corriendo con un
perfil que nadie comprobó.
```

- [ ] **Step 7: Corregir Seguridad**

Sustituye la sección entera por:

```markdown
### Seguridad

El router no escribe títulos, así que el nombre de una carpeta nunca entra en una secuencia
de escape. Esa era la única vía de inyección del proyecto, y
[ya hubo CVEs de esto en Ghostty](https://dgl.cx/2024/12/ghostty-terminal-title): ahora no
existe en vez de estar mitigada. El color se valida contra `#rrggbb` antes de entrar en una
secuencia OSC.
```

- [ ] **Step 8: Corregir las limitaciones**

Borra la última viñeta («**El título deja de mostrar el comando en curso.**...»): con este
cambio el título vuelve a ser de Ghostty.

- [ ] **Step 9: Actualizar el número de tests**

En la sección «Desarrollo», sustituye `bats tests/    # 106 tests` por el número real. Sácalo
de:

Run: `bats tests/ 2>&1 | tail -3`

- [ ] **Step 10: Commit**

```bash
git add README.md
git commit -m "docs: README refleja el color como unica marca del tab"
```

---

### Task 8: Verificación final

- [ ] **Step 1: Suite completa**

Run: `bats tests/`
Expected: todo verde, sin `not ok` ni tests saltados.

- [ ] **Step 2: Lint completo**

Run: `shellcheck -s bash bin/claude-account install.sh lib/*.sh`
Expected: sin salida.

- [ ] **Step 3: Comprobar que no queda ninguna referencia muerta**

Run: `grep -rn 'cmd_surface\|_surface\|ghostty_title\|ghostty_sanitize\|CAR_TITLE_MAX\|DISABLE_AUTO_TITLE\|_car_paint\|_car_cache\|FEATURES=' bin lib shell tests install.sh README.md`
Expected: sin salida. (Los `docs/superpowers/` quedan fuera a propósito: son el registro
histórico de cómo se construyó, y no se reescriben.)

- [ ] **Step 4: Prueba manual en Ghostty**

Esto no lo cubre ningún test, porque depende de un emulador real:

1. Abre un tab nuevo de Ghostty (para cargar el router nuevo).
2. Comprueba que el tab está con el color de tu tema y con el título de Ghostty.
3. `cd` a una carpeta con un perfil de color asignado y lanza `claude`.
4. El fondo se tiñe.
5. Sal con `/exit`. El fondo vuelve al del tema.
6. Vuelve a entrar y sal con doble Ctrl-C. El fondo vuelve al del tema igual — este es el
   camino que cubre el bloque `always`.
7. Entra, suspende con Ctrl-Z, y cierra el tab. Abre uno nuevo: no hereda ningún color.

- [ ] **Step 5: Commit final si algo quedó suelto**

Si los pasos anteriores no cambiaron nada, no hay commit. Si sí:

```bash
git add -A
git commit -m "fix: <lo que apareciera en la verificacion>"
```

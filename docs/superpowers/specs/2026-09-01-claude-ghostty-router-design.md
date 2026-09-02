# claude-ghostty-router — Diseño

**Fecha:** 2026-09-01
**Estado:** aprobado, pendiente de plan de implementación
**Inspirado en:** [kirlts/claude-account-router](https://github.com/kirlts/claude-account-router) (reimplementación, no fork)

## Problema

Claude Code toma la cuenta de un único directorio de configuración (`~/.claude` por
defecto, o `CLAUDE_CONFIG_DIR`). Con dos cuentas —personal y trabajo— hay que cerrar y
abrir sesión a mano para cambiar, y nada indica con qué cuenta está corriendo una sesión.

El flujo de trabajo real agrava el problema: varios proyectos abiertos en tabs y splits de
la misma ventana de Ghostty, saltando entre ellos. Un tab en reposo no dice a qué cuenta
pertenece, y lanzar Claude en el proyecto equivocado con la cuenta equivocada es silencioso.

`claude-account-router` resuelve esto para VS Code, enganchándose a
`claudeCode.claudeProcessWrapper`. Ghostty no tiene API de plugins ni hook equivalente, así
que la solución se construye con las piezas que sí ofrece: variables de entorno de sesión,
integración de shell y secuencias OSC.

## Objetivo

Que cada carpeta use automáticamente la cuenta Claude que le corresponde, que la cuenta
activa sea visible de un vistazo en cada tab, y que Claude **no arranque** si la cuenta
logueada no es la esperada.

**Alcance: solo dentro de Ghostty.** Fuera de Ghostty (terminal integrada de VS Code,
scripts, cron) todo se comporta exactamente como hoy.

## Contexto verificado de la máquina

Comprobado el 2026-09-01 en el equipo del usuario:

| Hecho | Valor | Cómo se comprobó |
|---|---|---|
| Ghostty | 1.3.1 (stable), macOS | `ghostty --version` |
| OSC 10–12 (colores dinámicos) | Soportados | [docs de Ghostty](https://ghostty.org/docs/vt/osc/1x) |
| `ghostty +new-window` | **No soportado en macOS** | `ghostty +new-window --help` |
| Acciones de keybind útiles | `set_surface_title`, `set_tab_title`, `new_tab`, `new_split`, `reload_config` | `ghostty +list-actions` |
| `shell-integration-features` por defecto | `cursor,no-sudo,title,no-ssh-env,no-ssh-terminfo,path` | `ghostty +show-config --default` |
| Detección de sesión Ghostty | `TERM=xterm-ghostty`, `GHOSTTY_RESOURCES_DIR`, `GHOSTTY_BIN_DIR`, `GHOSTTY_SHELL_FEATURES` | `env` |
| Identidad de cuenta | `~/.claude.json` → `oauthAccount.emailAddress` | lectura del archivo |
| Binario Claude | `~/.local/bin/claude` (Mach-O nativo) | `file` |
| Config actual de Ghostty | una línea: `theme = Github Dark Default` | lectura del archivo |
| Perfiles existentes | solo `~/.claude` | `ls -d ~/.claude*` |
| Herramientas | `shellcheck` presente; `bats` **ausente**; `python3` presente | `which` |

El `title` activo en `shell-integration-features` reescribe el título en cada prompt y
pisaría el título del router: por eso el instalador lo cambia a `no-title`.

## Arquitectura

Cuatro unidades. Una regla que las separa: **solo el núcleo sabe de routing, solo la capa
Ghostty emite escapes, solo el shim decide bloquear.**

### `lib/` — Núcleo puro

Sin efectos secundarios: entran datos, salen datos. Testeable con un `HOME` falso.

- **`config.sh`** — parsea `routes.conf` a perfiles y rutas. Depende solo del archivo.
- **`resolve.sh`** — `directorio → perfil`. Depende de `config.sh` y `git`.
- **`identity.sh`** — `perfil → email logueado`, leyendo el `.claude.json` de ese perfil.
  Depende de `python3` para el JSON.

### `lib/ghostty.sh` — Capa de presentación

Lo único que emite secuencias OSC: título de superficie (OSC 2), fondo (OSC 11), reset
(OSC 111). No conoce el concepto de perfil: recibe *nombre* y *color*, y pinta. Se testea
capturando stdout y comparando bytes.

### `bin/claude-account` — CLI

| Comando | Qué hace |
|---|---|
| `claude-account` | Estado: perfiles, email logueado en cada uno, perfil del `cwd` |
| `routes` | Mapa carpeta → perfil |
| `which [dir]` | Perfil de un directorio (una línea; pensado para scripts y tests) |
| `check` | Diagnóstico completo: config válida, hook cargado, `no-title` aplicado, cada perfil logueado y coincidente, tokens por expirar, perfiles con email duplicado |
| `login <perfil>` | Ejecuta el binario real con el `CLAUDE_CONFIG_DIR` de ese perfil para completar el login. **Es la única entrada que omite la verificación**, y tiene que serlo: su propósito es crear la sesión que después se verifica. Un perfil vacío nunca podría loguearse si `login` también bloqueara |
| `mark` | Repinta la superficie actual (útil para verificar a mano) |

Es la cara humana del núcleo; no participa en el arranque de Claude.

### `shell/router.zsh` — Integración de sesión

Se carga desde `.zshrc` y **se auto-desactiva si `TERM != xterm-ghostty`**. Aporta:

- **Hook `chpwd` + init**: al entrar a un directorio resuelve el perfil y repinta *esa*
  superficie (título + fondo). Caché en memoria por directorio, invalidada por `mtime` de
  `routes.conf`, para no pagar un `git` en cada `cd`.
- **Hook `zshexit`**: reset del fondo al salir.
- **Función `claude()`**: verifica y bloquea, o ejecuta el binario real con el
  `CLAUDE_CONFIG_DIR` del perfil.

El shim es una función de shell y no un ejecutable en el PATH, precisamente porque el
alcance es "solo Ghostty": así no afecta scripts, cron ni la terminal de VS Code, y no
compite con `~/.local/bin/claude`.

## Configuración

`~/.config/claude-ghostty-router/routes.conf`:

```conf
# profile <nombre> <config-dir>    <email-glob>        <fondo-hex>
profile personal  ~/.claude         royarzun@gmail.com  -
profile work      ~/.claude-work    *@tuempresa.com     #171b12

# route <ruta>  <perfil>     — gana la primera declarada
route ~/repos/trazaambiental-backend  work
route ~/repos/sotos-*                 work
```

Decisiones:

- **El fondo se declara literal, no se calcula.** `-` significa "no toques nada" (reset al
  tema). Con el tema Github Dark Default (`#0d1117`), un `#171b12` es un verde-oliva apenas
  perceptible: reconocible de reojo sin arruinar el tema. Sin mezclas automáticas de color.
- **`personal` es el perfil por defecto.** Toda carpeta sin ruta cae ahí, sin bloqueo y sin
  tinte: se comporta como hoy.
- **Primera ruta declarada gana**, lo que permite excepciones anidadas declarando la más
  específica antes.

**Valores pendientes de definir por el usuario al instalar:** el email de la cuenta de
trabajo (`*@tuempresa.com` es un marcador de posición), el directorio del perfil de trabajo
(`~/.claude-work` es la propuesta) y qué repos van a `work`.

## Flujos

### A — Entrar a una carpeta

1. `chpwd` dispara.
2. Si el directorio está en caché y `routes.conf` no cambió (`mtime`), se usa el cacheado.
3. Si no: se busca prefijo de ruta. Si ninguno matchea, se resuelve la raíz del repo git
   (y para worktrees el repo principal vía `git rev-parse --git-common-dir`) y se reintenta
   con esa raíz. Si nada matchea → perfil por defecto.
4. Se pinta **esa superficie**: título `work · trazaambiental-backend`, fondo `#171b12`.

Cada tab conserva su propio color y título: el estado es por superficie, no por ventana.

### B — Ejecutar `claude`

1. Si `TERM != xterm-ghostty` → paso directo al binario real, sin tocar nada.
2. Se resuelve el perfil de `$PWD` (mismo núcleo, misma caché).
3. Se lee el email realmente logueado en ese perfil.
4. Se compara contra el glob del perfil:
   - **coincide** → se ejecuta Claude con el `CLAUDE_CONFIG_DIR` de ese perfil;
   - **no coincide, no hay sesión, o el archivo es ilegible** → no arranca.
5. Al salir, se repinta el tab (Claude Code toca el título mientras corre).

### Decisión: el hook no exporta `CLAUDE_CONFIG_DIR`

El hook solo pinta. La variable se define únicamente en el proceso de Claude ya verificado.
Exportarla a la shell haría que cualquier script que invoque `claude` —esquivando la
función— corriera con un perfil que nadie verificó, que es justo lo que el diseño impide.
Los subprocesos que Claude lance sí la heredan, que es el comportamiento correcto.

## Errores y casos borde

Principio único: **si no se puede verificar, no arranca.** La ambigüedad se resuelve
bloqueando, nunca adivinando.

| Situación | Shim (`claude`) | Hook (pintado) |
|---|---|---|
| Email logueado ≠ glob esperado | **Bloquea.** Muestra esperado vs. encontrado + `claude-account login work` | Pinta normal |
| Perfil sin sesión (`.claude.json` ausente o sin `oauthAccount`) | **Bloquea.** "perfil `work` sin sesión iniciada" | Pinta normal |
| Config-dir del perfil no existe | **Bloquea.** Perfil declarado pero no instalado | Pinta normal |
| `routes.conf` con sintaxis inválida | **Bloquea.** Señala línea y motivo | Título `⚠ routes.conf inválido`, sin tinte |
| `routes.conf` no existe | Paso directo (todo es `personal`, como hoy) | No pinta |
| `python3` no disponible | **Bloquea.** Sin verificación no hay arranque | No pinta |
| `cwd` borrado o ilegible | Bloquea | No revienta la shell |
| Token expirado (`expiresAt` pasado) | **Deja pasar**: la identidad se lee igual y Claude refresca solo. `check` lo avisa | — |
| Sesión no-Ghostty | Paso directo | Inactivo |

Dos consecuencias del diseño:

- **El hook nunca bloquea.** No puede y no debe: pintar es informar. Toda la autoridad para
  negar el arranque vive en el shim. Un `routes.conf` roto se *ve* en el título, pero lo que
  detiene es el shim.
- **Restauración del fondo**: al volver a una carpeta `personal` se emite OSC 111 (reset al
  tema); también al salir de la shell vía `zshexit`.

**Sin válvula de escape.** Se descartó `CLAUDE_ROUTER_OFF=1`: si la verificación falla, se
arregla la configuración.

## Seguridad

El título se construye a partir de un nombre de carpeta, y una carpeta puede contener bytes
de control en su nombre. Un título sin sanear es una vía de inyección de secuencias de
escape —[ya hubo CVEs de esto en Ghostty](https://dgl.cx/2024/12/ghostty-terminal-title)—.
`ghostty.sh` filtra bytes de control y recorta el título a un largo fijo antes de emitirlo.
El color se valida contra `^#[0-9a-fA-F]{6}$` antes de entrar en una secuencia OSC.

Ninguna pieza escribe, copia ni transmite credenciales: `identity.sh` solo **lee** el campo
`oauthAccount.emailAddress`. Los tokens no se leen nunca.

## Testing

**Herramienta:** `bats-core` (`brew install bats-core`). `shellcheck` ya está instalado y
corre sobre todo el código shell.

**Fase 0, antes de escribir código: un experimento.** El diseño asume que con
`CLAUDE_CONFIG_DIR=~/.claude-work` Claude Code escribe la identidad en
`~/.claude-work/.claude.json`, pero el perfil actual la tiene en `~/.claude.json`, *fuera*
del directorio. Hay que comprobar cuál layout usa antes de codificar `identity.sh`. Si el
resultado sorprende, el diseño cambia solo en esa unidad.

Independiente del resultado, `identity.sh` soporta ambos layouts: busca primero
`<config-dir>/.claude.json` y, si no existe, `<config-dir>.json` (es decir, para
`~/.claude` probaría `~/.claude/.claude.json` y luego `~/.claude.json`).

| Unidad | Casos |
|---|---|
| `config.sh` | Comentarios, expansión de `~`, líneas inválidas, orden de precedencia, globs |
| `resolve.sh` | Prefijo exacto, subdirectorio profundo, primera ruta gana, excepción anidada, raíz de repo git, worktree, sin match → default |
| `identity.sh` | Email presente, archivo ausente, JSON corrupto, sin `oauthAccount`, ambos layouts |
| `ghostty.sh` | Bytes exactos de OSC 2/11/111, saneo de título con bytes de control, validación de color |
| Shim | Matriz completa de decisiones, verificando código de salida *y* que el binario real no se ejecutó |

Los tests del shim ponen un `claude` falso en el PATH que escribe un archivo si se ejecuta,
para poder afirmar *"esto no arrancó"* — la propiedad que de verdad importa.

## Estructura del repositorio

```
~/repos/claude-ghostty-router/
├── bin/claude-account          # CLI: estado, routes, which, check, login, mark
├── lib/config.sh               # parseo de routes.conf
├── lib/resolve.sh              # cwd → perfil
├── lib/identity.sh             # perfil → email logueado
├── lib/ghostty.sh              # OSC: título, fondo, reset
├── shell/router.zsh            # función claude() + hooks chpwd/zshexit
├── install.sh                  # idempotente, con --uninstall
├── tests/*.bats
├── routes.conf.example
└── docs/
```

## Instalación

`install.sh` es idempotente y pregunta antes de cada cambio fuera del repo:

1. Enlaza `bin/claude-account` a `~/.local/bin`.
2. Crea `~/.config/claude-ghostty-router/routes.conf` desde el ejemplo; nunca lo sobrescribe.
3. Agrega **una línea** a `~/.zshrc` que hace `source` de `shell/router.zsh`.
4. Cambia `shell-integration-features` a `no-title` en la config de Ghostty, con backup previo.
5. Ejecuta `claude-account check` y muestra el resultado.

`install.sh --uninstall` revierte los cuatro pasos.

## Limitaciones conocidas

- **Una función de shell no es un candado.** `command claude` la esquiva siempre; es una
  propiedad de zsh, no un descuido. Esto protege del error distraído, no de un intento
  deliberado de saltarse la verificación.
- **Solo zsh y solo Ghostty.** Otras shells y otros terminales no tienen integración.
- **Routing por ruta.** Renombrar una carpeta rompe su ruta hasta que se actualice
  `routes.conf`. El fallback por raíz de repo git cubre worktrees, no renombres.
- **La verificación depende del formato de `.claude.json`.** Si Claude Code cambia dónde o
  cómo guarda `oauthAccount`, la verificación falla cerrada (bloquea) hasta actualizar
  `identity.sh`. `claude-account check` es la manera de detectarlo temprano.
- **El fondo teñido depende del tema.** Cambiar el tema de Ghostty puede exigir recalibrar
  el hex del perfil.

## Fuera de alcance

- Enrutar Claude fuera de Ghostty (VS Code, scripts, cron).
- Aislar memoria/transcripciones por perfil (el `isolate` de upstream).
- Lanzadores de ventana por perfil y configs de Ghostty por cuenta.
- Más de dos perfiles: el diseño los soporta, pero solo se configuran dos.

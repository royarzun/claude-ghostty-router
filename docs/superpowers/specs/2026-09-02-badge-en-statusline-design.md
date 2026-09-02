# El badge de cuenta dentro de Claude Code — Diseño

**Fecha:** 2026-09-02
**Estado:** implementado
**Reemplaza:** [2026-09-02-color-solo-en-claude-design.md](2026-09-02-color-solo-en-claude-design.md)
**Modifica:** [2026-09-01-claude-ghostty-router-design.md](2026-09-01-claude-ghostty-router-design.md)

## Problema

El diseño original marca la superficie en cada `precmd`: título `perfil · carpeta` y color de
fondo, permanentes. La spec del color reducía eso a teñir el fondo solo mientras Claude corre,
y dejaba el título fuera porque Claude Code escribe el suyo mientras corre.

Las dos versiones comparten un límite: la señal de cuenta vive **fuera** de Claude Code, en
una superficie que Claude Code no controla y que además le pisamos. Un tinte dice "esta no es
tu carpeta de siempre"; no dice con qué cuenta corre la sesión. Y sostener el título costaba
poner `no-title` en Ghostty, es decir, renunciar a ver el comando en curso en todos los tabs
de la máquina, todo el tiempo.

La spec del color cerraba declarando fuera de alcance "marcar la superficie por cualquier otra
vía (cursor, borde, badge)". Esta spec abre esa vía porque resultó existir de verdad.

## Lo que hay

Claude Code tiene `statusLine`: una clave de `settings.json` que apunta a un comando propio,
cuyo stdout se renderiza en una fila fija de su UI, visible durante toda la sesión
([docs](https://code.claude.com/docs/en/statusline.md)). El comando recibe por stdin un JSON
de estado (`workspace.project_dir`, `model.display_name`, `session_id`, coste, contexto…),
soporta ANSI y emoji, y se refresca con cada mensaje del asistente, con un *debounce* de
300 ms.

Dos hechos más, comprobados antes de escribir nada:

- **`CLAUDE_CONFIG_DIR` mueve el `settings.json` de nivel usuario a la carpeta del perfil**
  ([docs](https://code.claude.com/docs/en/settings.md)). O sea: cada perfil ya tiene su propio
  `settings.json`, y por tanto puede tener su propio badge, sin que se pisen.
- **El comando del statusLine hereda el entorno del proceso `claude`.** Se verificó al revés,
  que es lo barato: `CAR_ROUTER_LOADED` y `DISABLE_AUTO_TITLE`, que `router.zsh` exporta antes
  de lanzar Claude, se ven en un subproceso que arranca Claude Code.

## Objetivo

Que la cuenta se vea **dentro de la sesión**, dicha con todas sus letras, y que la terminal
vuelva a ser una terminal: sin título pisado, sin fondo teñido, sin `no-title`.

El badge reemplaza al color. La spec del tinte no llega a implementarse.

## Comportamiento

```
work · d.f.d.chile@gmail.com · traza-backend
```

- **perfil**, pintado con su color de `routes.conf`.
- **email** logueado en ese perfil.
- **carpeta**, el `basename` de `workspace.project_dir`.

El perfil y el email **no se deducen de la ruta**: salen del `CLAUDE_CONFIG_DIR` real con el
que corre la sesión, o de `~/.claude` si la variable no está, que es lo que `_launch-check`
deja pasar sin exportar nada. El badge dice lo que **es**, no lo que debería ser: si alguien
esquiva la función del shell con `command claude`, el badge muestra la cuenta con la que
realmente arrancó, en vez de repetir la versión oficial de los hechos.

| Situación | Qué muestra |
|---|---|
| `routes.conf` inválido o ausente | `⚠ routes.conf invalido` |
| El config-dir no lo declara ningún perfil | `? · email · carpeta` |
| Perfil sin sesión, o identidad corrupta | `perfil · (sin sesion) · carpeta` |
| Perfil con color `-` | el mismo texto, sin color |
| Sin `python3` | `perfil · (sin python3)` |

El badge **nunca falla y nunca bloquea**: sale con 0 por todos los caminos. Quien detiene el
arranque sigue siendo `_launch-check`, y sigue siendo el único que puede.

## Decisiones

**El color se muda al badge.** El campo `color` de `routes.conf` conserva formato y nombre,
pero pinta el nombre del perfil (`\033[1;38;2;R;G;Bm`) en vez del fondo de la superficie. El
criterio de qué color elegir cambia: antes convenía un tinte casi imperceptible; ahora hace
falta un tono legible sobre el fondo del tema.

**Un solo fork de `python3` por refresco.** `lib/statusline.py` saca la carpeta del JSON de
stdin y el email del perfil en una sola invocación. El badge no resuelve rutas: no llama a
`resolve_route` ni a `git`. `refreshInterval` no se configura, porque el contenido no cambia
durante la sesión.

**El stdin se lee entero antes de decidir nada.** Un camino que salga sin leerlo le devuelve
un EPIPE a quien lo está escribiendo.

**El separador entre los dos campos que devuelve `statusline.py` es US (`\037`), no un
tabulador.** El tabulador es espacio en blanco para el IFS de bash: con la carpeta vacía
delante, `read` se la salta y desplaza el email a su sitio. El bug existió y lo cazó un test.

**El `settings.json` lleva la ruta absoluta del CLI**, porque Claude Code puede arrancar con
un `PATH` que no incluya `~/.local/bin`. Se considera nuestro cualquier `command` que termine
en `claude-account statusline`, para que mover el repo se lea como una actualización y no como
un statusLine ajeno.

**Nunca se pisa un `statusLine` ajeno**, igual que el instalador no pisa un `claude-account`
ajeno en `~/.local/bin`. Se avisa y se deja como está.

## Lo que se elimina

**`shell/router.zsh`** queda en el guard de Ghostty, `CAR_ROUTER_LOADED` y `claude()`. Se van
`zmodload zstat`, `_car_cache`, `_car_conf`, `_car_conf_mtime`, `_car_check_conf`,
`_car_paint`, `_car_cleanup`, los hooks `precmd` y `zshexit`, el repintado al salir de Claude
y `DISABLE_AUTO_TITLE` —que existía solo para que `termsupport` de oh-my-zsh no pisara un
título que ya no escribimos.

**`bin/claude-account`**: se van `_surface` y el subcomando `mark`. Entran `statusline`
(público: es lo que se instala en el `settings.json`) y `_config-dirs` (interno: le dice al
instalador en qué archivos escribir). `check` deja de exigir `no-title` y pasa a verificar el
badge perfil por perfil.

**`lib/ghostty.sh`** se convierte en **`lib/badge.sh`**: al no emitir ninguna OSC, deja de ser
la capa Ghostty y pasa a ser el único emisor de ANSI. Sobrevive el saneado —el nombre de la
carpeta y el email siguen sin ser texto de confianza, y Claude Code renderiza el badge
respetando ANSI— y `ghostty_bg` se convierte en `badge_color`. `ghostty_title` desaparece.

**`install.sh`** deja de añadir `no-title`. Como ya lo escribió en las máquinas donde el
proyecto está instalado, y mientras siga ahí Ghostty no muestra el comando en curso, detecta
su propia marca y **ofrece revertirla**, con backup, igual que hizo al ponerla.

## Lo que entra

- **`lib/statusline.py`** — carpeta del JSON de stdin + email del perfil, en un solo fork.
  Importa `read_email` de `lib/identity.py`, que se refactoriza para exponerla: el formato de
  `.claude.json` es la dependencia más frágil del proyecto y no puede quedar leída en dos
  sitios.
- **`lib/settings.py`** — mete y saca la clave `statusLine` del `settings.json` de un perfil
  sin tocar el resto: respaldo previo, escritura por archivo temporal y **el modo del archivo
  se conserva** (`~/.claude/settings.json` es `600`).
- Un paso nuevo en `install.sh`, confirmado como los demás, que recorre los perfiles de
  `routes.conf` y les instala el badge. `--uninstall` lo retira.

## Aviso de `routes.conf` roto

Vuelve, y a un sitio mejor que el título del tab: el propio badge dice
`⚠ routes.conf invalido`. Sigue siendo cierto que el pintado informa y no decide —
`_launch-check` ya bloquea con `CAR_ECONFIG` y explica el error por `stderr` con archivo y
línea.

## Consecuencia que queda anotada

Sin OSC, lo único específico de Ghostty que queda en el proyecto es el guard
`TERM == xterm-ghostty` de `router.zsh`. El badge, en cambio, se ve en cualquier terminal
donde corra Claude Code. El nombre del proyecto empieza a quedarle grande, y ampliar el guard
—o no— es una decisión aparte que esta spec no toma.

## Fuera de alcance

- Añadir modelo, coste, contexto o rama al badge. El JSON los trae; esto es un router de
  cuentas, no un statusline de uso general.
- Recuperar el título del tab con `CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1`. Es viable y es la
  única superficie que se ve en tabs **inactivos**; queda para una decisión aparte.
- Cambiar el formato de `routes.conf` o el guard de Ghostty.

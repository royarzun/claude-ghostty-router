# El tinte de fondo, sobre el diseño del badge — Diseño

**Fecha:** 2026-09-02
**Estado:** aprobado; ejecución bloqueada hasta que el trabajo del badge esté commiteado
**Sustituye a:** [2026-09-02-color-solo-en-claude-design.md](2026-09-02-color-solo-en-claude-design.md)

## Qué cambió desde el spec anterior

El spec anterior partía de un proyecto que marcaba el tab con título y color de fondo en cada
`precmd`, y proponía dejar solo el color, y solo mientras Claude corre.

Mientras tanto, el proyecto se reescribió hacia otro diseño: la cuenta se ve en un **badge**
que Claude Code renderiza desde el `statusLine` de cada perfil. `lib/ghostty.sh` se borró,
`lib/badge.sh` ocupó su lugar emitiendo SGR en vez de OSC, y `shell/router.zsh` dejó de pintar
del todo. Buena parte de lo que el spec anterior pedía —quitar el pintado en `precmd`,
`DISABLE_AUTO_TITLE`, el paso de `no-title` del instalador— ya está hecho por ese camino.

Lo que **no** cubre el badge: el badge vive dentro de la sesión de Claude. Un tab de Ghostty
en el que Claude está corriendo no se distingue de uno en el prompt hasta que miras el
contenido. El tinte de fondo sí se ve de reojo, y es lo que queda por construir.

## Objetivo

El fondo del tab se tiñe con el color de fondo del perfil **al arrancar Claude** y vuelve al
color del tema **al salir**. El badge no se toca: sigue siendo la señal de *qué cuenta*
dentro de la sesión, y el tinte es la señal de *hay sesión* desde fuera.

## El campo de color: dos medios, dos valores

El badge usa el campo `color` de `routes.conf` como color de **texto**, y por eso el ejemplo
del repo lo movió a un verde brillante (`#8fbc5a`). Un fondo de terminal necesita lo
contrario: un tinte apenas perceptible (`#171b12`). Un solo campo no puede servir a los dos
—un verde brillante de fondo ciega, y un casi-negro de texto es ilegible—, así que el fondo
gana un campo propio, opcional y al final:

```conf
#       <nombre>  <config-dir>    <email-glob>   <badge>  <fondo>
profile personal  ~/.claude       yo@gmail.com   -        -
profile work      ~/.claude-work  *@empresa.com  #8fbc5a  #171b12
```

El quinto campo es opcional y su ausencia equivale a `-`: las líneas existentes siguen
valiendo tal cual, y el tinte es opt-in. `-` en cualquiera de los dos significa lo mismo que
ya significa: ese medio no se colorea.

## Comportamiento

| Momento | Badge en la sesión | Fondo del tab |
|---|---|---|
| En el prompt | — | el del tema |
| `claude` autorizado y corriendo | el del perfil | el fondo del perfil |
| Al salir de Claude | — | el del tema |
| `claude` bloqueado | — | el del tema |

Un perfil sin fondo declarado no tiñe nada, y por tanto tampoco despinta nada al salir.

## Piezas

**`lib/config.sh`** parsea el quinto campo a un array nuevo, `CAR_P_TINT`, validado contra
`#rrggbb` o `-` como ya se valida `color`. El registro que emite `resolve_route` gana un
campo al final; ese registro se lee posicionalmente en `cmd_launch_check`, `cmd_which` y
`cmd_status`, así que los tres hay que tocarlos aunque no usen el campo nuevo. Al final y no
en medio, precisamente para que el cambio sea aditivo.

**`lib/ghostty.sh`** vuelve, con una sola función, `ghostty_bg`, que valida `#rrggbb` y emite
OSC 11, o emite OSC 111 para `-`. Vuelve como archivo propio y no dentro de `lib/badge.sh`
porque son dos medios distintos: `badge.sh` colorea texto que Claude Code renderiza,
`ghostty.sh` habla con el emulador de terminal. El comentario de cabecera de `badge.sh`, que
hoy se declara «único emisor de secuencias de escape del proyecto», pasa a decir que es el
único emisor de SGR.

**`bin/claude-account`** gana `_tint <dir>` y `_untint`, los dos comandos internos que ya
diseñó el spec anterior y que no cambian: `_tint` resuelve el perfil de un directorio y emite
su fondo, o nada; `_untint` emite el reset y no lee configuración, porque corre en caminos
donde `routes.conf` puede haber desaparecido. Ninguno de los dos falla nunca: el pintado
informa, no decide.

**`shell/router.zsh`** tiñe alrededor de la sesión dentro de su `claude()`, que ya tiene la
forma correcta:

```zsh
typeset -g _car_tinted=

_car_cleanup() {
  [[ -n $_car_tinted ]] || return 0
  claude-account _untint 2>/dev/null
}

claude() {
  local config_dir tint rc=0
  config_dir=$(claude-account _launch-check "$PWD") || return $?
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
    if [[ -n $_car_tinted ]]; then
      claude-account _untint
      _car_tinted=
    fi
  }

  return $rc
}

add-zsh-hook zshexit _car_cleanup
```

Tres decisiones dentro de esas líneas, todas heredadas del spec anterior y ninguna
invalidada por el badge:

**Se tiñe después de `_launch-check`.** Un arranque bloqueado no deja rastro en el tab.

**El despintado va en un bloque `always`.** Si Claude muere por `SIGINT`, zsh aborta el resto
de la función y un despintado escrito como línea siguiente nunca correría. Por lo mismo `rc`
arranca en `0`: en ese camino nunca llega a asignarse.

**El hook `zshexit` lleva guardia.** Sin `_car_tinted`, toda shell de Ghostty escupiría un
reset al salir aunque nunca hubiera corrido Claude. El guardia deja el hook para lo único que
el `always` no cubre: suspender la sesión con Ctrl-Z y cerrar el tab sin volver a ella.

## Documentación

`routes.conf.example` y el README documentan el quinto campo, con la distinción explícita:
el badge se elige para leerse, el fondo para no leerse. Es el error fácil de cometer, y
cuesta una frase evitarlo.

## Fuera de alcance

- Cualquier cambio al badge, al `statusLine` o a `lib/badge.sh` más allá de su comentario de
  cabecera.
- Cualquier cambio en la verificación de identidad o en el bloqueo *fail-closed*.
- Volver a marcar el título del tab. Sigue siendo de Ghostty en el prompt y de Claude Code
  durante la sesión.

## Secuencia

Este diseño se aplica **sobre** el trabajo del badge, que al escribir esto está sin commitear
en el checkout principal y todavía en movimiento. El plan de implementación paso a paso no se
escribe hasta que esa base esté en un commit: necesita contenidos y líneas exactas de
archivos que aún cambian, y escribirlo antes sería inventar sobre arena.

# El color solo mientras Claude corre — Diseño

**Fecha:** 2026-09-02
**Estado:** aprobado, pendiente de plan de implementación
**Modifica:** [2026-09-01-claude-ghostty-router-design.md](2026-09-01-claude-ghostty-router-design.md)

## Problema

El diseño original marca la superficie en cada `precmd`: el tab lleva permanentemente el
título `perfil · carpeta` y el color de fondo del perfil. La idea era que un tab en reposo
dijera a qué cuenta pertenece.

En uso real ese marcado permanente molesta más de lo que informa. El color del perfil pisa
el tema de la terminal todo el tiempo, incluso cuando no hay ninguna sesión de Claude
corriendo, que es cuando la distinción de cuenta importa. Y el título permanente tiene un
coste documentado: para sostenerlo hay que poner `no-title` en la config de Ghostty, lo que
deja al usuario sin el título que Ghostty escribe con el comando en curso.

## Objetivo

El fondo de la terminal se tiñe con el color del perfil **al arrancar Claude** y vuelve al
color del tema **al salir**. Fuera de la sesión, el tab es un tab normal de Ghostty.

El router deja de gestionar el título. No lo escribe nunca.

## Comportamiento

| Momento | Título | Fondo |
|---|---|---|
| En el prompt | el de Ghostty | el del tema |
| `claude` autorizado y corriendo | el de Claude Code | el color del perfil |
| Al salir de Claude | el de Ghostty | el del tema |
| `claude` bloqueado (cuenta equivocada, sin sesión, config rota) | el de Ghostty | el del tema |

El título durante la sesión no es nuestro y no se intenta que lo sea: Claude Code escribe el
suyo mientras corre, así que pintarlo antes de lanzar solo produciría un parpadeo de un par
de segundos. La señal duradera de cuenta pasa a ser el color, y solo dura lo que dura la
sesión.

Un perfil con color `-` no tiñe nada, y por tanto tampoco despinta nada al salir.

## Dónde vive el cambio

El color pasa a la función `claude()` de `shell/router.zsh`, el único punto del sistema que
sabe cuándo empieza y termina una sesión.

```zsh
claude() {
  local config_dir tint rc
  config_dir=$(claude-account _launch-check "$PWD") || return $?
  tint=$(claude-account _tint "$PWD")

  {
    [[ -n $tint ]] && print -rn -- $tint
    if [[ -n $config_dir ]]; then
      CLAUDE_CONFIG_DIR=$config_dir command claude "$@"
    else
      command claude "$@"
    fi
    rc=$?
  } always {
    [[ -n $tint ]] && claude-account _untint
  }
  return $rc
}
```

Dos decisiones dentro de esas líneas:

**Se pinta después de `_launch-check`.** Una cuenta equivocada no llega a teñir nada. El
orden mantiene la regla del proyecto: quien decide es el shim, y el pintado solo informa de
una decisión ya tomada.

**El despintado va en un bloque `always`.** Si Claude muere por `SIGINT`, zsh aborta el
resto de la función y un despintado escrito como línea siguiente nunca correría: el color se
quedaría pegado al tab. `always` corre igual. El hook `zshexit` se conserva como red de
seguridad para el caso en que se cierre el tab con una sesión suspendida con Ctrl-Z.

## Lo que se elimina

Sin pintado en cada `precmd`, toda la maquinaria que existía para hacerlo barato deja de
tener razón de ser.

**`shell/router.zsh`:** se van `zmodload zstat`, `_car_cache`, `_car_conf`,
`_car_conf_mtime`, `_car_check_conf`, `_car_paint`, el hook `precmd` y la llamada de pintado
inicial. Se va también `DISABLE_AUTO_TITLE`, que existía solo para que `termsupport` de
oh-my-zsh no pisara nuestro título. Quedan `CAR_ROUTER_LOADED`, la función `claude()` y el
hook `zshexit`.

**`bin/claude-account`:** `_surface` se convierte en `_tint`, que emite solo el color del
perfil resuelto y nada más. Se añade `_untint`, que emite el reset al tema. Desaparece el
subcomando `mark`: repintaba la superficie en el prompt, que es exactamente lo que este
diseño quita. `check` deja de exigir `no-title` en la config de Ghostty.

**`lib/ghostty.sh`:** quedan `ghostty_bg` y nada más. `ghostty_title`, `ghostty_sanitize` y
`CAR_TITLE_MAX` se borran con sus tests. Al no emitir nunca un título, la vía de inyección
por nombre de carpeta deja de existir en vez de quedar mitigada; la sección de Seguridad del
README pasa a decir eso.

**`install.sh`:** deja de añadir `no-title` a la config de Ghostty. Como el instalador ya
metió esa línea en máquinas donde el proyecto está instalado, y mientras siga ahí Ghostty no
escribe el título del comando en curso, `install.sh` detecta su propia marca y **ofrece
revertirla**, con backup, igual que hacía al ponerla. `--uninstall` sigue limpiándola.

## Aviso de `routes.conf` roto

Hoy un `routes.conf` inválido se ve en el título del tab (`⚠ routes.conf invalido`). Ese
canal desaparece, y no hace falta reemplazarlo: `_launch-check` ya bloquea el arranque con
código `CAR_ECONFIG` y `car_load_config` ya explica el error por `stderr` con archivo y
línea. El usuario ve más, no menos.

Por eso `_tint` con una config rota no emite nada y sale con éxito: sigue siendo cierto que
el pintado informa y no decide.

## Tests

`tests/surface.bats` se reescribe como `tests/tint.bats`: color del perfil resuelto, nada
para un perfil con color `-`, nada sin `routes.conf`, nada con `routes.conf` roto y salida 0,
y funciona invocado a través de un symlink.

`tests/router_paint.bats` pierde casi todo su contenido —cache, invalidación por mtime,
`DISABLE_AUTO_TITLE`, pintado en `precmd`— y conserva solo que el router se activa dentro de
Ghostty y no fuera.

`tests/router_claude.bats` gana los casos nuevos, que son el corazón del cambio: tiñe antes
de lanzar y despinta al salir; **no** tiñe cuando `_launch-check` bloquea; no emite nada
cuando el perfil tiene color `-`; y despinta aunque Claude termine con código distinto de
cero.

`tests/ghostty.bats` pierde los tests de título. `tests/install.bats` y `tests/check.bats` se
ajustan a un instalador que ya no añade `no-title` y a un `check` que ya no lo exige.

## Documentación

El README abre diciendo que cada tab muestra su cuenta "en su título y en su color de
fondo", y esa frase deja de ser cierta. Hay que revisar la introducción, la sección de
instalación (desaparece el paso 4 y su explicación), la tabla de arquitectura, la sección de
Seguridad, la lista de uso diario (sin `mark`) y la limitación "el título deja de mostrar el
comando en curso", que ahora se resuelve en vez de asumirse.

## Fuera de alcance

- Cambiar el formato de `routes.conf`. El campo `color` sigue siendo el mismo.
- Cualquier cambio en la verificación de identidad o en el bloqueo *fail-closed*.
- Marcar la superficie por cualquier otra vía (cursor, borde, badge).

# claude-ghostty-router

Enruta cada carpeta a la cuenta de Claude Code que le corresponde, dentro de [Ghostty](https://ghostty.org).

- Dentro de cada sesión, un **badge** dice con qué cuenta está corriendo Claude.
- Si la cuenta logueada no es la esperada para esa carpeta, **Claude no arranca**.
- Fuera de Ghostty todo se comporta exactamente como antes.

Inspirado en [kirlts/claude-account-router](https://github.com/kirlts/claude-account-router),
que resuelve el mismo problema para VS Code enganchándose a `claudeCode.claudeProcessWrapper`.
Ghostty no tiene API de plugins, así que aquí el mismo objetivo se construye con dos piezas
que sí existen: la integración de shell de zsh, y el `statusLine` que Claude Code deja
configurar para pintar una línea propia dentro de su interfaz.

## El problema

Claude Code toma la cuenta de un único directorio de configuración. Con dos cuentas hay que
cerrar y abrir sesión a mano para cambiar, y nada indica con qué cuenta está corriendo una
sesión. Si trabajas con varios proyectos en tabs distintos de la misma ventana, lanzar Claude
en el proyecto equivocado con la cuenta equivocada es silencioso: nada en la pantalla lo
desmiente.

## Requisitos

- macOS y Ghostty (probado en 1.3.1)
- zsh
- `python3` — solo para leer JSON
- `git`
- `~/.local/bin` en el `PATH`

Todo el código shell es compatible con **bash 3.2**, el `/bin/bash` que trae macOS.

## Instalación

```sh
git clone https://github.com/royarzun/claude-ghostty-router.git
cd claude-ghostty-router
./install.sh
```

El instalador es idempotente y pregunta antes de cada cambio fuera del repo:

1. Enlaza `bin/claude-account` en `~/.local/bin`.
2. Crea `~/.config/claude-ghostty-router/routes.conf` desde el ejemplo. **Nunca lo sobrescribe.**
3. Añade una línea a `~/.zshrc` que hace `source` de `shell/router.zsh`.
4. Añade el badge al `settings.json` de cada perfil, con backup previo.
5. Ejecuta `claude-account check` y te muestra el resultado.

El paso 4 escribe una sola clave, `statusLine`, y deja el resto del archivo intacto. Cada
perfil tiene su propio `settings.json` porque `CLAUDE_CONFIG_DIR` es justamente lo que mueve
la configuración de nivel usuario a la carpeta del perfil. Si ya tienes un `statusLine`
propio, **no se toca**: el instalador avisa y sigue. Si añades un perfil más adelante, vuelve
a correr `./install.sh` para darle su badge.

Versiones anteriores ponían `no-title` en la config de Ghostty para sostener un título de tab
que este proyecto ya no escribe. Si la encuentra, el instalador **ofrece quitarla**, con
backup: sin ella Ghostty vuelve a mostrar el comando en curso en el título.

Para revertirlo todo:

```sh
./install.sh --uninstall
```

`routes.conf` se conserva: es tuyo. El `statusLine` se quita de cada perfil, y el resto de
cada `settings.json` queda como estaba.

## Configuración

Un solo archivo, `~/.config/claude-ghostty-router/routes.conf`:

```conf
#       <nombre>  <config-dir>    <email-glob>        <color>
profile personal  ~/.claude       yo@gmail.com        -
profile work      ~/.claude-work  *@empresa.com       #e0a458

route ~/repos/proyecto-de-trabajo  work
route ~/repos/cliente-*            work
```

**`profile <nombre> <config-dir> [email-glob] [color]`**

- `config-dir` es el `CLAUDE_CONFIG_DIR` de esa cuenta. Cada perfil tiene su propio login.
- `email-glob` es el patrón que **debe** cumplir la cuenta logueada ahí. `-` desactiva la
  verificación de ese perfil, lo que anula la única garantía que da esta herramienta: úsalo
  solo si sabes por qué.
- `color` es el `#rrggbb` con el que se pinta el **fondo** de la línea del badge. `-` la deja
  sin fondo. El color del texto no se declara: sale de la luminancia del fondo —negro sobre
  los tonos claros, blanco sobre los oscuros—, así que cualquier color se lee.
  `claude-account check` imprime la muestra con ese mismo fondo, así que un tono que no
  convenza se ve ahí en vez de descubrirse dentro de una sesión.

**`route <ruta> <perfil>`**

- **Gana la primera ruta declarada**, así que las excepciones se declaran antes que el padre.
- Se permiten globs (`~/repos/cliente-*`).
- Un subdirectorio hereda la ruta de su padre.

**El primer perfil declarado es el perfil por defecto**: toda carpeta sin ruta cae ahí.

Los comentarios son de línea completa. Un `#` a media línea es parte de un campo, porque los
colores son `#rrggbb`.

## Cómo decide

Al resolver una carpeta se prueban estos candidatos, en orden, y gana el primero que case
alguna ruta:

1. El directorio tal cual.
2. Su forma física, con los symlinks resueltos.
3. La raíz de su repositorio git.
4. El repositorio principal, que solo difiere en un worktree.

Por eso un worktree en otro disco sigue a su repositorio, y un repo alcanzado por symlink se
resuelve igual. Si nada casa, se usa el perfil por defecto.

## Uso diario

```sh
claude-account                # perfiles, email logueado en cada uno, y perfil del cwd
claude-account routes         # mapa carpeta -> perfil
claude-account which [dir]    # el perfil de un directorio, en una línea
claude-account check          # diagnóstico completo
claude-account login <perfil> # abre sesión en un perfil
claude-account statusline     # la línea del badge (la invoca Claude Code)
```

### Añadir la segunda cuenta

```sh
claude-account login work     # dentro de Claude: /login, luego /exit
claude-account check
```

`check` te dirá el email que encontró. Cópialo al `email-glob` de ese perfil en `routes.conf`,
declara las rutas de tus proyectos, y listo.

### Cuando bloquea

```
claude-account: cuenta equivocada para trazaambiental-backend (perfil 'work').
  esperaba: *@empresa.com
  logueada: yo@gmail.com
  Arreglalo con: claude-account login work
```

El principio es uno solo: **si no se puede verificar, no arranca**. También bloquea si el
perfil no tiene sesión, si su directorio no existe, si `routes.conf` tiene un error de
sintaxis, o si falta `python3`. La ambigüedad se resuelve bloqueando, nunca adivinando.

Un `routes.conf` roto además se *ve*: el badge pasa a `⚠ routes.conf invalido`.
Pero quien detiene el arranque es siempre el shim, nunca el badge.

## Arquitectura

| Pieza | Responsabilidad |
|---|---|
| `lib/config.sh` | Parsea `routes.conf` a registros. Nada más. |
| `lib/resolve.sh` | `directorio → perfil`. |
| `lib/identity.{sh,py}` | `perfil → email logueado`. **Nunca lee tokens.** |
| `lib/statusline.py` | Carpeta del JSON de stdin + email del perfil, en un solo fork. |
| `lib/badge.sh` | Único emisor de secuencias de escape del proyecto. |
| `lib/settings.py` | Mete y saca la clave `statusLine` de un `settings.json` ajeno. |
| `bin/claude-account` | El CLI, y la verificación *fail-closed*. |
| `shell/router.zsh` | La función `claude()`. |

El núcleo es puro: entran datos, salen datos, sin efectos secundarios. Solo `lib/badge.sh`
emite escapes, y solo el shim decide bloquear.

`shell/router.zsh` se auto-desactiva si `TERM != xterm-ghostty`, así que no afecta a scripts,
cron ni a la terminal integrada de un editor. No pinta nada ni engancha ningún hook de prompt:
sustituye a `claude` y nada más.

**El shell nunca exporta `CLAUDE_CONFIG_DIR` por su cuenta.** La variable se define únicamente
en el proceso de Claude ya verificado, para que ningún script que esquive la función acabe
corriendo con un perfil que nadie comprobó.

### El badge

`statusLine` es una clave del `settings.json` de Claude Code que apunta a un comando propio:
su stdout se renderiza en una fila fija de la interfaz, visible durante toda la sesión, y se
refresca con cada mensaje. Aquí ese comando es `claude-account statusline`.

```
work · tu-cuenta@empresa.com · traza-backend
```

Esa línea entera va sobre el fondo del color del perfil, con el nombre del perfil en negrita.
El fondo llega hasta donde llega el texto y ni un carácter más: la fila no se rellena hasta el
ancho de la terminal, porque esa superficie no es nuestra.

El perfil y el email **no se deducen de la carpeta**: salen del `CLAUDE_CONFIG_DIR` con el que
la sesión está corriendo de verdad, que el comando hereda por ser hijo del proceso `claude`.
Por eso el badge dice lo que *es* y no lo que debería ser: si esquivas la función con
`command claude`, lo verás decir `personal` en una carpeta de trabajo. Cuesta un solo proceso
de `python3` por refresco, y no llama a `git` ni resuelve rutas.

### Seguridad

El badge se arma con un nombre de carpeta y con un email leído de un archivo, y ninguno de los
dos es texto de confianza: una carpeta puede llamarse con bytes de control adentro. Claude Code
renderiza el badge respetando ANSI, así que un nombre hostil podría colar sus propias
secuencias. `lib/badge.sh` los filtra antes de emitirlos, `bin/claude-account` los recorta a
60 caracteres campo a campo, y `lib/statusline.py` los filtra otra vez en el punto por el que
entran. Ni siquiera el propio badge arma escapes por fuera: la negrita del nombre del perfil
la emite `lib/badge.sh`, porque el filtro no puede distinguir un escape nuestro de uno colado
por un nombre de carpeta. El color se valida contra `#rrggbb` antes de entrar en la secuencia,
y el color del texto no viene de fuera: se calcula.

Al no escribir nunca el título del tab, la vía de inyección que
[ya dio CVEs en Ghostty](https://dgl.cx/2024/12/ghostty-terminal-title) deja de existir en vez
de quedar mitigada.

El `settings.json` de cada perfil es un archivo tuyo: el instalador lo respalda antes de
tocarlo, cambia una sola clave, conserva el modo del archivo (`600` en `~/.claude`) y nunca
pisa un `statusLine` que no haya puesto él.

## Limitaciones conocidas

- **Una función de shell no es un candado.** `command claude` la esquiva siempre; es una
  propiedad de zsh, no un descuido. Esto protege del error distraído, no de un intento
  deliberado de saltársela.
- **Solo zsh y solo Ghostty.**
- **Las rutas no pueden contener espacios**: los campos se separan por espacios. Si ocurre, el
  síntoma es un config-dir inexistente y Claude no arranca mostrando la ruta truncada.
- **Renombrar una carpeta rompe su ruta** hasta que actualices `routes.conf`. El fallback por
  raíz de repo cubre worktrees, no renombres.
- **La verificación depende del formato de `.claude.json`.** Si Claude Code cambia dónde guarda
  `oauthAccount`, la verificación falla cerrada hasta actualizar `identity.sh`.
  `claude-account check` es la forma de detectarlo temprano.
- **El badge depende de `statusLine`.** Si Claude Code cambia esa clave o el JSON que entrega
  por stdin, el badge se degrada o desaparece; el bloqueo por cuenta equivocada no se entera y
  sigue funcionando.
- **El badge solo se ve en el split enfocado.** Un tab en reposo no dice a qué cuenta
  pertenece: para eso haría falta el título, y sostenerlo cuesta el título de Ghostty.
  Teñir el fondo del tab mientras corre la sesión llegó a implementarse, con su propio campo
  en `routes.conf`, y se descartó después de probarlo (revertido en `120bf6b`). Si vuelves a
  considerarlo, ahí está hecho y con tests.

## Desarrollo

```sh
brew install bats-core shellcheck
bats tests/                                          # 128 tests
shellcheck -s bash bin/claude-account install.sh lib/*.sh
```

Los tests corren con un `HOME` desechable: nunca tocan la máquina real.

`bats` arranca con `env bash`, que en un macOS con Homebrew suele ser bash 5.x. Para verificar
de verdad la compatibilidad con el bash 3.2 del sistema:

```sh
mkdir -p /tmp/b32 && ln -sf /bin/bash /tmp/b32/bash
PATH=/tmp/b32:$PATH bats tests/
```

El diseño y el plan de implementación están en `docs/superpowers/`.

## Licencia

MIT

# claude-ghostty-router

Enruta cada carpeta a la cuenta de Claude Code que le corresponde, dentro de [Ghostty](https://ghostty.org).

- Cada tab muestra **en su título y en su color de fondo** a qué cuenta pertenece.
- Si la cuenta logueada no es la esperada para esa carpeta, **Claude no arranca**.
- Fuera de Ghostty todo se comporta exactamente como antes.

Inspirado en [kirlts/claude-account-router](https://github.com/kirlts/claude-account-router),
que resuelve el mismo problema para VS Code enganchándose a `claudeCode.claudeProcessWrapper`.
Ghostty no tiene API de plugins, así que aquí el mismo objetivo se construye con las piezas
que sí ofrece una terminal: variables de sesión, integración de shell y secuencias OSC.

## El problema

Claude Code toma la cuenta de un único directorio de configuración. Con dos cuentas hay que
cerrar y abrir sesión a mano para cambiar, y nada indica con qué cuenta está corriendo una
sesión. Si trabajas con varios proyectos en tabs distintos de la misma ventana, un tab en
reposo no dice a qué cuenta pertenece, y lanzar Claude en el proyecto equivocado con la
cuenta equivocada es silencioso.

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
4. Pone `no-title` en `shell-integration-features` de tu config de Ghostty, con backup previo.
5. Ejecuta `claude-account check` y te muestra el resultado.

Ese paso 4 hace falta porque Ghostty reescribe el título en cada prompt y pisaría el nuestro.
Si usas **oh-my-zsh**, su módulo `termsupport` hace lo mismo: el router pone
`DISABLE_AUTO_TITLE=true` en tiempo de ejecución, y solo dentro de Ghostty.

Para revertirlo todo:

```sh
./install.sh --uninstall
```

`routes.conf` se conserva: es tuyo.

## Configuración

Un solo archivo, `~/.config/claude-ghostty-router/routes.conf`:

```conf
#       <nombre>  <config-dir>    <email-glob>        <fondo>
profile personal  ~/.claude       yo@gmail.com        -
profile work      ~/.claude-work  *@empresa.com       #171b12

route ~/repos/proyecto-de-trabajo  work
route ~/repos/cliente-*            work
```

**`profile <nombre> <config-dir> [email-glob] [color]`**

- `config-dir` es el `CLAUDE_CONFIG_DIR` de esa cuenta. Cada perfil tiene su propio login.
- `email-glob` es el patrón que **debe** cumplir la cuenta logueada ahí. `-` desactiva la
  verificación de ese perfil, lo que anula la única garantía que da esta herramienta: úsalo
  solo si sabes por qué.
- `color` es el fondo `#rrggbb` de la superficie. `-` respeta el tema. Conviene un tinte
  apenas perceptible sobre tu fondo habitual: reconocible de reojo, sin arruinar el tema.

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
claude-account mark           # repinta la superficie actual
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

Un `routes.conf` roto además se *ve*: el título del tab pasa a `⚠ routes.conf invalido`.
Pero quien detiene el arranque es siempre el shim, nunca el pintado.

## Arquitectura

| Pieza | Responsabilidad |
|---|---|
| `lib/config.sh` | Parsea `routes.conf` a registros. Nada más. |
| `lib/resolve.sh` | `directorio → perfil`. |
| `lib/identity.{sh,py}` | `perfil → email logueado`. **Nunca lee tokens.** |
| `lib/ghostty.sh` | Único emisor de secuencias OSC del proyecto. |
| `bin/claude-account` | El CLI, y la verificación *fail-closed*. |
| `shell/router.zsh` | Hooks de sesión y la función `claude()`. |

El núcleo es puro: entran datos, salen datos, sin efectos secundarios. Solo la capa Ghostty
emite escapes, y solo el shim decide bloquear.

`shell/router.zsh` se auto-desactiva si `TERM != xterm-ghostty`, así que no afecta a scripts,
cron ni a la terminal integrada de un editor. Pinta en cada `precmd` con una caché por
directorio invalidada por el `mtime` de `routes.conf`: con la caché caliente son unos 40 bytes
escritos y ningún proceso nuevo.

**El hook nunca exporta `CLAUDE_CONFIG_DIR`.** Solo pinta. La variable se define únicamente en
el proceso de Claude ya verificado, para que ningún script que esquive la función acabe
corriendo con un perfil que nadie comprobó.

### Seguridad

El título se construye con un nombre de carpeta, y una carpeta puede tener bytes de control en
su nombre. `ghostty.sh` los filtra y recorta el título antes de emitirlo:
un título sin sanear es una vía de inyección de secuencias de escape, y
[ya hubo CVEs de esto en Ghostty](https://dgl.cx/2024/12/ghostty-terminal-title).
El color se valida contra `#rrggbb` antes de entrar en una secuencia OSC.

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
- **El título deja de mostrar el comando en curso.** Es el precio de que diga de qué cuenta es
  el tab.

## Desarrollo

```sh
brew install bats-core shellcheck
bats tests/                                          # 106 tests
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

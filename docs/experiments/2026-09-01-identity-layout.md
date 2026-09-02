# Layout del archivo de identidad con CLAUDE_CONFIG_DIR

**Fecha:** 2026-09-01
**Pregunta:** con `CLAUDE_CONFIG_DIR=<dir>`, ¿dónde escribe Claude Code `oauthAccount`?

## Comandos

    probe=$(mktemp -d)
    CLAUDE_CONFIG_DIR="$probe" claude --version
    CLAUDE_CONFIG_DIR="$probe" claude mcp list

(Claude Code 2.1.258, macOS)

## Observado

Paso 1 — `CLAUDE_CONFIG_DIR="$probe" claude --version`:

    2.1.258 (Claude Code)

    --- dentro de $probe ---
    total 0
    drwx------@    2 royarzun  staff     64 Sep  1 23:30 .
    drwx------@ 1419 royarzun  staff  45408 Sep  1 23:30 ..
    --- hermano ---
    (no existe)

`--version` no escribió nada: ni `$probe/.claude.json` ni `$probe.json`. Confirma lo esperado en el Paso 1 (rama "no aparece nada").

Paso 2 — `CLAUDE_CONFIG_DIR="$probe" claude mcp list` (no colgó, no intentó autenticar; terminó de inmediato con salida `No MCP servers configured. Use \`claude mcp add\` to add a server.`):

    --- dentro de $probe ---
    total 8
    drwx------@    4 royarzun  staff    128 Sep  1 23:30 .
    drwx------@ 1419 royarzun  staff  45408 Sep  1 23:30 ..
    -rw-------@    1 royarzun  staff    423 Sep  1 23:30 .claude.json
    drwxr-xr-x@    3 royarzun  staff     96 Sep  1 23:30 backups
    --- hermano ---
    (no existe)

`$probe/.claude.json` apareció dentro del directorio. Su contenido (revisado, no pegado íntegro por llevar `userID`/`machineID` locales) es un JSON con claves como `firstStartTime`, `firstStartVersion`, `machineID`, `userID`, `seenNotifications`, `migrationVersion`, etc. — y, como anticipaba el enunciado del Paso 2, **no** contiene `oauthAccount`, porque este perfil desechable nunca inició sesión. `$probe.json` (el hermano, fuera del directorio) no existe en ningún momento.

## Conclusión

Layout: `<dir>/.claude.json`

## Consecuencia

`identity.sh` prueba `<dir>/.claude.json` y luego `<dir>.json`, en ese orden.
El experimento confirma que, con `CLAUDE_CONFIG_DIR` apuntando a un directorio nuevo, Claude Code
escribe su identidad **dentro** de ese directorio (`<dir>/.claude.json`), no como archivo hermano.
Esto contrasta con el perfil real de esta máquina, donde la identidad vive en `~/.claude.json`
(hermano de `~/.claude/`) — probablemente por ser un perfil migrado de una versión anterior, antes
de que `CLAUDE_CONFIG_DIR` se usara. El fallback a `<dir>.json` en `identity.sh` queda como
salvaguarda para ese caso heredado, no como el comportamiento por defecto observado aquí.

Sigue pendiente confirmar con una sesión con login real que `oauthAccount` efectivamente aparece en
`<dir>/.claude.json` (aquí solo se confirmó la ubicación del archivo, no el campo, porque el perfil
de sondeo no tiene sesión) — eso lo resuelve la Tarea 16.

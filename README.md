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

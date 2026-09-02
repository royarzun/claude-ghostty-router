#!/usr/bin/env python3
"""Extrae, en una sola invocacion, los dos datos del badge que viven en JSON.

Argv 1: ruta del archivo de identidad del perfil, o "" si no lo hay.
Stdin:  el JSON de estado que Claude Code entrega a un comando de statusLine.
Stdout: <carpeta-del-proyecto><US><email>, con el email vacio si el perfil no
        tiene sesion o su archivo esta corrupto. El separador es US (\037) y no
        un tabulador porque el tabulador es espacio en blanco para el IFS de
        bash: con un campo vacio delante, `read` se lo salta y desplaza el
        resto.

Existe para que el badge cueste un solo fork de python3 por refresco: Claude
Code lo reejecuta con cada mensaje del asistente. Nunca lee ni imprime tokens:
la identidad se lee con identity.read_email, que solo mira un campo.

Sale 0 siempre: un badge que falla no debe ensuciar la UI de Claude, y no
decide nada. Los campos que no se puedan averiguar salen vacios.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from identity import BadIdentity, read_email  # noqa: E402

# Un byte de control dentro de un campo partiria el separador. Se filtran aqui,
# en el unico punto por el que pasan, y de paso el badge no puede colar ANSI.
def clean(value) -> str:
    if not isinstance(value, str):
        return ""
    return "".join(char for char in value if char.isprintable())


def project_dir(payload) -> str:
    if not isinstance(payload, dict):
        return ""
    workspace = payload.get("workspace")
    if isinstance(workspace, dict):
        for key in ("project_dir", "current_dir"):
            value = workspace.get(key)
            if isinstance(value, str) and value:
                return value
    return payload.get("cwd") if isinstance(payload.get("cwd"), str) else ""


def main() -> int:
    try:
        payload = json.loads(sys.stdin.read())
    except (OSError, ValueError):
        payload = None

    email = ""
    identity = sys.argv[1] if len(sys.argv) > 1 else ""
    if identity:
        try:
            email = read_email(identity) or ""
        except BadIdentity:
            email = ""

    print("%s\037%s" % (clean(project_dir(payload)), clean(email)))
    return 0


if __name__ == "__main__":
    sys.exit(main())

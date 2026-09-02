#!/usr/bin/env python3
"""Mete (o saca) la clave statusLine del settings.json de un perfil.

Uso:
  settings.py <settings.json> --install <comando>
  settings.py <settings.json> --uninstall
  settings.py <settings.json> --check     (no escribe nada)

El archivo es del usuario y suele tener dentro permisos, modelo y plugins: se
lee, se cambia una sola clave y se vuelve a escribir con el resto intacto.
Nunca se pisa un statusLine ajeno, por la misma razon por la que el instalador
no pisa un claude-account ajeno en ~/.local/bin.

Codigos de salida:
  0 escrito (o, con --check, instalado)   2 nada que hacer / no instalado
  3 hay un statusLine ajeno
  1 error: JSON corrupto, o no se pudo leer o escribir
"""

import json
import os
import shutil
import sys

EXIT_WRITTEN = 0
EXIT_ERROR = 1
EXIT_UNCHANGED = 2
EXIT_FOREIGN = 3

MARCA = "claude-account statusline"
MODO_NUEVO = 0o600


def es_nuestro(status_line) -> bool:
    return (
        isinstance(status_line, dict)
        and isinstance(status_line.get("command"), str)
        and status_line["command"].rstrip().endswith(MARCA)
    )


def leer(path: str):
    """-> el objeto del settings.json, o {} si no existe o esta vacio."""
    try:
        with open(path, "r", encoding="utf-8") as handle:
            texto = handle.read().strip()
    except FileNotFoundError:
        return {}
    except OSError as error:
        raise ValueError("no puedo leer %s: %s" % (path, error))
    if not texto:
        return {}
    data = json.loads(texto)
    if not isinstance(data, dict):
        raise ValueError("%s no contiene un objeto JSON" % path)
    return data


def escribir(path: str, data) -> None:
    """Respalda, escribe por archivo temporal y conserva el modo del original."""
    existe = os.path.exists(path)
    if existe:
        shutil.copy2(path, path + ".bak")
        modo = os.stat(path).st_mode & 0o777
    else:
        modo = MODO_NUEVO
    temporal = path + ".tmp"
    with open(temporal, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    os.chmod(temporal, modo)
    os.replace(temporal, path)


def main() -> int:
    if len(sys.argv) < 3:
        print("uso: settings.py <settings.json> --install <comando> | --uninstall",
              file=sys.stderr)
        return EXIT_ERROR

    path, accion = sys.argv[1], sys.argv[2]
    try:
        data = leer(path)
    except (ValueError, json.JSONDecodeError) as error:
        print("claude-account: %s" % error, file=sys.stderr)
        return EXIT_ERROR

    actual = data.get("statusLine")

    if accion == "--install":
        if len(sys.argv) != 4:
            return EXIT_ERROR
        deseado = {"type": "command", "command": sys.argv[3]}
        if actual == deseado:
            return EXIT_UNCHANGED
        if actual is not None and not es_nuestro(actual):
            return EXIT_FOREIGN
        data["statusLine"] = deseado
    elif accion == "--uninstall":
        if actual is None:
            return EXIT_UNCHANGED
        if not es_nuestro(actual):
            return EXIT_FOREIGN
        del data["statusLine"]
    elif accion == "--check":
        if actual is None:
            return EXIT_UNCHANGED
        return EXIT_WRITTEN if es_nuestro(actual) else EXIT_FOREIGN
    else:
        return EXIT_ERROR

    try:
        escribir(path, data)
    except OSError as error:
        print("claude-account: no puedo escribir %s: %s" % (path, error),
              file=sys.stderr)
        return EXIT_ERROR
    return EXIT_WRITTEN


if __name__ == "__main__":
    sys.exit(main())

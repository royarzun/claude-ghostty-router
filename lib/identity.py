#!/usr/bin/env python3
"""Lee oauthAccount.emailAddress del archivo de identidad de un perfil.

Nunca lee ni imprime tokens: solo ese campo.
Codigos de salida: 0 ok, 3 sin sesion, 4 archivo ilegible o corrupto.

read_email() se expone aparte porque lib/statusline.py la importa: el formato
de .claude.json es la dependencia mas fragil del proyecto (lo dice el README),
y tenerla leida en dos sitios distintos seria tener dos sitios que arreglar.
"""

import json
import sys

EXIT_OK = 0
EXIT_NO_SESSION = 3
EXIT_BAD_JSON = 4


class BadIdentity(Exception):
    """El archivo no existe, no se puede leer, o no es el JSON esperado."""


def read_email(path: str):
    """-> el email logueado, o None si el archivo no declara ninguna sesion."""
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError) as error:
        raise BadIdentity(str(error)) from error
    if not isinstance(data, dict):
        raise BadIdentity("la raiz no es un objeto")
    account = data.get("oauthAccount")
    if not isinstance(account, dict):
        return None
    email = account.get("emailAddress")
    if not isinstance(email, str) or not email:
        return None
    return email


def main() -> int:
    if len(sys.argv) != 2:
        return EXIT_BAD_JSON
    try:
        email = read_email(sys.argv[1])
    except BadIdentity:
        return EXIT_BAD_JSON
    if email is None:
        return EXIT_NO_SESSION
    print(email)
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())

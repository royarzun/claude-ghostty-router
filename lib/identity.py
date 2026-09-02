#!/usr/bin/env python3
"""Imprime oauthAccount.emailAddress del archivo de identidad de un perfil.

Nunca lee ni imprime tokens: solo ese campo.
Codigos de salida: 0 ok, 3 sin sesion, 4 archivo ilegible o corrupto.
"""

import json
import sys

EXIT_OK = 0
EXIT_NO_SESSION = 3
EXIT_BAD_JSON = 4


def main() -> int:
    if len(sys.argv) != 2:
        return EXIT_BAD_JSON
    try:
        with open(sys.argv[1], "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return EXIT_BAD_JSON
    if not isinstance(data, dict):
        return EXIT_BAD_JSON
    account = data.get("oauthAccount")
    if not isinstance(account, dict):
        return EXIT_NO_SESSION
    email = account.get("emailAddress")
    if not isinstance(email, str) or not email:
        return EXIT_NO_SESSION
    print(email)
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())

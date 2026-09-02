#!/usr/bin/env python3
"""Imprime claudeAiOauth.expiresAt (epoch en milisegundos) de un .credentials.json.

Lee exclusivamente ese campo: los tokens no se leen ni se imprimen nunca.
Codigos de salida: 0 ok, 3 sin campo, 4 archivo ilegible o corrupto.
"""

import json
import sys

EXIT_OK = 0
EXIT_MISSING = 3
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
    oauth = data.get("claudeAiOauth")
    if not isinstance(oauth, dict):
        return EXIT_MISSING
    expires = oauth.get("expiresAt")
    if not isinstance(expires, (int, float)):
        return EXIT_MISSING
    print(int(expires))
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())

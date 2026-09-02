# El fondo del badge — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el color del perfil pinte el fondo de toda la línea del badge —hasta donde llega el texto y ni un carácter más— con el color del texto calculado para que se lea encima.

**Architecture:** `lib/badge.sh` cambia su única función de pintado: `badge_color` (frente sobre el nombre del perfil) se convierte en `badge_bar <color> <destacado> [resto]`, que envuelve la línea entera en una sola secuencia SGR con `48;2` y un `38;2` calculado por luminancia. El nombre del perfil, que ya no se distingue por el color, se distingue por la negrita, y esa negrita la emite `badge_bar` —no quien la llama— porque el filtro de bytes de control se comería un escape armado por fuera. Sus dos llamadores, `cmd_statusline` y `car_colores`, pasan a darle los campos por separado.

**Tech Stack:** bash 3.2 (`bin/`, `lib/`), bats-core para tests, shellcheck para lint.

**Spec:** [docs/superpowers/specs/2026-09-02-fondo-del-badge-design.md](../specs/2026-09-02-fondo-del-badge-design.md)

---

## Contexto para quien implemente

Este repo enruta carpetas a cuentas de Claude Code. El badge es la línea que `claude-account
statusline` escribe y que Claude Code renderiza dentro de la sesión. Cuatro reglas del proyecto
que hay que respetar en cada tarea:

1. **`lib/badge.sh` es el único sitio que emite secuencias de escape.** Ningún otro archivo
   escribe `\033[...` a mano, ni siquiera para poner algo en negrita.
2. **El badge informa, no decide.** Sale con 0 por todos los caminos. Un color que no se pueda
   usar produce texto plano, nunca un error. Quien bloquea el arranque de Claude es siempre
   `_launch-check`.
3. **bash 3.2.** Nada de `declare -A`, `${var^^}`, `mapfile` ni namerefs en `bin/` y `lib/`.
4. **El recorte a 60 caracteres va por campo, no por línea.** `badge_sanitize` se llama sobre
   el perfil, el email y la carpeta por separado; la línea entera son esos tres campos más
   separadores, y recortarla a 60 la mutilaría.

Los tests corren con un `HOME` desechable (`tests/helper.bash`) y nunca tocan la máquina real.

**Línea base antes de empezar: 128 tests verdes y shellcheck limpio.**

```sh
bats tests/                                                # toda la suite
bats tests/badge.bats                                      # un archivo
shellcheck -s bash bin/claude-account install.sh lib/*.sh  # lint
```

### La aritmética, ya resuelta

El frente sale de `L = (299*R + 587*G + 114*B) / 1000`, con `L >= 140` → negro y `L < 140` →
blanco. Los valores que aparecen en los tests, calculados:

| Color | RGB | L | Frente |
|---|---|---|---|
| `#8fbc5a` | 143, 188, 90 | 163 | `38;2;0;0;0` |
| `#2d4f8b` | 45, 79, 139 | 75 | `38;2;255;255;255` |
| `#e0a458` | 224, 164, 88 | 173 | `38;2;0;0;0` |
| `#87b7ff` | 135, 183, 255 | 176 | `38;2;0;0;0` |

### La secuencia, entera

`badge_bar "#8fbc5a" "work" " · x"` emite exactamente esto (sin salto de línea al final):

```
\033[48;2;143;188;90;38;2;0;0;0m \033[1mwork\033[22m · x \033[0m
```

El espacio de guarda va **dentro** de la barra, a cada lado. El destacado cierra con `22m` y no
con `0m`: un reset completo a mitad de línea apagaría también el fondo y partiría la barra en
dos justo después del nombre del perfil.

## Estructura de archivos

| Archivo | Qué pasa con él | Task |
|---|---|---|
| `lib/badge.sh` | Entra `badge_strip`; `badge_sanitize` se reescribe encima. | 1 |
| `lib/badge.sh` | Entran `badge_fg` y `badge_bar`. | 2 |
| `lib/badge.sh` | Se borra `badge_color`, ya sin llamadores. | 4 |
| `bin/claude-account` | `cmd_statusline` arma la línea y llama una vez a `badge_bar`. | 3 |
| `bin/claude-account` | `car_colores` pinta la muestra con `badge_bar`. | 4 |
| `tests/badge.bats` | +1 test en Task 1, +6 en Task 2, −5 en Task 4. | 1, 2, 4 |
| `tests/statusline.bats` | Los 3 tests que fijaban el color pasan a fijar la barra. | 3 |
| `tests/check.bats` | La muestra de color pasa a ser una barra. | 4 |
| `README.md`, `routes.conf.example` | El campo `color` es el fondo, no el texto. | 5 |

El orden importa: `badge_bar` nace en la Task 2 antes de que la Task 3 lo use, y `badge_color`
no se borra hasta la Task 4, cuando ya no lo llama nadie. **Cada commit deja la suite verde.**

Cuenta de tests esperada al terminar cada tarea: 129, 140, 140, 135, 135.

> La Task 2 acabó en 140 y no en 135: la revisión de calidad pidió cinco tests más de
> endurecimiento —umbral exacto de luminancia, guardia numérico de `badge_fg`, color en
> mayúsculas, filtrado de control con la barra pintada, y canal con cero a la izquierda— más
> el guardia y la constante `CAR_BADGE_LUM` que los motivan. Las cuentas de abajo ya lo
> incluyen.

---

### Task 1: `badge_strip`, y `badge_sanitize` construida encima

El filtro de bytes de control y el recorte a 60 son hoy la misma función. `badge_bar` necesita
el filtro **sin** el recorte, así que se separan. Sin cambio de comportamiento: los 3 tests que
ya existen de `badge_sanitize` tienen que seguir pasando sin tocarlos.

**Files:**
- Modify: `lib/badge.sh:6-15`
- Test: `tests/badge.bats`

- [ ] **Step 1: Escribir el test que falla**

Añadir al final de `tests/badge.bats`:

```bash
@test "badge_strip filtra los bytes de control sin recortar" {
  # badge_bar necesita el filtro sin el recorte: la linea entera son tres
  # campos mas separadores, y recortarla a 60 la mutilaria.
  local largo
  largo="$(printf 'x%.0s' $(seq 1 200))"
  run badge_strip "$(printf 'ma\033[31mlo')$largo"
  [ "$status" -eq 0 ]
  [ "$output" = "ma[31mlo$largo" ]
  [ "${#output}" -eq 208 ]
}
```

- [ ] **Step 2: Verificar que falla**

Run: `bats tests/badge.bats`
Expected: FAIL en ese test, con `badge_strip: command not found`. Los otros 8 en verde.

- [ ] **Step 3: Implementar**

En `lib/badge.sh`, sustituir la función `badge_sanitize` entera (el bloque de comentario
incluido) por estas dos:

```sh
# badge_strip <texto> -> el texto sin bytes de control.
# El badge se arma con un nombre de carpeta y con un email leido de un archivo,
# y ninguno de los dos es texto de confianza: una carpeta puede llamarse con
# bytes de control adentro. Claude Code renderiza este texto respetando ANSI,
# asi que sin este filtro un nombre hostil podria colar sus propias secuencias.
badge_strip() {
  local text="$1"
  printf '%s' "${text//[[:cntrl:]]/}"
}

# badge_sanitize <texto> -> el texto filtrado y recortado a CAR_BADGE_MAX.
# El recorte va por campo y no por linea: la linea del badge son tres campos
# mas separadores, y recortarla entera a 60 la mutilaria.
badge_sanitize() {
  local text
  text="$(badge_strip "$1")"
  printf '%s' "${text:0:$CAR_BADGE_MAX}"
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `bats tests/badge.bats`
Expected: 9 tests en verde.

Run: `bats tests/ && shellcheck -s bash bin/claude-account install.sh lib/*.sh`
Expected: **129 tests** en verde, shellcheck sin salida.

- [ ] **Step 5: Commit**

```bash
git add lib/badge.sh tests/badge.bats
git commit -m "refactor: separar el filtro de control del recorte a 60"
```

---

### Task 2: `badge_fg` y `badge_bar`

Nacen las dos funciones nuevas. `badge_color` sigue existiendo y sus tests siguen pasando: se
borra en la Task 4, cuando ya no lo llame nadie.

**Files:**
- Modify: `lib/badge.sh` (añadir al final)
- Test: `tests/badge.bats`

- [ ] **Step 1: Escribir los tests que fallan**

Añadir al final de `tests/badge.bats`:

```bash
# #8fbc5a = rgb(143,188,90), luminancia 163 -> por encima del umbral -> texto negro.
@test "un color claro pinta la barra entera con texto negro" {
  run badge_bar "#8fbc5a" "work" " · ricardo@empresa.com · miapp"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033[48;2;143;188;90;38;2;0;0;0m \033[1mwork\033[22m · ricardo@empresa.com · miapp \033[0m')" ]
}

# #2d4f8b = rgb(45,79,139), luminancia 75 -> por debajo del umbral -> texto blanco.
# Es el caso que un frente fijo se comeria: con negro constante, ilegible.
@test "un color oscuro pinta la barra con texto blanco" {
  run badge_bar "#2d4f8b" "work" ""
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '\033[48;2;45;79;139;38;2;255;255;255m \033[1mwork\033[22m \033[0m')" ]
}

@test "el guion devuelve el texto sin barra y sin los espacios de guarda" {
  # Los espacios son parte de la barra: sin barra no hay nada que separar.
  run badge_bar "-" "personal" " · a@b.com"
  [ "$status" -eq 0 ]
  [ "$output" = "personal · a@b.com" ]
}

@test "un color invalido devuelve la linea igual, sin fallar" {
  run badge_bar "rojo; rm -rf /" "personal" " · a@b.com"
  [ "$status" -eq 0 ]
  [ "$output" = "personal · a@b.com" ]
}

@test "un color de longitud incorrecta tampoco pinta la barra" {
  run badge_bar "#abc" "personal" ""
  [ "$status" -eq 0 ]
  [ "$output" = "personal" ]
}

@test "la barra filtra los bytes de control de sus dos campos, sin recortar" {
  # Quien llama no puede colar su propia negrita ni su propio color: el filtro
  # no distingue un escape nuestro de uno que venga en un nombre de carpeta.
  local largo
  largo="$(printf 'y%.0s' $(seq 1 100))"
  run badge_bar "-" "$(printf 'ma\033[31mlo')" "$largo"
  [ "$status" -eq 0 ]
  [ "$output" = "ma[31mlo$largo" ]
}
```

- [ ] **Step 2: Verificar que fallan**

Run: `bats tests/badge.bats`
Expected: FAIL en los 6 nuevos, con `badge_bar: command not found`. Los 9 anteriores en verde.

- [ ] **Step 3: Implementar**

Añadir al final de `lib/badge.sh`:

```sh
# badge_fg <r> <g> <b> -> el frente que se lee sobre ese fondo, como "R;G;B".
# Luminancia YIQ: la formula de contraste de la WCAG exige linearizar cada canal
# antes de pesarlo, y para elegir entre exactamente dos frentes -negro o blanco-
# no cambia el resultado. Aritmetica entera: bash 3.2 no tiene otra.
badge_fg() {
  local lum=$(( (299 * $1 + 587 * $2 + 114 * $3) / 1000 ))
  if [ "$lum" -ge 140 ]; then
    printf '0;0;0'
  else
    printf '255;255;255'
  fi
}

# badge_bar <color|-> <destacado> [resto] -> la linea entera sobre el fondo.
# El destacado va en negrita y la emite esta funcion, no quien llama: un escape
# armado por fuera se lo comeria el filtro de control, y con razon, porque el
# filtro no puede distinguirlo de uno colado por un nombre de carpeta.
# Cierra con 22m y no con 0m: un reset a mitad de linea apagaria tambien el
# fondo y partiria la barra en dos.
# Un color ausente, "-" o mal formado devuelve el texto tal cual, sin barra y
# sin los espacios de guarda: el badge informa igual sin color, y aqui nada
# puede fallar de forma ruidosa.
badge_bar() {
  local color="${1:--}" strong rest red green blue fg
  strong="$(badge_strip "${2:-}")"
  rest="$(badge_strip "${3:-}")"
  case "$color" in
    '#'[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
      red="$(printf '%d' "0x${color:1:2}")"
      green="$(printf '%d' "0x${color:3:2}")"
      blue="$(printf '%d' "0x${color:5:2}")"
      fg="$(badge_fg "$red" "$green" "$blue")"
      printf '\033[48;2;%s;%s;%s;38;2;%sm \033[1m%s\033[22m%s \033[0m' \
        "$red" "$green" "$blue" "$fg" "$strong" "$rest"
      ;;
    *)
      printf '%s%s' "$strong" "$rest"
      ;;
  esac
}
```

- [ ] **Step 4: Verificar que pasan**

Run: `bats tests/badge.bats`
Expected: 15 tests en verde.

Run: `bats tests/ && shellcheck -s bash bin/claude-account install.sh lib/*.sh`
Expected: **135 tests** en verde, shellcheck sin salida.

- [ ] **Step 5: Commit**

```bash
git add lib/badge.sh tests/badge.bats
git commit -m "feat: badge_bar pinta el fondo de una linea y calcula su frente"
```

---

### Task 3: el badge del `statusline` pasa a ser una barra

**Files:**
- Modify: `bin/claude-account:25-84` (`cmd_statusline`)
- Test: `tests/statusline.bats`

- [ ] **Step 1: Escribir los tests que fallan**

En `tests/statusline.bats`, sustituir las dos constantes de arriba:

```bash
VERDE="$(printf '\033[1;38;2;143;188;90m')"
FIN="$(printf '\033[0m')"
```

por una función que arma la barra esperada:

```bash
# La barra del perfil 'work': #8fbc5a = rgb(143,188,90), luminancia 163 -> negro.
# Fijar la linea entera byte a byte prueba de paso lo que mas importa aqui: que
# hay UN solo 48;2 y UN solo reset, con el nombre del perfil en negrita dentro.
barra() {
  printf '\033[48;2;143;188;90;38;2;0;0;0m \033[1m%s\033[22m%s \033[0m' "$1" "$2"
}
```

Y sustituir los tres tests que usaban `$VERDE`:

```bash
@test "la linea entera va sobre el fondo del perfil, con el nombre en negrita" {
  make_profile ".claude-work" "ricardo@empresa.com"
  CLAUDE_CONFIG_DIR="$HOME/.claude-work" run badge
  [ "$output" = "$(barra "work" " · ricardo@empresa.com · miapp")" ]
}

@test "un perfil sin sesion lo dice en vez de inventar" {
  make_profile ".claude-work"
  CLAUDE_CONFIG_DIR="$HOME/.claude-work" run badge
  [ "$output" = "$(barra "work" " · (sin sesion) · miapp")" ]
}

@test "un archivo de identidad corrupto tambien sale como sin sesion" {
  make_profile ".claude-work"
  printf 'no soy json\n' > "$HOME/.claude-work/.claude.json"
  CLAUDE_CONFIG_DIR="$HOME/.claude-work" run badge
  [ "$output" = "$(barra "work" " · (sin sesion) · miapp")" ]
}
```

Los demás tests del archivo no se tocan: usan el perfil `personal`, que tiene color `-` y por
tanto sale igual que hoy, sin barra.

- [ ] **Step 2: Verificar que fallan**

Run: `bats tests/statusline.bats`
Expected: FAIL en esos 3, mostrando la línea con el color viejo (`\033[1;38;2;...` alrededor
solo del nombre del perfil) frente a la barra esperada. Los otros 9 en verde.

- [ ] **Step 3: Implementar**

En `bin/claude-account`, dentro de `cmd_statusline`, tres cambios.

Añadir `rest` a la línea de locales:

```sh
  local config_dir default_dir i profile color identity datos project label email rest
```

Sustituir el camino sin `python3`:

```sh
  if ! command -v python3 >/dev/null 2>&1; then
    badge_bar "$color" "$(badge_sanitize "$profile")" " · (sin python3)"
    printf '\n'
    return 0
  fi
```

Y sustituir las cuatro últimas líneas de la función:

```sh
  # La linea se arma entera y se envuelve UNA vez: el fondo tiene que cubrir
  # tambien el email y la carpeta, no solo el nombre del perfil. Cada campo
  # pasa por badge_sanitize -el perfil tambien, que hasta ahora se saneaba de
  # rebote dentro de badge_color- porque el recorte a 60 va por campo.
  rest=" · $(badge_sanitize "$email")"
  [ -n "$label" ] && rest="$rest · $(badge_sanitize "$label")"
  badge_bar "$color" "$(badge_sanitize "$profile")" "$rest"
  printf '\n'
  return 0
```

- [ ] **Step 4: Verificar que pasan**

Run: `bats tests/statusline.bats`
Expected: 12 tests en verde.

Run: `bats tests/ && shellcheck -s bash bin/claude-account install.sh lib/*.sh`
Expected: **140 tests** en verde, shellcheck sin salida.

- [ ] **Step 5: Commit**

```bash
git add bin/claude-account tests/statusline.bats
git commit -m "feat: el badge pinta el fondo de toda su linea"
```

---

### Task 4: la muestra de `check`, y el borrado de `badge_color`

La muestra que imprime `check` existe para que un tono que no convenza se vea fuera de la
sesión. Si la muestra se pinta distinta del badge, deja de servir para eso. Con este cambio
`badge_color` se queda sin llamadores y se borra.

**Files:**
- Modify: `bin/claude-account:236-243` (`car_colores`)
- Modify: `lib/badge.sh` (borrar `badge_color`)
- Test: `tests/check.bats`, `tests/badge.bats`

- [ ] **Step 1: Escribir el test que falla**

En `tests/check.bats`, sustituir el test del color entero (el comentario de encima incluido)
por este:

```bash
# #8fbc5a = rgb(143, 188, 90), luminancia 163 -> texto negro. La prueba fija la
# barra completa pegada a la linea de SU perfil (no solo que aparezca en algun
# sitio del output): una muestra impresa encima del perfil anterior, o la de
# otro perfil, tambien haria pasar una comprobacion que solo buscara la
# secuencia suelta.
@test "la muestra del perfil sale con su propio fondo, debajo de su perfil" {
  perfiles_ok
  run "$CA" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"work: ricardo@empresa.com"$'\n'"       badge $(printf '\033[48;2;143;188;90;38;2;0;0;0m \033[1m#8fbc5a\033[22m \033[0m')"* ]]
  # personal no declara color ("-" en routes.conf): fijar tambien su linea
  # detecta ademas que las dos lineas no se hayan intercambiado entre si.
  [[ "$output" == *"personal: tu-email@ejemplo.com"$'\n'"       badge -"* ]]
}
```

- [ ] **Step 2: Verificar que falla**

Run: `bats tests/check.bats`
Expected: FAIL en ese test. Los otros 9 en verde.

- [ ] **Step 3: Implementar**

En `bin/claude-account`, `car_colores` pasa a usar `badge_bar`, con el hex como destacado y
sin resto:

```sh
# car_colores <indice>
# El color del badge del perfil, pintado como se vera el badge: un tono que no
# convenza se delata aqui, en vez de descubrirse dentro de la sesion.
# Linea informativa y no una comprobacion: no toca car_check_ok ni car_check_bad.
car_colores() {
  local i="$1"
  printf '       badge %s\n' "$(badge_bar "${CAR_P_COLOR[$i]}" "${CAR_P_COLOR[$i]}")"
}
```

- [ ] **Step 4: Verificar que pasa**

Run: `bats tests/check.bats`
Expected: 9 tests en verde.

- [ ] **Step 5: Borrar `badge_color` y sus tests**

Comprobar primero que no queda ningún llamador:

Run: `grep -rn 'badge_color' bin lib tests shell install.sh`
Expected: solo las líneas de `lib/badge.sh` y de `tests/badge.bats`. Si aparece cualquier otro
archivo, **parar**: hay un llamador que este plan no vio.

Borrar de `lib/badge.sh` la función `badge_color` entera, con su bloque de comentario.

Borrar de `tests/badge.bats` estos 5 tests, que son los que la probaban:

```
@test "un color valido pinta el texto en negrita con SGR de 24 bits"
@test "el guion devuelve el texto sin colorear"
@test "un color invalido devuelve el texto igual, sin fallar"
@test "un color de longitud incorrecta tampoco pinta"
@test "un texto coloreado tambien pasa por el saneo"
```

Sus equivalentes para `badge_bar` ya entraron en la Task 2, con nombres distintos. Los 3 tests
de `badge_sanitize` y el de `badge_strip` se quedan.

- [ ] **Step 6: Verificar**

Run: `grep -rn 'badge_color' bin lib tests shell install.sh`
Expected: sin resultados. (En `docs/` sí sigue apareciendo: las specs viejas son historia y no
se reescriben.)

Run: `bats tests/ && shellcheck -s bash bin/claude-account install.sh lib/*.sh`
Expected: **135 tests** en verde, shellcheck sin salida.

- [ ] **Step 7: Commit**

```bash
git add bin/claude-account lib/badge.sh tests/badge.bats tests/check.bats
git commit -m "feat: check pinta la muestra como se vera el badge"
```

---

### Task 5: la documentación

El README dice hoy del campo `color` que "es texto, no un tinte". Con este cambio es lo
contrario, y es la frase que guía a quien elige un color.

**Files:**
- Modify: `README.md:87-90`, `README.md:183-186`, `README.md:198-200`
- Modify: `routes.conf.example:5-7`
- Modify: `docs/superpowers/specs/2026-09-02-fondo-del-badge-design.md:4`

- [ ] **Step 1: El campo `color` en el README**

Sustituir el bullet de `README.md:87-90`:

```markdown
- `color` es el `#rrggbb` con el que se pinta el nombre del perfil en el badge. `-` lo deja
  sin color. Conviene un tono legible sobre el fondo de tu tema: es texto, no un tinte.
  `claude-account check` lo imprime pintado con el suyo, así que un tono ilegible se ve ahí
  en vez de descubrirse dentro de una sesión.
```

por:

```markdown
- `color` es el `#rrggbb` con el que se pinta el **fondo** de la línea del badge. `-` la deja
  sin fondo. El color del texto no se declara: sale de la luminancia del fondo —negro sobre
  los tonos claros, blanco sobre los oscuros—, así que cualquier color se lee.
  `claude-account check` imprime la muestra con ese mismo fondo, así que un tono que no
  convenza se ve ahí en vez de descubrirse dentro de una sesión.
```

- [ ] **Step 2: El ejemplo del badge en el README**

En la sección `### El badge`, justo debajo del bloque

```
work · tu-cuenta@empresa.com · traza-backend
```

añadir este párrafo, antes del que empieza por "El perfil y el email":

```markdown
Esa línea entera va sobre el fondo del color del perfil, con el nombre del perfil en negrita.
El fondo llega hasta donde llega el texto y ni un carácter más: la fila no se rellena hasta el
ancho de la terminal, porque esa superficie no es nuestra.
```

- [ ] **Step 3: La sección de Seguridad del README**

Sustituir, en `README.md:198-200`:

```markdown
`lib/badge.sh` los filtra y recorta el texto antes de emitirlo, y `lib/statusline.py`
los filtra otra vez en el punto por el que entran. El color se valida contra `#rrggbb` antes de
entrar en una secuencia.
```

por:

```markdown
`lib/badge.sh` los filtra antes de emitirlos, `bin/claude-account` los recorta a 60 caracteres
campo a campo, y `lib/statusline.py` los filtra otra vez en el punto por el que entran. Ni
siquiera el propio badge arma escapes por fuera: la negrita del nombre del perfil la emite
`lib/badge.sh`, porque el filtro no puede distinguir un escape nuestro de uno colado por un
nombre de carpeta. El color se valida contra `#rrggbb` antes de entrar en la secuencia, y el
color del texto no viene de fuera: se calcula.
```

- [ ] **Step 4: `routes.conf.example`**

Sustituir las tres líneas del campo `color`:

```
#     color:      #rrggbb con el que se pinta el nombre del perfil en el badge
#                 que se ve dentro de Claude Code. "-" = sin color. Conviene un
#                 tono legible sobre el fondo de tu tema, no un tinte apagado.
```

por:

```
#     color:      #rrggbb con el que se pinta el fondo de la linea del badge
#                 que se ve dentro de Claude Code. "-" = sin fondo. El color
#                 del texto no se declara: se calcula para que se lea encima.
```

- [ ] **Step 5: Marcar la spec como implementada**

En `docs/superpowers/specs/2026-09-02-fondo-del-badge-design.md`, línea 4:

```markdown
**Estado:** aprobado, sin implementar
```

pasa a:

```markdown
**Estado:** implementado
```

- [ ] **Step 6: Revisar la tabla de arquitectura**

Run: `grep -n 'lib/badge.sh' README.md`
Expected: la fila dice "Único emisor de secuencias de escape del proyecto". Sigue siendo cierta
—ahora más que antes, porque la negrita también sale de ahí— así que **no se toca**. Este paso
existe para que quede comprobado en vez de supuesto.

- [ ] **Step 7: Verificar**

Run: `grep -n 'es texto, no un tinte' README.md routes.conf.example`
Expected: sin resultados.

Run: `bats tests/`
Expected: **135 tests** en verde. (Ningún test lee el README, pero la suite se corre igual
antes de cada commit.)

- [ ] **Step 8: Commit**

```bash
git add README.md routes.conf.example docs/superpowers/specs/2026-09-02-fondo-del-badge-design.md
git commit -m "docs: el campo color es el fondo del badge, no su texto"
```

---

### Task 6: verificación en una sesión real

La spec anota un riesgo que ningún test puede cerrar: se da por hecho que Claude Code respeta
`48;2` en el `statusLine` igual que respeta `38;2`. Esto se comprueba mirando.

**Files:** ninguno. Es una verificación.

- [ ] **Step 1: Ver los bytes que salen**

```sh
echo '{"workspace":{"project_dir":"'"$PWD"'"}}' | ./bin/claude-account statusline | cat -v
```

Expected: una línea que empieza por `^[[48;2;`, con `^[[1m` alrededor del nombre del perfil,
`^[[22m` justo después, y un único `^[[0m` al final.

- [ ] **Step 2: Ver la muestra de `check`**

Run: `./bin/claude-account check`
Expected: la línea `badge` de cada perfil sale como una pastilla con el hex escrito encima de
su propio color. Si alguno cuesta de leer, el color se cambia en `routes.conf` — no hace falta
tocar código ni reinstalar nada.

- [ ] **Step 3: Ver el badge dentro de Claude Code**

Abrir una sesión de Claude en cualquier carpeta y mirar la línea del badge. No hace falta
reinstalar: el `settings.json` de los perfiles apunta al mismo comando de siempre.

Expected: la línea entera sobre el fondo del perfil.

Si Claude Code estripara el `48;2`, el badge se vería como se veía antes —texto sin barra— y
no roto. En ese caso, dejar constancia en la spec (sección "Riesgo anotado") de que la vía no
existe, en vez de revertir a ciegas: el resto del cambio —frente calculado, negrita, saneado
por campo— sigue siendo correcto.

- [ ] **Step 4: Cerrar la rama**

Con la suite verde y el badge visto funcionando, usar la skill
`superpowers:finishing-a-development-branch` para decidir cómo integra `fondo-del-badge`.

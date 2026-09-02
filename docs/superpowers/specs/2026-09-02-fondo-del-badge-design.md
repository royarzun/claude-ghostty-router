# El fondo del badge — Diseño

**Fecha:** 2026-09-02
**Estado:** implementado; falta ver el badge en una sesión real (ver «Riesgo anotado»)

**Modifica:** [2026-09-02-badge-en-statusline-design.md](2026-09-02-badge-en-statusline-design.md)

## Problema

El badge dice la cuenta con todas sus letras, pero la dice en voz baja. Dentro de la sesión es
una fila más entre las que pinta Claude Code, y lo único que la separa del resto es el nombre
del perfil coloreado: tres o cuatro caracteres de color en una línea de texto. El badge existe
para que una cuenta equivocada salte a la vista, y hoy hay que ir a buscarlo.

Subir el volumen con más color de texto no da más de sí: el nombre del perfil ya va en negrita
y a color pleno. Lo que falta no es más saturación, es superficie.

## Objetivo

Que la línea del badge se lea como un bloque y no como texto suelto: el color del perfil pasa
a ser el **fondo** de toda la línea, y el texto de encima se elige para que se lea sobre él.

El fondo llega hasta donde llega el texto del badge y ni un carácter más. No se emite `\033[K`
ni se rellena la fila hasta el ancho de la terminal: teñir superficie que no es nuestra es
exactamente el marcado permanente que este proyecto ya probó y quitó
([spec del color](2026-09-02-color-solo-en-claude-design.md)). La barra termina donde termina
lo que el router tiene que decir.

## Comportamiento

```
 work · d.f.d.chile@gmail.com · traza-backend
```

Toda esa línea sobre un fondo `#87b7ff`, con `work` en negrita y el resto en texto normal, los
dos en el frente que se calcule para ese fondo. Un espacio a cada lado para que la barra no
pegue con los glifos.

| Situación | Qué muestra |
|---|---|
| Perfil con color `#rrggbb` | la línea entera sobre el fondo del perfil |
| Perfil con color `-`, o mal formado | la línea entera sin fondo y sin color, como hoy |
| `routes.conf` inválido o ausente | `⚠ routes.conf invalido`, sin fondo: no hay perfil del que sacar un color |
| Perfil sin sesión, o identidad corrupta | igual, con `(sin sesion)` en el lugar del email |
| Sin `python3` | `perfil · (sin python3)`, con su fondo |

El badge sigue sin fallar y sin bloquear: sale con 0 por todos los caminos, y un color que no
se pueda usar produce texto plano, nunca un error.

## Decisiones

**El color del texto se calcula, no se fija.** `routes.conf` acepta cualquier `#rrggbb`, así
que un frente constante es una apuesta: negro fijo se borra sobre un perfil azul marino, y
blanco fijo se borra sobre uno ámbar. El frente sale de la luminancia del propio fondo:

```
L = (299 * R + 587 * G + 114 * B) / 1000
L >= 140 → texto negro     L < 140 → texto blanco
```

Es la ponderación YIQ de toda la vida, no el contraste de la WCAG —que exige linearizar cada
canal antes de pesarlo—. Para elegir entre exactamente dos frentes la diferencia entre las dos
fórmulas casi no se ve, y en aritmética entera de bash 3.2 la diferencia de coste sí. Con los
colores de hoy, `#e0a458` da 173 y `#87b7ff` da 176: los dos, texto negro.

**El perfil se distingue por la negrita, no por el color.** Hasta ahora el nombre del perfil
era lo único coloreado de la línea; ahora el color es la línea entera, así que necesita otra
marca. Va envuelto en `\033[1m` … `\033[22m`, y el cierre es `22m` y no `0m` a propósito: un
reset completo a mitad de línea apagaría también el fondo, y la barra se partiría en dos justo
después del nombre. La negrita la emite `badge_bar`, no quien la llama: por eso el nombre del
perfil entra como un argumento aparte del resto de la línea. Si el llamador armara su propio
`\033[1m`, el filtro de control de `badge_bar` se lo comería —y con razón, porque ese filtro no
puede distinguir un escape nuestro de uno colado por un nombre de carpeta—.

**`badge_color` se convierte en `badge_bar`.** Al envolver la línea entera no queda ningún
sitio que pinte solo texto, ni siquiera `check`: la muestra de color que `check` imprime tiene
que verse **como se verá el badge**, o dejaría de servir para lo que se puso —descubrir un tono
ilegible fuera de la sesión en vez de dentro—. Una función, un contrato, y `lib/badge.sh` sigue
siendo el único emisor de escapes del proyecto.

**El saneado se parte en dos.** `badge_sanitize` filtra bytes de control **y recorta a 60**, y
se sigue llamando campo por campo en `cmd_statusline`, ahora también sobre el nombre del
perfil, que hasta hoy se saneaba de rebote al pasar por `badge_color`. `badge_bar` filtra otra vez, sin recortar:
aplicar el recorte de 60 a la línea completa la mutilaría, y el recorte que de verdad acota lo
que un nombre de carpeta hostil puede ocupar es el de por campo. Sigue siendo cierto que nada
sale de `badge.sh` sin pasar por el filtro.

**El fondo se valida como se validaba el frente.** El color entra en la secuencia solo si casa
`#rrggbb` carácter a carácter; cualquier otra cosa devuelve el texto tal cual.

## Lo que cambia

**`lib/badge.sh`**

- `badge_color` → `badge_bar <color> <destacado> [resto]`: emite
  `\033[48;2;R;G;B;38;2;F;F;Fm` ` ` `\033[1m<destacado>\033[22m<resto>` ` ` `\033[0m`, con el
  frente calculado y el espacio de guarda a cada lado **dentro** de la barra. Sin un color
  válido devuelve `<destacado><resto>` en plano: sin barra, y por tanto sin esos espacios.
- Entra `badge_fg <R> <G> <B>`, interna: devuelve `0;0;0` o `255;255;255`.
- Entra `badge_strip <texto>`, interna: filtra control sin recortar. `badge_sanitize` pasa a
  ser `badge_strip` + recorte, para que el filtro viva escrito una sola vez.

**`bin/claude-account`**

- `cmd_statusline` sanea cada campo por separado y hace **una sola** llamada a `badge_bar`, con
  el perfil como destacado y ` · email · carpeta` como resto. Hoy llama una vez por el perfil y
  concatena el resto por fuera, que es justo lo que deja el resto de la línea sin fondo.
- `car_colores` imprime la muestra con `badge_bar "$color" "$color"`: el hex, en negrita, sobre
  su propio fondo.

No se toca nada más: `statusline.py`, `identity.{sh,py}`, `resolve.sh`, `config.sh`,
`settings.py`, `install.sh` y `router.zsh` quedan igual. El `settings.json` de los perfiles no
cambia, así que no hace falta reinstalar nada para ver el badge nuevo.

## Tests

**`tests/badge.bats`** cambia los casos de `badge_color` por los de `badge_bar`, y fija bytes
exactos como ya hacía: la secuencia completa de un color claro con texto negro, la de un color
oscuro con texto blanco, el `-` y el color mal formado devolviendo el texto sin ningún escape,
y el filtrado de bytes de control **sin** recorte a 60 en una línea larga. Se conservan los
tests de `badge_sanitize` tal cual: su contrato no cambia.

**`tests/statusline.bats`** gana que la línea sale envuelta una sola vez —un solo `48;2` y un
solo `\033[0m`, al principio y al final— con el nombre del perfil en negrita dentro, y que
`⚠ routes.conf invalido` sale sin ningún escape.

**`tests/check.bats`** se ajusta a una muestra pintada como barra.

## Documentación

El README dice hoy del campo `color` que "conviene un tono legible sobre el fondo de tu tema:
es texto, no un tinte". Con este cambio es al revés: es el fondo, y el texto de encima lo
elige el propio badge, así que lo que conviene es un tono que se distinga del fondo del tema.
Hay que revisar esa línea, el ejemplo de la sección "El badge", el comentario del campo `color`
en `routes.conf.example`, y la fila de `lib/badge.sh` en la tabla de arquitectura.

La sección de Seguridad sigue siendo cierta y se queda, con una frase de más: el fondo se
valida contra `#rrggbb` igual que se validaba el frente.

## Riesgo anotado

Se da por hecho que Claude Code respeta `48;2` en el `statusLine` igual que respeta `38;2`. No
está verificado; se ve en la primera sesión después del cambio. Si lo estripara, el badge se
vería como se ve hoy —texto sin barra—, no roto: el modo de fallo es degradarse, que es la
regla que el badge ya sigue en todos sus caminos.

## Fuera de alcance

- Rellenar la fila hasta el ancho de la terminal (`\033[K`) o teñir cualquier superficie que no
  sea el texto del badge.
- Declarar fondo y frente a mano en `routes.conf`. El campo `color` sigue siendo uno solo y
  sigue siendo `#rrggbb`.
- Añadir modelo, coste, contexto o rama al badge.
- Cualquier cambio en la verificación de identidad o en el bloqueo *fail-closed*.

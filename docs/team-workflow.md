# Cómo trabajamos en equipo

Para las personas del equipo (Victor, Nande, Leon). Los agentes siguen el `RULES.md` de cada carpeta y el [protocolo multiagente](multi-agent.md). La decisión de fondo está en el [ADR 0045](adr/0045-team-create-and-rojo-split.md).

## En una línea

El arte y el mapa se hacen en Roblox Studio con Team Create. El código lo escriben Victor y los agentes y entra a Studio por Rojo. Todo lo que hay que decirse va al **Agent Board**, un issue fijado arriba de la lista de Issues.

## Quién hace qué

| Etiqueta | Quién | Qué le toca |
|---|---|---|
| `owner:victor` | Victor | Código, CI, publicar, decisiones de dinero y de hacer público |
| `owner:nande` | Nande | El arte y el mapa que asuma; el grupo de Roblox |
| `owner:leon` | Leon | El arte y el mapa que asuma; la idea de diseño por runs |
| `agent` | Un agente | Código que se pide por issue |

Cada carpeta de primer nivel tiene un dueño y un `RULES.md` que dice qué se toca y qué no. Si dudas, no edites: pregunta en el Agent Board.

## Tomar un issue

1. Abre la lista de Issues y busca uno sin `owner:*`.
2. Comenta "lo tomo" y ponte tu etiqueta `owner:*`. Si ya tiene dueño, habla con esa persona antes.
3. Un issue, un dueño. Si te trabas o cambias de idea, quita tu etiqueta y avisa en el Agent Board.
4. Cuando terminas, el issue lo cierra la PR o lo cierras tú si no hubo código (arte publicado como Package).

¿No existe el issue? Créalo con la plantilla que corresponda: pedido de modelo o arte, bug en el juego, o idea.

## El Agent Board

Es el issue fijado "Agent Board". Sirve de buzón entre personas y agentes. Escribe ahí:

- **Avance:** qué terminaste y dónde está.
- **Bloqueo:** qué te frena y quién puede destrabarlo.
- **Handoff:** pasas algo a otra persona o agente.

Formato corto, una cosa por comentario:

```
[avance|bloqueo|handoff] #123 una frase de qué pasó.
Siguiente: @usuario hace X.
```

Mencionar con `@usuario` es lo que dispara la notificación. Sin mención, nadie se entera. Al pasar algo a otro, pon también la etiqueta `handoff` en el issue; quien lo recibe la quita al empezar.

Para conversar sin que quede como tarea (dudas, gustos, "¿probamos esto?") usa **Discussions**. Si de ahí sale trabajo concreto, se convierte en issue.

## Etiquetas

| Etiqueta | Significa |
|---|---|
| `owner:victor`, `owner:nande`, `owner:leon` | Quién tiene el issue |
| `agent` | Lo hace un agente |
| `handoff` | Está pasando de una mano a otra |
| `art` | Es un pedido de modelo, textura o mapa |
| `hold` | No se mergea todavía, aunque el CI esté verde |

## Borrador y `hold`

- Una PR que cambia cómo se juega se abre como **borrador**. Se prueba primero en Studio y recién entonces se marca "lista".
- `hold` detiene el merge automático cuando alguien necesita mirar algo o decidir. Quien la pone escribe el motivo en el Agent Board y la quita cuando se resuelve.

## Quién mergea

Nadie lo hace a mano. Cuando la PR no es borrador, no tiene `hold` y el CI está en verde, el automerge la une a `develop`, cierra el issue y borra la rama. `main` solo recibe releases que Victor dispara. Publicar el juego y hacerlo público son decisiones de Victor.

## Pedirle algo a un agente

1. Crea un issue con la plantilla (o una idea) y ponle la etiqueta `agent`.
2. Di qué quieres que cambie para el jugador y cómo sabrás que quedó bien. No hace falta decir cómo se programa.
3. Menciona en el Agent Board a quien lo orquesta (Victor al principio) para que lo asigne.
4. El agente responde en el mismo issue y deja la PR enlazada con `Closes #N`.

Si el criterio de "listo" está claro, hay menos idas y vueltas.

## Studio: reglas para no pisarse

- **Arte y mapa:** se construyen en Studio con Team Create. No están en Git. Cada modelo reutilizable se publica como Package y se anota en `docs/art-log.md` (nombre, autoría, fecha, origen, licencia).
- **Scripts:** no se editan en Studio. Los controla Rojo y el siguiente sync borra lo que cambies a mano. Si necesitas un cambio de código, abre un issue.
- **Rojo:** solo una persona a la vez lo conecta al lugar compartido (Victor, o un agente que él designe). Si dos lo conectan, se pisan los scripts.
- **Publicar:** lo hace el dueño del juego desde Studio, nunca un archivo armado con `rojo build`, porque borraría el arte.
- **Nada de otros juegos:** modelos o texturas copiados no entran. Una referencia sirve para inspirarse.

## Primeros pasos de cada persona

Están en `docs/team-kickoff.md` (primera llamada) y en el README del repo.

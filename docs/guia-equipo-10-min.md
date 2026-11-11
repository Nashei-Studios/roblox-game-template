# Guía de 10 minutos para Nande y Leon

Qué vas a aprender: tomar una tarea, avisar en el tablero y abrir una PR (una propuesta de cambio). Todo se puede hacer desde la web de GitHub o desde GitHub Desktop. No necesitas terminal.

**Tu vista principal es Notion.** Ahí ves todas las tareas y PR del juego en una tabla, sin entrar a GitHub. Lo que cambias en Notion no se guarda en GitHub: las tareas se toman y se cierran en GitHub. Notion es para mirar.

## Antes de empezar (una sola vez, 3 minutos)

1. Acepta la invitación a la organización y al repo. Te llega por correo y a las notificaciones de GitHub.
2. En GitHub, arriba a la derecha: tu foto, Settings, Notifications. Deja marcado "Email" para menciones. Así sabes cuándo te escriben.
3. Abre el enlace de Notion que te mandó Victor y guárdalo en favoritos.
4. Si vas a subir archivos desde tu computador, instala GitHub Desktop e inicia sesión.

## 1. Tomar una tarea (2 minutos)

1. En el repo abre la pestaña **Issues**. Cada issue es una tarea.
2. Busca una que no tenga persona asignada. Ábrela.
3. A la derecha, en **Assignees**, pulsa "assign yourself" (asígnatelo).
4. Escribe un comentario: "La tomo". Pulsa **Comment**.

Si ya tiene dueño, no la tomes: escríbele a esa persona.
Si no encuentras la tarea que necesitas, pulsa **New issue** y elige la plantilla "Tarea". Rellena las tres preguntas.

## 2. Avisar en el tablero (2 minutos)

El tablero es un issue fijado arriba de la lista, llamado **Agent Board**. Sirve para avisar, no para conversar largo.

1. Ábrelo y baja hasta el cuadro de comentarios.
2. Escribe una sola cosa, con este formato:

   `[Avance] #12 Terminé el cartel del lobby, está en el Studio.`
   `Siguiente: @usuario-de-Victor lo conecta.`

   Las palabras para empezar son **Avance**, **Bloqueo** (algo te frena) o **Traspaso** (se lo pasas a otra persona).
3. Escribe `@` y el usuario de la persona a la que avisas. Sin la mención, nadie recibe notificación.
4. Pulsa **Comment**.

Para dudas o ideas sueltas ("¿probamos esto?") usa la pestaña **Discussions**, no el tablero.

## 3. Abrir una PR (3 minutos)

Una PR sirve cuando tu cambio es un archivo del repo (por ejemplo, una nota en `docs/art-log.md` con el modelo que hiciste). El arte en sí vive en Roblox Studio con Team Create, no en GitHub.

**Desde la web (lo más simple):**
1. Abre el archivo en GitHub y pulsa el lápiz (Edit).
2. Haz tu cambio.
3. Pulsa **Commit changes**. Elige "Create a new branch" y pulsa **Propose changes**.
4. En la pantalla siguiente, en la descripción escribe `Closes #12` (el número de tu tarea) y una frase de qué cambiaste.
5. Pulsa **Create pull request**.

**Desde GitHub Desktop:**
1. Menú Branch, New branch. Ponle un nombre corto, por ejemplo `arte-cartel`.
2. Cambia los archivos. Aparecen a la izquierda. Escribe un resumen abajo y pulsa **Commit**.
3. Pulsa **Publish branch** y luego **Create Pull Request**. Se abre la web; escribe `Closes #12` y pulsa **Create pull request**.

Después Victor (o su agente) la revisa y la une. Si pide cambios, te llega una notificación. Cuando se une, la tarea se cierra sola.

## 4. Dónde ver todo en Notion

- **Tabla de tareas y PR:** una fila por cada issue y PR. Filtra por tu nombre en la columna Assignees.
- **Estado:** open (abierta), draft (borrador), merged (unida) o closed (cerrada).
- Si algo se ve desactualizado, espera un minuto y recarga. Si sigue igual, avisa en el tablero.

## Si te trabas

- No borres nada ni fuerces nada. Casi todo se puede deshacer.
- Escribe en el tablero con el formato **Bloqueo** y menciona a Victor.
- Dudas de cómo se hace algo: pregunta en Discussions, categoría Preguntas.

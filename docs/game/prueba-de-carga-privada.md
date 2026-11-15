---
doc: prueba-de-carga-privada
stage: 10
revisit: 12
owner: el agente redacta; la ejecutan administradores del grupo; Victor aprueba el registro
status: draft
as_of:
sections: Respuestas, Material, Roles, Antes de empezar, Caso 1 Tiempo de entrada, Caso 2 Teléfono de gama baja, Caso 3 Servidor lleno, Caso 4 Regresión en Studio, Registro, Criterio de listo, Evidencia
---
# Prueba de carga privada para administradores

Procedimiento para medir el tiempo de entrada, el teléfono y el servidor lleno con administradores reales, sobre la versión publicada en privado. Se escribe para que quien no estuvo la primera vez lo ejecute desde cero y obtenga lo mismo. Los topes contra los que se compara viven en [`load-budget.md`](load-budget.md); si un número de esta página difiere de esa tabla, manda la tabla.

Qué es: cuatro casos con material, roles, criterio de aceptación por paso, qué hacer si falla y dónde queda el resultado. Qué no es: una prueba de cientos de clientes (no hay forma oficial verificada de hacerla), ni el testeo por el MCP de Studio, ni la ronda de beta con celular grabado ([`beta-testing.md`](beta-testing.md)), ni una medición precompletada. Ningún valor de esta página es un resultado: todo lo medido se escribe el día de la prueba.

## Preguntas que debe responder

1. ¿Qué versión se probó y quién estaba en cada rol?
2. ¿Cuánto tarda la entrada, la primera vez y al reentrar antes de 3 minutos?
3. ¿Qué FPS y qué memoria da un teléfono de gama baja real?
4. ¿Qué latido, memoria y red tiene el servidor con todos los administradores dentro?
5. ¿Qué caso falló y qué issue quedó abierto?

## Respuestas

1. TBD (#203), se llena en el registro del día de la prueba.
2. TBD (#203)
3. TBD (#203)
4. TBD (#203)
5. TBD (#203)

## Material

| Material | Para qué | Criterio de que está listo |
|---|---|---|
| Versión del juego publicada en privado, con su número SemVer y el SHA del commit | Es lo que se prueba | Se puede abrir desde la página de la experiencia con una cuenta administradora |
| Roblox Player en un PC (no Studio) | Casos 1 y 3 | Abre la experiencia y entra |
| Un teléfono Android de gama baja, con modelo y versión de sistema anotados | Caso 2 | Tiene Roblox instalado y la sesión de un administrador |
| Una cuenta administradora por persona, entre 3 y 6 personas | Casos 1 y 3 | Cada una puede entrar al servidor privado |
| La sonda de entrada (ADR 0032) activada por su bandera, solo en la versión de prueba | Casos 1 y 3 | La línea `[JOINPROBE]` aparece en el registro del servidor al entrar |
| Acceso al registro del servidor y a la Developer Console (F9) | Casos 1 a 3 | Quien lee el servidor ve la pestaña Server Jobs y la pestaña Memory |
| Studio con el proyecto sincronizado por Rojo en una copia local | Caso 4 | Test, Clients and Servers, abre 6 clientes sin errores rojos |
| Un cronómetro (el del teléfono sirve) | Caso 1 si la sonda falla | Marca segundos |
| El archivo `docs/game/qa-plan.md` abierto | Registro | Tiene la sección `## Evidencia` |

## Roles

| Rol | Hace | Cuántas personas |
|---|---|---|
| Coordinador | Lleva el orden, anota cada resultado en el registro, decide parar | 1 |
| Jugador de entrada | Entra, sale y reentra siguiendo el caso 1 | 1 |
| Operador del teléfono | Corre el caso 2 en el teléfono | 1 |
| Lector del servidor | Lee Server Jobs, Memory y el registro del servidor en los casos 1 y 3 | 1, puede ser el coordinador |
| Administradores de relleno | Entran y juegan con normalidad en el caso 3 | hasta completar el tope de jugadores por servidor |

Una misma persona puede cubrir dos roles, salvo coordinador y jugador de entrada. Quien probó no es quien escribió el código que se mide.

## Antes de empezar

1. **Anotar la versión.** Escribir la versión SemVer y el SHA en una hoja nueva. Criterio: ambos están escritos y coinciden con lo publicado. Si no coinciden: no empezar, publicar la versión correcta en privado.
2. **Confirmar que el servidor es privado.** La experiencia sigue sin acceso público. Criterio: una cuenta que no es del grupo no puede abrirla. Si puede: parar y avisar a Victor; nada de esta prueba se hace en público.
3. **Activar la sonda** solo en la versión de prueba y comprobar la línea `[JOINPROBE]` con una entrada de ensayo. Criterio: la línea aparece. Si no: seguir con el cronómetro en el caso 1 y anotarlo en el registro.
4. **Reunir a los roles** y fijar el modelo del teléfono en la hoja. Criterio: cada rol tiene nombre. Si falta alguien: el caso que lo necesita queda `no ejecutado`, nunca se rellena.

## Caso 1 Tiempo de entrada

Mide cuánto tarda en estar jugable y separa la espera por el candado de sesión.

1. **Primera entrada.** El jugador de entrada pulsa Jugar en Roblox Player. El coordinador arranca el cronómetro al clic y lo para cuando el personaje y el HUD están visibles y se puede mover. Criterio: la sonda y el cronómetro dan un tiempo cada uno. Si no hay línea de sonda: anotar solo el cronómetro.
2. **Repetir hasta 5 entradas.** La entrada 1 es la primera del día. Las entradas 2 y 3 son reentradas: salir de la experiencia por completo y volver en menos de 3 minutos. Las entradas 4 y 5 son reentradas tras esperar más de 3 minutos. Criterio: hay 5 tiempos, cada uno marcado como "primera", "reentrada en menos de 3 min" o "reentrada tras más de 3 min". Si una entrada fracasa o expulsa al jugador: anotarla como fallo con el mensaje que mostró, no repetirla en silencio.
3. **Calcular.** Con los 5 tiempos, p50 es el tercero ordenado de menor a mayor y p90 es el mayor. Criterio: ambos están escritos junto a los topes de la fila "Entrada a jugable" de `load-budget.md`, y cada tiempo sobre el fallo duro de esa fila queda marcado. Si p50 o p90 pasan el tope: no tocar constantes; abrir un issue `tipo:bug` con los 5 tiempos (la regla de ADR 0032: medir antes de cambiar).
4. **Aislar el candado de sesión.** Comparar las reentradas en menos de 3 minutos con las demás. Si las reentradas son mucho más lentas y la espera es un múltiplo de 5 s, el candado de sesión es el sospechoso. Criterio: el coordinador escribe qué observó, sin interpretar. Si no hay diferencia: escribirlo igual.

## Caso 2 Teléfono de gama baja

1. **Preparar.** El operador entra desde el teléfono al servidor privado y abre la Developer Console. Criterio: ve la pestaña Memory. Si el teléfono no la ofrece: anotar "sin consola en este dispositivo" y usar el medidor de rendimiento que sí ofrezca, nombrándolo.
2. **FPS.** Jugar 5 minutos con el loop normal y leer el FPS cada minuto. Criterio: 5 lecturas escritas; el p10 se aproxima con la menor de ellas, porque 5 lecturas no alcanzan para un percentil exacto. Se compara con la fila "FPS del cliente" de `load-budget.md`. Si pasa el tope hacia abajo: abrir issue con el modelo del teléfono y las 5 lecturas.
3. **Memoria.** Leer Memory al minuto 0, 5 y 10 de la sesión. Criterio: 3 lecturas escritas. Si crece entre lecturas de forma sostenida: anotarlo; es el síntoma de una fuga y va a un issue.
4. **Entrada en el teléfono.** Cronometrar una entrada como en el caso 1 paso 1. Criterio: un tiempo escrito. Si falla: anotar el fallo.

## Caso 3 Servidor lleno

1. **Llenar.** Los administradores entran al mismo servidor privado hasta el tope de jugadores por servidor del juego; ese tope se escribe en la hoja antes. Criterio: el lector del servidor cuenta los jugadores y coincide con el tope. Si no se llena: anotar cuántos eran; la prueba vale por esa cantidad, no por el tope.
2. **Jugar 5 minutos con normalidad.** Todos corren el loop. Criterio: nadie sale ni sufre un fallo visible. Si alguien es expulsado: anotar el mensaje y la hora.
3. **Latido.** El lector abre Developer Console, Server Jobs, Heartbeat. Criterio: lee los pasos por segundo cada minuto, 5 lecturas. Se compara con la fila "Latido del servidor". Si cae: seguir el paso 4 del procedimiento de [`performance.md`](../performance.md) (MicroProfiler) y adjuntar la captura de la etiqueta que sube.
4. **Red.** Leer `Stats.DataSendKbps` y `DataReceiveKbps` en el servidor con todos dentro. Criterio: ambos escritos, y se compara contra la fila "Red por jugador" multiplicada por el número de jugadores. Si pasa: anotar el remote o la propiedad replicada que más sube, si se sabe, o "sin identificar".
5. **Memoria del servidor.** Developer Console, Memory, al minuto 0 y 5. Criterio: 2 lecturas, comparadas con la fila "Memoria del servidor". Si no coincide con la fórmula: abrir issue.
6. **Reentrada con el servidor lleno.** Un administrador sale y reentra de inmediato. Criterio: el tiempo se anota como una entrada más del caso 1. Si hay espera larga: anotarla.

## Caso 4 Regresión en Studio

Se corre en la copia local de cada persona que cambió código desde la última prueba, no en el servidor privado.

1. **Abrir.** Test, Clients and Servers, 6 jugadores, Start. Criterio: una ventana de servidor y seis de cliente, sin errores rojos en Output. Si hay errores: corregirlos antes; las cifras no valen.
2. **Servidor.** Seguir los pasos 3 a 6 de la sección "Manual procedure in Studio" de [`performance.md`](../performance.md) con 6 clientes. Criterio: Heartbeat, peor frame, envío y recepción, y memoria escritos. Los topes del paso 5 y 6 de ese documento se calculan para 2 jugadores: con 6 hay que multiplicar por 6 los presupuestos por jugador, no copiar los números de 2.
3. **Anotar como regresión.** Estos números no sustituyen a los del caso 3: no hay latencia real y el equipo es el mismo. Criterio: el registro dice "Studio, 6 clientes" junto a cada valor.

## Si algo falla

- Una medición fuera del tope no se corrige en el momento: se registra, se abre un issue `tipo:bug` con los números y se sigue con el caso. Cambiar una constante sin medir primero puede robar sesiones (ADR 0032).
- Si un caso no se puede ejecutar (falta el teléfono, falta gente): se escribe `no ejecutado` y el motivo. Nunca se deja en blanco ni se pone un valor plausible.
- Si algo parece un problema de seguridad o de datos de jugadores (datos duplicados, compras raras): parar, no repetir y avisar a Victor.

## Registro

Cada caso deja una línea en la sección `## Evidencia` de [`qa-plan.md`](qa-plan.md), en la PR o el commit de quien cierra la prueba. Formato, con los campos entre `<>` por llenar el día de la prueba:

```
- <fecha>, versión <SemVer> (<SHA>), caso <1 a 4>, <resultado: dentro del tope | fuera del tope | no ejecutado>, medido: <valores con su unidad>, personas: <roles y nombres>, issue: <número o ninguno>
```

El coordinador también copia la tabla de tiempos del caso 1 y las lecturas de los casos 2 y 3 en esa PR. Si el resultado es "fuera del tope", la línea cita el issue que se abrió.

## Criterio de listo

- [ ] Los cuatro casos tienen su línea en `qa-plan.md`, ejecutados o `no ejecutado` con motivo.
- [ ] Cada valor medido lleva fecha, versión y persona.
- [ ] Cada resultado fuera del tope tiene su issue.
- [ ] La columna "Medido" de `load-budget.md` se actualizó con lo medido, o sigue en `TBD (#203)`.

## Evidencia

- [Presupuesto de carga y tiempo de entrada](load-budget.md)
- [Plan de QA](qa-plan.md)
- [Procedimiento manual de rendimiento](../performance.md)
- [ADR 0032: la entrada y la sonda](../adr/0032-join-architecture-data-as-background-state.md)
- [ADR 0019: presupuesto de rendimiento](../adr/0019-performance-budget.md)
- [Publicación en privado primero](README.md#publicación-privado-primero-público-solo-en-la-major-final)

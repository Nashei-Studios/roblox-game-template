# Configuración estándar de la experiencia

Así queda **todo juego de la fábrica**, sin excepción. Cada valor lleva su porqué. Si un juego necesita otra cosa, se dice en su ADR. La columna "Cómo" separa lo que se pone a mano en Studio o Creator Hub de lo que el agente aplica por la API de Open Cloud en la etapa de publicación (`roblox-publish`).

Antes de usar un campo de la API, se confirma en la documentación oficial (context7 `/roblox/creator-docs`), nunca de memoria. Ningún valor de clave se imprime: las claves van en las variables `ROBLOX_API_KEY` y `ASPHALT_API_KEY`.

## 0. Rojo y la place

1. Crea la place nueva en Studio y anota su `PlaceId`. Lo ves en el error de Rojo o en Game Settings.
2. Pon ese id en `servePlaceIds` de `default.project.json`. Así Rojo se niega a sincronizar en cualquier otra place, incluida la de otro juego.
3. Corre `rojo serve` desde el repo del juego. Si el puerto 34872 está ocupado por el Rojo de otro juego, cierra ese servidor o usa `--port 34873` y pon el mismo puerto en el plugin.

## 1. Información básica (Studio)

| Ajuste | Valor | Por qué | Cómo |
|---|---|---|---|
| Nombre | El elegido con `roblox-naming` | Etapa 2; veto de 24 h (decisión 0017) | Studio o API |
| Descripción | Una de las 3 versiones de la etapa 4 | Se escribe al final, con el juego terminado | API en la publicación |
| Creación en equipo | **Activado** | Guardado automático en la nube, que respalda la place | Studio |
| Modo Borradores | **Desactivado** | Rojo escribe los scripts directamente; con borradores, lo sincronizado no se publica sin confirmar cada script | Studio |

## 2. Comunicación (Studio)

| Ajuste | Valor | Por qué | Cómo |
|---|---|---|---|
| Chat de voz | **Activado** | Jugar con amigos suma sesiones de calidad; solo lo usan mayores de 13 con edad verificada | Studio o API |
| Cámara | **Activado** | No cuesta nada y suma expresión social | Studio |
| API de grupos de chat de texto y voz | **Desactivado** | El juego no la usa; menos superficie | Studio |

## 3. Seguridad (Studio)

| Ajuste | Valor | Por qué | Cómo |
|---|---|---|---|
| Acceso de Studio a los servicios API | **Activado** | Sin esto, los DataStores (ProfileStore) no funcionan en el playtest de Studio | Studio |
| Ventas de terceros | **Desactivado** | No vendemos objetos de otros creadores | Studio |
| Teletransporte de terceros | **Desactivado** | Solo se activa si el juego manda a otra experiencia; se decide en su ADR | Studio |
| API de malla e imagen (EditableMesh e EditableImage) | **Desactivado** | No se usa; se activa solo con ADR | Studio |
| Carga de activos de terceros | **Desactivado** | Solo cargamos assets propios, subidos con asphalt; bloquea assets que no son nuestros | Studio |

## 4. Configuración adicional (Creator Hub)

| Ajuste | Valor | Por qué | Cómo |
|---|---|---|---|
| Público > Acceso: dispositivos | Computador, teléfono, tableta y consola **activados**; VR **desactivado** | La mayoría juega en el teléfono; la UI se prueba en esos tamaños | API en la publicación |
| Público > Acceso: acceso de pago | **Desactivado** | Juego gratis; se gana con pases y productos | Creator Hub |
| Público > Acceso: servidores privados | **Activados y de pago** | Es una superficie de monetización (decisión 0024) | API en la publicación |
| Configurar > Cuestionario | **Completo**, buscando Minimal o Mild | Sin cuestionario completo no se llega a Kids (5 a 8) ni a Select (9 a 15) (decisión 0025, `research/gap-17-policies-and-age` del vault) | Creator Hub |
| Configurar > Ajustes: ícono | Propio, nunca el de defecto | Sin ícono ni miniatura propios no hay impresiones en Home (desde el 19 de octubre de 2026) | Etapa 3 |
| Configurar > Lugares: miniaturas y máximo de jugadores | Miniaturas propias de la etapa 3; máximo según el ADR del juego | Las miniaturas deciden el clic | Etapa 3 |
| Monetización > Productos y pases | Los de la configuración del juego; sin tope fijo (decisión 0024) | Se crean desde `Config`, nunca a mano | API en la publicación |
| Interacción > Emblemas | Uno de bienvenida, y luego por hito | Sirve de señal de progreso; revisar el costo vigente antes de crear | Creator Hub |
| Público > Localización | **Traducción automática activada** | Abre los mercados de habla hispana y portuguesa sin costo | Creator Hub |

## 5. Para llegar a menores de 16

Además del cuestionario hacen falta la verificación en 2 pasos, y Roblox Plus o Premium durante 2 meses, o una tarifa reembolsable de 1.000 R$ por juego. Después viene la evaluación de 250 jugadas únicas de jugadores muy activos (decisión 0025). Sin eso, el juego llega solo a mayores de 16.

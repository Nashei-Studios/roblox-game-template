# Mapa del ecosistema base: sistema, pieza externa, pegamento, issue

Política en [ADR 0028](adr/0028-external-building-blocks-and-wally.md): primero lo externo (servicio nativo de Roblox, librería abierta mantenida, plugin del Creator Store), después el pegamento que escribimos nosotros. Seguimiento general: #48.

Fecha de verificación: 2026-11-06. Los repos se midieron con `gh repo view` (licencia, último push); las APIs de Roblox se leyeron en `roblox/creator-docs` con context7. Lo que no se pudo leer ese día se marca como **no verificado**.

## Sistemas con pieza externa

| Sistema | Pieza externa | Licencia o fuente | Último push o página | Lo que escribimos (pegamento) | Issue |
|---|---|---|---|---|---|
| Persistencia | MadStudioRoblox/ProfileStore | Apache-2.0 | 2025-07-31 | Puerto `ProfileRepository` y shim de fachada | #34 (ya existe) |
| Remotos | red-blox/zap | MIT | 2026-06-23 | Esquema y validación | hecho (ADR 0015) |
| Limpieza y señales | Sleitnick/RbxUtil (`trove`, `signal`) vía Wally | MIT | 2026-08-11 | Ninguno; se adopta cuando un módulo lo pida | ADR 0028 |
| Notificaciones fuera del juego | `ExperienceNotificationService` y Open Cloud `POST /cloud/v2/users/{id}/notifications` | docs: production/promotion/experience-notifications | leído 2026-11-06 | Puerto, flag de opt-in, cola con tope diario, trabajador externo | #49 |
| Podio 3D con avatares | `Players:CreateHumanoidModelFromUserId` | docs: reference/engine/classes/Players | leído 2026-11-06 | `WorldBoard`: filas, podio, temporizador, texto de respaldo | #50 |
| Caché de tableros y rango | `MemoryStoreSortedMap` y `OrderedDataStore` | docs: cloud-services/memory-stores/sorted-map | leído 2026-11-06 | Puerto `BoardCache`, reconstrucción, ciclos | #51 |
| Invitar y unirse a un amigo | `SocialService:PromptGameInvite`, `Player:GetJoinData`, eventos de experiencia | docs: production/promotion/invite-prompts | leído 2026-11-06; `GetEventRsvpStatusAsync` no se encontró en la doc: **no verificado** | Puerto `Social`, recompensa idempotente | #52 |
| Eventos y LiveOps | Eventos nativos de la experiencia, `ConfigService`, `MessagingService` | docs: production/promotion/experience-events | leído 2026-11-06 | `EventBus`, calendario sobre `Flags`, insignia en HUD | #55 (primer corte hecho: `features/liveops`, ADR 0038, #86) |
| Experimentos A/B | `ConfigService:GetConfigForPlayerAsync` | docs: production/experiments | leído 2026-11-06 | Lectura por jugador en `Flags`, variante en analítica | #57 |
| Analítica de funnel | `AnalyticsService` | ADR 0023 | API de funnel **no verificada** hoy | Catálogo tipado de eventos | #58 |
| Soft shutdown | `BindToClose` y `TeleportService` con `ReservedServerId`; referencia: Quenty/NevermoreEngine `softshutdown` | docs; MIT | Nevermore 2026-11-06 | Módulo corto de aviso y teletransporte | #59 |
| Consola de admin y bans | evaera/Cmdr (vendorizado), `Players:BanAsync`, Open Cloud user restrictions | MIT; docs: players/index | Cmdr 2026-10-21, release v1.13.1 | Puerto `Moderation`, lista de permisos desde Config | #60 |
| Borrado por privacidad | Open Cloud DataStore delete | docs oficiales (nota del vault 2026-11-05) | **no verificado** hoy | Trabajador externo, lista de tiendas desde Config | #61 |
| Audio | `SoundService`, `SoundGroup`; pistas CC0 (Kenney) | nativo; CC0 | n/a | Reproductor sobre el módulo de sonido | #62 |
| Localización | `LocalizationService:GetTranslatorForPlayerAsync`; ayuda candidata: flshmodels/flash-locale | nativo; MIT | flash-locale 2026-11-02 (0 estrellas, sin revisar) | Acceso a texto con respaldo al idioma fuente | #64 |
| Menús extra (changelog, teleport, regalo) | Ninguna hoy; centau/vide cuando dos juegos dupliquen enlace de estado | MIT | 2026-10-26 | Menús sobre `UiKit` | #53 |

## Módulos portados desde +1 Mining Power (2026-11-07)

Maduraron en el juego y vuelven a la plantilla para que el siguiente los herede. Todos son Luau puro con README propio.

| Módulo | Qué resuelve | Pieza de plataforma | ADR | Issue |
|---|---|---|---|---|
| `features/social` | Friend boost, invitación con recompensa, multiplicador de perk configurable | `Player:IsFriendsWith`, `SocialService`, `GetJoinData`, MemoryStore | 0030, 0031 | #52 |
| `features/join` | Entrada sin espera: lecturas en paralelo, lote provisional, reintento de hello, política de cancelación | ProfileStore `Cancel` | 0032 | #47 |
| `features/joinprobe` | Medir la entrada antes de cambiar constantes | DataStore (opcional) | 0032 | #47 |
| `features/input` | "Toca en cualquier parte" con bloqueadores | `UserInputService` (adaptador por juego) | 0033 | #47 |
| `features/progress` | Títulos por contador, hito cada N unidades sin spam al entrar, conteo diario desde un contador de vida | `TextChatService` (`Announcer`, adaptador) | 0034 | #76 |
| `features/hitfx` | Efecto de golpe con un solo emisor reutilizado y tipos de golpe como datos | `ParticleEmitter` (presentador) | 0034 | #76 |
| `features/leaderboards` (`extraStats`) | Tablero diario de un contador del juego con una línea de config más una de tablero | `OrderedDataStore` (ya existente) | 0034 | #76 |
| `features/ui` (`CardGrid`) | Grilla de tarjetas (guardarropa, colección) detrás de una interfaz de presentador | `UIGridLayout` (presentador) | 0034 | #76 |

## Sistemas sin pieza externa

No existe pieza abierta mantenida ni servicio nativo que los resuelva. Se escriben nosotros; se anota el repo del que se leen patrones.

| Sistema | Qué se buscó (2026-11-06) | Patrones que se leen | Issue |
|---|---|---|---|
| Mascotas y huevos | Búsqueda en GitHub: solo repos de 0 estrellas, casi todos sin licencia | `roblox-gameplay-toolkit` (MIT, según el vault) | #24 (ya existe) |
| Ruleta | `marchware/Roblox-Spin-Wheel` no tiene licencia | Ninguno con licencia | #26 (ya existe) |
| Regalos entre jugadores | Sin módulo abierto | `MessagingService` nativo solo para avisar | #54 |
| Misiones | `FarFromLittle/Questline` (MIT, 9 estrellas, 2026-10-07), código no leído | Leerlo antes de tomar nada | #56 |
| Pase de temporada | Sin módulo abierto | Ninguno | #63 |
| Intercambio (trade) | Sin módulo abierto; riesgo de duplicado | Ninguno; diferido hasta que un juego lo pida | #65 |

## Issues relacionados que ya existen

- #34 shim de persistencia, #24 mascotas, #26 ruleta: cada uno recibió un comentario con la verificación externa.
- #47 ports desde +1 Mining Power: se pide contrastar cada arreglo con este mapa antes de portarlo.
- #45 ajustes estándar de experiencia: sin cambios.

## Piezas descartadas o solo de referencia

Descartadas por mantenimiento o por encaje: ByteNet, lapis, DataKeep, ZonePlus (sin push desde 2024), Fusion, react-lua, jecs, Janitor, roblox-lua-promise, ReplicaService, Knit. Solo referencia: TopbarPlus (licencia propia con atribución), Iris, GA-SDK-ROBLOX, lyra, Nevermore (acoplado). `CheeseGodRoblox/SoftShutdown` es GPL-3.0: no se copia. Detalle de las mediciones en la nota del vault `research/ecosistema-base-paridad-essentials`.

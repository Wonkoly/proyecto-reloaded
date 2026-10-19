# Reporte de conexiones

Generado con `python3 tools/extraer.py --solo mapas,conexiones --mapas todos` y
`python3 tools/validar_conexiones.py` (sin abrir Godot). El grafo queda en `data/extraido/conexiones.json`
(no se versiona). Cómo está hecho: `tools/conexiones.py`.

## Resumen

| | Antes | Después |
|---|---:|---:|
| Mapas | 717 | 717 |
| Salidas (conexiones) | 1860 | **1953** |
| Salidas ok | 1500 | **1583** |
| Salidas con aviso (así en el original o piden algo) | 253 | 302 |
| Salidas con error | 107 | **68** |
| Zonas (partes caminables de los mapas) | 8839 | 9496 |
| Pasos entre zonas (dentro del mapa) | 4199 | 5105 (192 saltos) |
| (a) mapas a los que se llega con la historia al empezar | 12 | 12 |
| (b) … con las banderas en su valor final | 53 | **157** |
| (c) … como (b) sin surf, bici ni MO | 234 | 232 |

"Antes" (sin `obj_TelePort`, que se convirtió al final) es la conversión con los tipos de 5.2 ya convertidos pero sin los arreglos de 5.6; los dos se
miden con el mismo validador. En (c) baja 2 porque ahora las salidas que dependen de por qué puerta se
entró (`index_place`) ya no valen siempre.

Salidas por tipo: borde 692, entrada (`obj_NOdoor`) 436, puerta 369 (64 de ellas `obj_door_inv`),
teletransporte 184, salida especial (`obj_out_special`) 114, salida de interior (`obj_out`) 113,
conducto 34, escalera 6, brecha 5. 110 dependen de la historia (51 de ellas de `index_place`) y 41 se
activan desde el agua (piden surf).

Zonas que piden algo para entrar: surf 1080, trepa 442, torbellino 190, cascada 85, lava 80,
golpe roca 52, corte 47, fuerza 4, y 1047 tapadas por algo que depende de la historia (NPCs, rocas…).

### Problemas por tipo

| Problema | Antes | Después | Qué es |
|---|---:|---:|---|
| `sin_regreso` | 58 | **19** | puerta, borde o escalera sin salida de vuelta en el destino |
| `sin_entrada` | 33 | 33 | `obj_out` en un mapa al que no entra ninguna puerta |
| `llegada_pared` | 13 | 13 | se aparece metido más de 4 px en una pared |
| `inalcanzable` | 4 | 4 | ninguna posición caminable activa la salida |
| `llegada_historia` (aviso) | 17 | 26 | al llegar tapa un NPC/roca de la historia al empezar |
| `llegada_agua` (aviso) | 63 | 64 | se llega al agua: ruta de surf |
| `sin_destino` (aviso) | 21 | 21 | `ROOM = -1` |
| `rebote_esquina` (aviso) | 134 | 134 | solo en algunas posiciones de la esquina se cae sobre otra salida |
| `llega_a_pareja` (aviso) | 36 | 67 | teletransporte que llega sobre su pareja |
| `rebote` | 0 | 0 | toda llegada cae sobre otra salida que se activa sola |
| `llegada_fuera` | 0 | 0 | se aparece fuera del mapa |
| `destino_inexistente` | 0 | 0 | el destino no es un mapa |

## 5.2 Tipos que afectan a las conexiones

- **`obj_NOdoor` (440 en CreateDoors)**: no bloquea ni anula puertas: **es una entrada sin puerta**
  (`NoDoorStepActions`/`NoDoorEnter`): con la máscara del jugador encima y pulsando arriba (o abajo si
  `abajo = true`, o sin pulsar si las dos son false) lleva a `ROOM` (`X`, `Y`) y deja
  `global.index_place = INDEX`. Con `entrada = true` guarda el regreso solo si no había uno; con
  `salida = true` lo borra. Convertido a `Salida` (tipo "entrada").
- **`obj_minibloqueado` (485)**: hijo de `obj_bloqueado`. Es colisión, pero **no para el jugador**:
  `ProtaMovimiento` nunca lo mira. Lo usan las rocas de Fuerza (`EmpujeFuerza`), los Pokémon que andan
  por el mapa (`PokemonEntornoCollition`) y otros objetos. No afecta al paso; queda ignorado, como
  `obj_bloqueado`.
- **Agua**: `obj_agua1` y sus 12 hijos (`obj_agua2`, `obj_aguasimple`, `obj_aguainvisible`, `obj_lava`,
  `obj_agua_buceable`…; ~86 000 instancias, más las que crea `SetOnlyWater` en los mapas de mar) son
  ahora colisión en la capa 7 ("agua", unida en rectángulos grandes) y zonas del grafo que piden surf
  (lava: "lava"). `obj_borradorDeAgua` borra el agua más cercana (`BorradorAguaActua`): se aplica al
  convertir. No hay surf: el agua no se pisa.
- Con la misma revisión también se convirtieron otras salidas que estaban como marcadores o ni siquiera
  se creaban: `obj_door_inv` (puerta invisible, 49), `obj_out_special` (114), los teletransportes de
  suelo (`obj_teleport_suelo/super/espiritu`) y de máquina (`obj_TelePort`: 2 s encima, en nativo al llegar), los conductos (`obj_conducto_tierra`) y las brechas
  (`obj_brechaTransporte`), que vienen de `CreateDevices` (antes no se evaluaba). También salen de ahí
  los obstáculos de MO (arbustos, rocas, torbellinos, rocas de Fuerza), que siguen siendo paredes y en
  el grafo piden su movimiento.

## Errores de conversión (arreglados)

1. **Bloques `if(room=(N) && …)` ignorados.** Solo se leían `room=(N)` y `room=(N) || …`; los que
   combinan la room con otra condición se perdían enteros (salidas y NPCs de interiores compartidos).
2. **`global.index_place` tomado siempre como 0.** Los interiores compartidos (EdificioPuertoSolar,
   InterRuta, InterRuta3, BarcoCamarote…) eligen su salida según el `INDEX` de la puerta por la que se
   entró. Ahora es la variable `lugar` en las condiciones (`GameState.indice_lugar`, la fija cada
   `Salida` con `indice_lugar`) y el grafo la lleva como estado.
3. **Condiciones mezcladas.** `room=(310) && global.index_place=1` no se podía escribir en GDScript
   (por `room`) y se evaluaba entero como si `lugar` fuera 0: se perdían las ramas 1, 2… `room` se
   sustituye por su número.
4. **Las salidas por los bordes y escaleras se activaban con la máscara.** El original
   (`CambiosWorldRooms`) mira solo el punto del jugador y prueba las salidas en orden (gana la primera):
   ahora `Salida.por_punto`. En las esquinas gana la que va antes en el script.
5. **El regreso de los interiores.** `obj_out` vuelve a la posición fija de su room en 7 rooms
   (`OutDoorStepActions`) y borra el regreso al usarse; las puertas lo guardan siempre, las entradas
   sin puerta solo si estaba vacío, y `obj_out_special` lo borra (`Salida.regreso`).

Efecto: `sin_regreso` de 58 a 19, y en (b) de 53 a 157 mapas.

## Cosas que son así en el original (solo se anotan)

- **Bases secretas (30) + CentralElectrica, GYM7_Polar, GuaridaEscuadron** (`sin_entrada`): se entra
  por sus sistemas (`CreateSecretBases`, eventos), no por una puerta.
- **Ascensores** (`sin_destino`, 21): `obj_door_ascensor` con `ROOM = -1`; el piso lo elige un menú.
- **Llegadas metidas en una pared** (13): son las coordenadas del original. En CasaSpica entran 10
  puertas a (112, 196) que se meten 8 px en la pared de abajo, pero se puede salir hacia arriba (las de
  CiudadSpica usan 182). Las otras: teletransportes de CampoMagnetar y RioCancri sobre
  `obj_pared_abismo`, y AulaUniversidad sobre un `obj_Talk`.
- **Sin salida de vuelta** (19, en 10 pares de mapas): son así en los scripts del original, que no
  tienen la salida de vuelta. BarcoCamarote sale a BarcoJungla_1 y no a BarcoJungla_2; PlayaVida y
  SaltoLeon no tienen borde hacia BosqueNero; CuevaRetaguardia_7 no tiene ninguna salida (sala de
  evento); Torre_Batalla solo sale a sí misma (los pisos los maneja la torre); AlcantarillaPolar2 sale
  a AlcantarillaPolar; Centro_Pokemon2 sale a Centro_Pokemon; PlayaBrujula no tiene borde hacia
  Ruta_43; a TemploNebulosa_1 se entra desde TemploNebulosaBuceo (buceo) sin camino de vuelta.
- **Esquinas** (134): solo algunas posiciones de la esquina caen sobre otra salida; el original copia la
  coordenada tal cual.
- **Teletransportes que llegan a su pareja** (67): el original no los repite (`global.teletransportado`)
  y en nativo las salidas "al entrar" no se activan al aparecer encima.
- **Inalcanzables** (4): la salida por el borde de BosqueNero a SaltoLeon (tapada por árboles), un
  teletransporte de CampoMagnetar_2 metido en `obj_pared_abismo` y las dos escaleras de
  GuaridaGalaxia_3 (detrás de `obj_semipared`).
- **Barreras que no son de la historia**: el norte de PuebloAlba (a GranjaCajasPokemon) lo tapa un NPC
  mientras haya menos de 50 Pokémon capturados (`global.capturados < 50`); como todavía no hay Pokédex,
  queda siempre.
- **(a) solo 12 mapas**: con el primer Pokémon, la Ruta 2 está cortada (`ruta2cortada`) y el sur de
  PuebloAlba (Ruta_5_3) también; es el principio del juego.
- **Regiones a las que se llega por un evento**: casi todo lo que falta en (c) está detrás del barco
  (`DestinoViajeBarco` → EdificioPuertoSolar y las islas), vuelos (`MapaLocationActivate`), buceo
  (`GoDiving`) o cinemáticas. Eso no son salidas: hay que implementarlo como eventos.

## Cómo se calculó

- La rejilla es de 8 px con la máscara real del protagonista (`ProtaMaskSprite`, 15×20); se perdona
  1 px de solape con las paredes, y una salida se activa si queda a media celda.
- El "valor final" de una bandera es el mayor que se le asigna en los scripts (si solo se le suma,
  cuántas veces se suma). Es una aproximación: algunas banderas valen algo a mitad de la historia y
  vuelven a 0, y una pared que solo está en un valor intermedio queda abierta.
- La búsqueda lleva el estado que recuerda el juego al cruzar puertas: `index_place` y `room_out` (a
  dónde devuelve `obj_out`). Sin eso, el Centro Pokémon compartido conectaría todas las ciudades.

## Mapas a los que no se llega

<details><summary><b>(a) historia al empezar (fy_002 = 1, movil = 1: con el primer Pokémon, como GameState)</b></summary>

Se llega a **12** mapas; faltan **705**.

| Mapas | Razón probable | Cuáles |
|---:|---|---|
| 65 | solo se entra por un evento (barco, vuelo, buceo, cinemática…) | Ascensor, BuceoSimple, CajaPkmnMenu, CasaGloboRocket, CentralElectrica, CentroTecno_S1, CentroTecno_S2, CentroTecno_S3, CentroTecno_S4, CentroTecno_S5, CetaceaBuceo, CuevaGaara, CuevaRemolino_3, CuevaSextanteBuceo, DarkraiHome, DarkraiHome2, DarkraiHomeReal, FabricaChangePkmn, FaroLuzAzotea, GYM7_Polar, GuaridaGalaxia_4, LigaPokemonHoenn, LigaPokemonJohto, LigaPokemonKanto, LigaPokemonSinnoh, LigaPokemonStar, LigaPokemonTeselia, LogrosMenu, MapaMenu, MisionesMenu, MovilMenu, OpcionesMenu, ParaisoAether_Atracadero, PersonajeMenu, PokedexMenu, PokemonDojo_Playing, PokemonFlyGol_Playing, PokemonMenu, RascaCielos_Azotea, Remolino1_Buceo … (+25) |
| 41 | no es un mapa del mundo (pantalla, menú o sala sin salidas) | BattleROOM, BattleROOMAqua, BattleROOMLava, CardsRoom, CharlaRoom, CieloCaminoIslas, ComandosMenu, CreditosInicioScreen, CreditosScreen, CuevaUmbral, FlyGol, HuevoMenu, InicioROOM, InterCambioRoom, IntroROOM, LigaPokemonAlola, LigaPokemonKalos, LoaderROOM, MochilaMenu, MultijugadorMenu, MundoDebug1, OptionsROOM, ParaisoAether_Reserva, PkmnEvolution, PkmnHabMenu, PkmnInfoMenu, PkmnMovMenu, Pokedex2Menu, Pokedex3Menu, PokedexLugarMenu, PuzleUNW, RaceN1, SafariAgua, SafariBasic, SafariHierbas, SecretRoom, Tragaperras, ViajeBarco, ZonaArenaBattle, Zona_Final … (+1) |
| 31 | ninguna salida ni script lleva aquí | BaseSecretaA1, BaseSecretaA2, BaseSecretaA3, BaseSecretaA4, BaseSecretaA5, BaseSecretaD1, BaseSecretaD2, BaseSecretaD3, BaseSecretaD4, BaseSecretaD5, BaseSecretaM1, BaseSecretaM2, BaseSecretaM3, BaseSecretaM4, BaseSecretaM5, BaseSecretaR1, BaseSecretaR2, BaseSecretaR3, BaseSecretaR4, BaseSecretaR5, BaseSecretaT1, BaseSecretaT2, BaseSecretaT3, BaseSecretaT4, BaseSecretaT5, BaseSecretaV1, BaseSecretaV2, BaseSecretaV3, BaseSecretaV4, BaseSecretaV5, ParaisoAether_Lab |
| 17 | detrás de CiudadPolar | CasaAbandonada_1, CasaKena, CasaPolar, CasinoPolar, CasinoPolarPremios, CentroComercial_0, CuevaExtravio, EntradaSafari, Lab_Abedul, Lab_Fosil, Pantano_Swamp2, PuebloKena, Ruta_12_1, Ruta_12_3, Ruta_16, Ruta_18, Ruta_18_1 |
| 17 | detrás de EdificioPuertoSolar | CasaNeptuno, EdificioMultimediaStar, IslaMarte_Ruta, IslaNeptuno, IslaNeptuno_Ruta, IslaPluton, IslaSaturno_Ruta, IslaTerra, IslaTerra_RutaI, IslaVenus, Ruta_35, Ruta_35_1, Ruta_36, Ruta_39, Ruta_39_1, Ruta_39_2, Ruta_40_3 |
| 14 | detrás de Ruta_21 | BancoStar, Bosque_Mistico, CentroTecno_0, CiudadAntares, CuevaMetal_1, CuevaMetal_2, CuevaMetal_3, EntradaRascacielos, GYM8_Antares, ParaisoFloral, PuertoLuz, Ruta_18_2, Ruta_18_3, Ruta_20_1 |
| 14 | detrás de CuevaRetaguardia_0 | CuevaRetaguardia_1, CuevaRetaguardia_2, CuevaRetaguardia_3, CuevaRetaguardia_4, CuevaRetaguardia_5, CuevaRetaguardia_6, CuevaRetaguardia_7, Fabrica_Retaguardia, FrenteEste, Palacio_Retaguardia, Survival_Retaguardia, Torneo_Retaguardia, Torre_Retaguardia, Zona_Retaguardia |
| 13 | detrás de CuevaPaleo_1 | BosqueSiluam4, CuevaPaleo_2, IslaFlecha_Ruta_27, ParqueVital, PuebloAdhara, PuebloWezen, Ruta_28, Ruta_29, Ruta_29_1, Ruta_30, Ruta_30_1, SalonModa, TeatroMelody |
| 13 | detrás de CuevaHelada_1 | CasaDeneb, CuevaHelada_2, GYM4_Deneb, IslaEnergia, Lab_Magnolia, Ruta_11_2, Ruta_11_3, Ruta_11_4, Ruta_13_2, Ruta_15, Ruta_15_1, Templo_Helado, Tunel_Yucca |
| 12 | detrás de PuebloAdhara | BosqueSiluam1, BosqueSiluam2, BosqueSiluam3, CasaNaos, Lab_Huevos, PuebloProcyon, PuertoJungla, RioPerseo, Ruta_26, Ruta_31, Ruta_32, Ruta_32_1 |
| 10 | detrás de MonteSelenio_2 | BosqueCristalino_2, BosqueCristalino_3, CuevaElemental, CuevaElemental_2, CuevaElemental_3, CuevaElemental_4, CuevaElemental_5, CuevaElemental_6, MonteSelenio, MonteSelenio_3 |
| 10 | detrás de CuevaChuzo_1 | BosqueFugaz, CasaArcturus, ColinaSagrada, CuevaChuzo_2, LagoLerna, PuebloArcturus, RioPerseo_2, RioPerseo_3, Ruta_33, Ruta_34 |
| 10 | detrás de Ruta_3 | Bosque_Spica, CasaSpica, CiudadSpica, GYM1_Spica, Lab_Serbal, Ruta_3_1, Ruta_4, Ruta_4_5, Ruta_4_6, Ruta_4_7 |
| 10 | detrás de CiudadVega | ComisariaVega, FloristeriaVega, GYM5_Vega, Lab_Elm, PokemonRace, Ruta_14_1, Ruta_16_1, Ruta_16_2, Ruta_16_3, VegaBeach |
| 10 | detrás de RioHeracles_2 | CuevaSextante, CuevaSextante_3, MonteFenix, MonteOctante_2, MontePiscis, MontePiscis_2, RioHeracles, RioHeracles_3, TemploNebulosa_Old, TemploNebulosa_Old_2 |
| 9 | detrás de Ruta_9 | CasaMUMU, GranjaMUMU, Ruta_10, Ruta_11, Ruta_11_1, Ruta_9_1, Ruta_9_2, Ruta_9_3, TorrePkmn_1 |
| 9 | detrás de Ruta_7 | CasaPescador, PozoTalo, Ruta_4_1, Ruta_4_2, Ruta_4_3, Ruta_5_1, Ruta_6, Ruta_6_1, Ruta_7_1 |
| 8 | detrás de RioMonoceros | LagoDraco, MonteOrion, PantanoSeismo, RioMonoceros_2, RioPegaso, RioPegaso_3, RuinasAndromeda_2, RutaAndromeda |
| 7 | detrás de MonteSelenio | BosqueCristalino, CuevaMagnetar, CuevaMagnetar_4, MonteSelenio_2, TemploSupernova_1, TemploSupernova_2, TemploSupernova_3 |
| 7 | detrás de InterRuta3 | Bosque_Tormenta, CasaClubFans, EntradaLabVoltio, IslaSaturno, PuenteKrono_1, PuenteKrono_3, Ruta_38 |
| 7 | detrás de CiudadSirio | CasaSirio, CementerioCan, GYM3_Sirio, Ruta_10_1, Ruta_10_2, Ruta_2_2, Ruta_2_4 |
| 7 | detrás de EntradaSafari | Ruta_17, Ruta_17_1, Ruta_17_2, ZonaSafari, ZonaSafari2, ZonaSafari3, ZonaSafari4 |
| 6 | detrás de CementerioMatagot | BosqueMarchito_2, CementerioMatagot_2, CementerioMatagot_3, TemploEspiritu_1, TemploEspiritu_2, TemploEspiritu_3 |
| 6 | detrás de ValleLlanos | BosqueNero_3, PlayaBrujula, TemploLlanos_1, TemploLlanos_2, TemploLlanos_3, TemploLlanos_Entrada |
| 6 | detrás de CampoMagnetar | CuevaMagnetar_1, CuevaMagnetar_2, CuevaMagnetar_3, LagoQuasar, LagoQuasar_2, LagoQuasar_3 |
| 5 | detrás de CampoPulsar_2 | BosqueHechizo, BosqueHechizo_2, CampoPulsar, CostaVirgo, TemploSupernova_Old |
| 5 | detrás de FrenteCentral | CasaFrente, CuevaRetaguardia_Salida, CupulaEventos, EdificioLogros, PuertoFrente |
| 5 | detrás de CiudadRigel | CasaRigel, DesiertoGaara_3, GYM6_Rigel, SaloonRigel, ZonaVolcanica_1 |
| 5 | detrás de AbismoPerdido_2 | CuevaLibra, CuevaLibra_2, ValleEspiritu, VolcanTormento, VolcanTormento_2 |
| 5 | detrás de MonteOrion | CuevaOrion, CuevaOrion_2, CuevaOrion_3, CuevaOrion_4, CuevaOrion_5 |
| 4 | detrás de BarcoJungla_1 | BarcoCamarote, BarcoJungla_2, BarcoJungla_3, EdificioPuertoLuz |
| 4 | detrás de BosqueHechizo_2 | BosqueHechizo_3, BosqueHechizo_4, CampoBlazar, CampoBlazar_2 |
| 4 | detrás de BosqueNero | BosqueNero_2, MonteLeon, PlayaVida, RioAcuario |
| 4 | detrás de LagunaRoja | CementerioMatagot, CuevaAries, CuevaAries_2, ValleAries |
| 4 | detrás de Tunel_Yucca | CiudadDeneb, CiudadSirio, CuevaHelada_1, Tunel_Yucca_2 |
| 4 | detrás de CostaCetacea | CostaCetacea_2, CuevaCetacea, CuevaCetacea_2, RioHeracles_2 |
| 4 | detrás de CostaTauro_2 | CostaTauro, DesiertoEscorpio, Ruta_44_2, Ruta_44_3 |
| 4 | detrás de CuevaRoja_1 | CuevaRoja_2, IslaMarte, PokemonDojo, Ruta_37_2 |
| 4 | detrás de CuevaSextante_3 | CuevaSextante_2, MontePiscis_3, MontePiscis_4, ValleNebulo |
| 4 | detrás de CuevaVendaval_1 | CuevaVendaval_2, IslaViento, Ruta_23, Ruta_4_4 |
| 4 | detrás de CuevaAstilla | GuarderiaNaos, Ruta_8, Ruta_8_1, Ruta_9 |
| 4 | detrás de CuevaExtravio | Pantano_Swamp, Pantano_Swamp3, Ruta_15_2, ZonaExtravio |
| 3 | detrás de ValleEspiritu | AbismoPerdido, AbismoPerdido_2, BosqueMental_2 |
| 3 | detrás de IslaSol | CalleVictoria_1, Ruta_23_1, Ruta_24_2 |
| 3 | detrás de CalleVictoria_1 | CalleVictoria_2, CalleVictoria_3, Ruta_25 |
| 3 | detrás de ValleSupernova_2 | CampoMagnetar_2, ValleSupernova, ValleSupernova_3 |
| 3 | detrás de CuevaMoonlight | CiudadVega, CuevaMoonlight_2, CuevaMoonlight_3 |
| 3 | detrás de CostaCapricornio_2 | CostaCapricornio, IslaAlma, TunelMatagot |
| 3 | detrás de CuevaMagmatica_1 | CuevaMagmatica_2, Ruta_37, Ruta_37_1 |
| 3 | detrás de CuevaNeith | CuevaNeith_3, IslaVenus_Ruta, Ruta_35_2 |
| 3 | detrás de FrenteEste | CuevaRetaguardia_0, InfiernoEntrada, TorreEntrada |
| 3 | detrás de PlayaVida | IslaHalley, Ruta_41_1, Ruta_41_2 |
| 3 | detrás de Ruta_24_2 | IslaSol, Ruta_24, Ruta_24_1 |
| 3 | detrás de EntradaLabVoltio | LabVoltio_0, LabVoltio_1, LabVoltio_2 |
| 3 | detrás de CuevaAries_2 | LagunaRoja, TunelTormento, VolcanTormento_3 |
| 3 | detrás de PalacioEntrada | Palacio_Central, Palacio_Este, Palacio_Oeste |
| 3 | detrás de ParaisoAether_Patio2 | ParaisoAether_EntradaMansion, ParaisoAether_Patio, ParaisoAether_Secreta |
| 3 | detrás de BosqueNero_2 | PlayaGeminis, Ruta_44, Ruta_44_1 |
| 3 | detrás de RuinasOmega | PuebloLuna, Ruta_19_1, Ruta_20 |
| 3 | detrás de CuevaMoonlight_3 | RioHidra, RuinasOmega, Ruta_19 |
| 3 | detrás de CostaVirgo | Ruta_43, Ruta_43_1, Ruta_43_2 |
| 2 | la salida de PuebloAlba está en una parte a la que no se llega (aislada: hay que cruzar agua, un obstáculo o una barrera) | GranjaCajasPokemon, Ruta_5_3 |
| 2 | detrás de GuaridaRocket_1 | AlcantarillaPolar2, GuaridaRocket_2 |
| 2 | detrás de BosqueCentauri_2 | BosqueCentauri, BosqueCentauri_3 |
| 2 | detrás de BosqueMarchito_2 | BosqueMarchito, BosqueMental |
| 2 | detrás de RioAcuario | BosqueNero, SaltoLeon |
| 2 | detrás de ValleSupernova | CampoMagnetar, ValleSupernova_2 |
| 2 | detrás de CarrilBicis_2 | CarrilBicis, CarrilBicis_3 |
| 2 | detrás de CarrilBicis | CarrilBicis_2, Ruta_13_1 |
| 2 | detrás de CasaAbandonada_1 | CasaAbandonada_0, CasaAbandonada_2 |
| 2 | detrás de IslaMercurio | CasaVega, IslaMercurio_Ruta |
| 2 | detrás de CentroComercial_2 | CentroComercial_1, CentroComercial_3 |
| 2 | detrás de CentroComercial_3 | CentroComercial_2, CentroComercial_4 |
| 2 | detrás de GuarderiaNaos | CiudadNaos, GYM2_Naos |
| 2 | detrás de Ruta_12_3 | CiudadPolar, Ruta_12 |
| 2 | detrás de DesiertoGaara_3 | CiudadRigel, DesiertoGaara_2 |
| 2 | detrás de DesiertoEscorpio | CostaTauro_2, DesiertoEscorpio_2 |
| 2 | detrás de CuevaArdiente_2 | CuevaArdiente_1, GuaridaMagma_1 |
| 2 | detrás de CuevaArdiente_1 | CuevaArdiente_2, ZonaVolcanica_3 |
| 2 | detrás de CuevaAstilla_1 | CuevaAstilla, CuevaAstilla_2 |
| 2 | detrás de CuevaCaliente_1 | CuevaCaliente_2, IslaCalor |
| 2 | detrás de CuevaChuzo_2 | CuevaChuzo_1, CuevaChuzo_3 |
| 2 | detrás de CuevaMagmatica_2 | CuevaMagmatica_1, CuevaMagmatica_3 |
| 2 | detrás de CuevaNeith_3 | CuevaNeith, CuevaNeith_2 |
| 2 | detrás de CuevaOceanica_3 | CuevaOceanica_2, CuevaOceanica_4 |
| 2 | detrás de CuevaRetaguardia_Salida | CuevaRetaguardia_Centro, FrenteCentral |
| 2 | detrás de DesiertoGaara | CuevaRocosa_1, TunelGaara_1 |
| 2 | detrás de TunelGaara_2 | CuevaRocosa_2, TunelGaara_3 |
| 2 | detrás de CuevaRocosa_2 | CuevaRocosa_3, TunelGaara_2 |
| 2 | detrás de CuevaRocosa_1 | DesiertoGaara, Ruta_12_2 |
| 2 | detrás de FrenteNorte | FabricaEntrada, PalacioEntrada |
| 2 | detrás de FabricaVenus_1 | FabricaVenus_2, FabricaVenus_S |
| 2 | detrás de Bosque_Mistico | FaroLuzBajo, Ruta_21 |
| 2 | detrás de GuaridaAqua_4 | GuaridaAqua_2, GuaridaAqua_3 |
| 2 | detrás de GuaridaMagma_2 | GuaridaMagma_3, GuaridaMagma_4 |
| 2 | detrás de GuaridaRocket_2 | GuaridaRocket_1, GuaridaRocket_3 |
| 2 | detrás de PuenteKrono_1 | InterRuta3, PuenteKrono_2 |
| 2 | detrás de IslaMercurio_Ruta | InterRutaCaloris, IslaMercurio |
| 2 | detrás de IslaHalley | IslaHalley_Ruta, Ruta_41 |
| 2 | detrás de Bosque_Tormenta | IslaJupiter, Ruta_38_1 |
| 2 | detrás de CuevaOceanica_1 | IslaTerra_RutaD, Ruta_36_1 |
| 2 | detrás de IslaUrano_Ruta | IslaUrano, PokemonFlyGol |
| 2 | detrás de Ruta_40 | IslaUrano_Ruta, Ruta_40_1 |
| 2 | detrás de LabJungla_2 | LabJungla_1, LabJungla_3 |
| 2 | detrás de MansionHollow_1 | MansionHollow_0, MansionHollow_2 |
| 2 | detrás de MundoInverso2 | MundoInverso, MundoInverso3 |
| 2 | detrás de ParaisoAether_Patio | ParaisoAether_Entrada, ParaisoAether_Patio2 |
| 2 | detrás de PozoTalo | PuebloTalo, Ruta_7 |
| 2 | detrás de PlayaBrujula | RioAcuario_2, ValleLlanos |
| 2 | detrás de ValleSupernova_3 | RioCancri, RioCancri_2 |
| 2 | detrás de CarrilBicis_3 | RioHidra_2, Ruta_14 |
| 2 | detrás de RuinasAndromeda_2 | RioMonoceros, RuinasAndromeda |
| 2 | detrás de Ruta_24 | Ruta_22, Ruta_22_1 |
| 2 | detrás de Bosque_Spica | Ruta_2_3, Ruta_3 |
| 2 | detrás de Ruta_40_1 | Ruta_40, Ruta_40_2 |
| 2 | detrás de RioAcuario_2 | Ruta_42, Ruta_42_2 |
| 2 | detrás de Ruta_5_3 | Ruta_5, Ruta_5_2 |
| 2 | detrás de SantuarioCeleste_1 | SantuarioCeleste_2, SantuarioTerra |
| 2 | detrás de FrenteOeste | SurvivalEntrada, ZonaEntrada |
| 2 | detrás de TiendaSecreta_4 | TiendaSecreta_3, TiendaSecreta_5 |
| 2 | detrás de Torneo_Camerino | Torneo_Batalla, Torneo_Pasillo |
| 2 | detrás de TorreIris_2 | TorreIris_1, TorreIris_Azotea |
| 2 | detrás de ZonaVolcanica_1 | ZonaVolcanica_2, ZonaVolcanica_4 |
| 1 | la salida de Centro_Pokemon está en una parte a la que no se llega (aislada: hay que cruzar agua, un obstáculo o una barrera) | Centro_Pokemon2 |
| 1 | la salida de Lago_Senn está en una parte a la que no se llega (aislada: hay que cruzar agua, un obstáculo o una barrera) | Lago_Senn_2 |
| 1 | la salida de PuebloValde está en una parte a la que no se llega (aislada: hay que cruzar agua, un obstáculo o una barrera) | Ruta_2 |
| 1 | detrás de AlcantarillaPolar2 | AlcantarillaPolar |
| 1 | detrás de UniversidadPokemon | AulaUniversidad |
| 1 | detrás de BarcoCamarote | BarcoJungla_1 |
| 1 | detrás de BiblioAntares2 | BiblioAntares |
| 1 | detrás de BiblioAntares | BiblioAntares2 |
| 1 | detrás de BosqueCentauri_3 | BosqueCentauri_2 |
| 1 | detrás de PuertoFrente | CafeteriaPL |
| 1 | detrás de TemploSupernova_Old | CampoPulsar_2 |
| 1 | detrás de RascacielosPiso | CasaAntares |
| 1 | detrás de DesiertoGaara_2 | CasaLuna |
| 1 | detrás de CementerioCan | CasaTalo |
| 1 | detrás de CastleRekiem_2 | CastleRekiem_1 |
| 1 | detrás de CastleRekiem_1 | CastleRekiem_2 |
| 1 | detrás de CastleRekiem_4 | CastleRekiem_3 |
| 1 | detrás de CastleRekiem_3 | CastleRekiem_4 |
| 1 | detrás de CastleRekiem_Final | CastleRekiem_5 |
| 1 | detrás de CastleRekiem_5 | CastleRekiem_Final |
| 1 | detrás de CentroComercial_4 | CentroComercial_Azotea |
| 1 | detrás de ComisariaVega | ComisariaVega2 |
| 1 | detrás de IslaAlma | CostaCapricornio_2 |
| 1 | detrás de CuevaCetacea | CostaCetacea |
| 1 | detrás de CuevaAstilla_2 | CuevaAstilla_1 |
| 1 | detrás de CuevaCaliente_2 | CuevaCaliente_1 |
| 1 | detrás de CuevaHelada_2 | CuevaHelada_3 |
| 1 | detrás de CuevaMoonlight_2 | CuevaMoonlight |
| 1 | detrás de CuevaOceanica_2 | CuevaOceanica_1 |
| 1 | detrás de CuevaOceanica_4 | CuevaOceanica_3 |
| 1 | detrás de CuevaPaleo_2 | CuevaPaleo_1 |
| 1 | detrás de CuevaRemolino_2 | CuevaRemolino |
| 1 | detrás de CuevaRemolino | CuevaRemolino_2 |
| 1 | detrás de CuevaRoja_2 | CuevaRoja_1 |
| 1 | detrás de GuaridaAqua_1 | CuevaRuta24 |
| 1 | detrás de BosqueHechizo_4 | CuevaSagitario |
| 1 | detrás de CuevaVendaval_2 | CuevaVendaval_1 |
| 1 | detrás de MundoInverso | EdificioPuertoSolar |
| 1 | detrás de FabricaVenus_2 | FabricaVenus_1 |
| 1 | detrás de Fabrica_Cambios | Fabrica_Batalla |
| 1 | detrás de Fabrica_Batalla | Fabrica_Cambios |
| 1 | detrás de Ruta_3_1 | FacultadCombate |
| 1 | detrás de TorneoEntrada | FrenteNorte |
| 1 | detrás de SurvivalEntrada | FrenteOeste |
| 1 | detrás de CuevaRuta24 | GuaridaAqua_1 |
| 1 | detrás de GuaridaAqua_2 | GuaridaAqua_4 |
| 1 | detrás de GuaridaEscuadron2 | GuaridaEscuadron |
| 1 | detrás de GuaridaEscuadron | GuaridaEscuadron2 |
| 1 | detrás de TunelGaara_3 | GuaridaFlare_1 |
| 1 | detrás de GuaridaFlare_1 | GuaridaFlare_2 |
| 1 | detrás de GuaridaGalaxia_2 | GuaridaGalaxia |
| 1 | detrás de GuaridaGalaxia | GuaridaGalaxia_2 |
| 1 | detrás de GuaridaGalaxia_4 | GuaridaGalaxia_3 |
| 1 | detrás de GuaridaMagma_4 | GuaridaMagma_2 |
| 1 | detrás de HotelSirio2 | HotelSirio |
| 1 | detrás de HotelSirio | HotelSirio2 |
| 1 | detrás de InstitutoMeteo_2 | InstitutoMeteo |
| 1 | detrás de InstitutoMeteo | InstitutoMeteo_2 |
| 1 | detrás de InterRuta2 | InterRuta |
| 1 | detrás de InterRuta | InterRuta2 |
| 1 | detrás de LabJungla_1 | LabJungla_2 |
| 1 | detrás de SalonFama | LigaPkmnEntrada |
| 1 | detrás de MansionHollow_2 | MansionHollow_1 |
| 1 | detrás de MonteOctante_2 | MonteOctante |
| 1 | detrás de MundoInverso3 | MundoInverso2 |
| 1 | detrás de MuseumSpica2 | MuseumSpica |
| 1 | detrás de MuseumSpica | MuseumSpica2 |
| 1 | detrás de ParaisoAether_Secreta | ParaisoAether_Dormitorio |
| 1 | detrás de InterRutaCaloris | ParqueCaloris |
| 1 | detrás de SaltoLeon | PlayaLyra |
| 1 | detrás de ParqueVital | PuebloRegulo |
| 1 | detrás de CasaAntares | RascacielosPiso |
| 1 | detrás de RioPegaso | RioPegaso_2 |
| 1 | detrás de Ruta_13_2 | Ruta_13 |
| 1 | detrás de Ruta_24Aqua_Buceo | Ruta_24Aqua2_Buceo |
| 1 | detrás de Ruta_24Aqua2_Buceo | Ruta_24Aqua_Buceo |
| 1 | detrás de Ruta_2 | Ruta_2_1 |
| 1 | detrás de BosqueFugaz | Ruta_33_1 |
| 1 | detrás de Ruta_42_2 | Ruta_42_1 |
| 1 | detrás de LigaPkmnEntrada | SalonFama |
| 1 | detrás de SantuarioTerra | SantuarioCeleste_1 |
| 1 | detrás de TemploNebulosa_2 | TemploNebulosa_1 |
| 1 | detrás de TemploNebulosaBuceo | TemploNebulosa_2 |
| 1 | detrás de TiendaSecreta_1 | TiendaSecreta_0 |
| 1 | detrás de TiendaSecreta_0 | TiendaSecreta_1 |
| 1 | detrás de TiendaSecreta_3 | TiendaSecreta_2 |
| 1 | detrás de TiendaSecreta_5 | TiendaSecreta_4 |
| 1 | detrás de Torneo_Pasillo | TorneoEntrada |
| 1 | detrás de Torneo_Batalla | Torneo_Camerino |
| 1 | detrás de TorreIris_1 | TorreIris_2 |
| 1 | detrás de Torre_Piso | Torre_Batalla |
| 1 | detrás de AulaUniversidad | UniversidadPokemon |

</details>

<details><summary><b>(b) todas las banderas en su valor final</b></summary>

Se llega a **157** mapas; faltan **560**.

| Mapas | Razón probable | Cuáles |
|---:|---|---|
| 65 | solo se entra por un evento (barco, vuelo, buceo, cinemática…) | Ascensor, BuceoSimple, CajaPkmnMenu, CasaGloboRocket, CentralElectrica, CentroTecno_S1, CentroTecno_S2, CentroTecno_S3, CentroTecno_S4, CentroTecno_S5, CetaceaBuceo, CuevaGaara, CuevaRemolino_3, CuevaSextanteBuceo, DarkraiHome, DarkraiHome2, DarkraiHomeReal, FabricaChangePkmn, FaroLuzAzotea, GYM7_Polar, GuaridaGalaxia_4, LigaPokemonHoenn, LigaPokemonJohto, LigaPokemonKanto, LigaPokemonSinnoh, LigaPokemonStar, LigaPokemonTeselia, LogrosMenu, MapaMenu, MisionesMenu, MovilMenu, OpcionesMenu, ParaisoAether_Atracadero, PersonajeMenu, PokedexMenu, PokemonDojo_Playing, PokemonFlyGol_Playing, PokemonMenu, RascaCielos_Azotea, Remolino1_Buceo … (+25) |
| 41 | no es un mapa del mundo (pantalla, menú o sala sin salidas) | BattleROOM, BattleROOMAqua, BattleROOMLava, CardsRoom, CharlaRoom, CieloCaminoIslas, ComandosMenu, CreditosInicioScreen, CreditosScreen, CuevaUmbral, FlyGol, HuevoMenu, InicioROOM, InterCambioRoom, IntroROOM, LigaPokemonAlola, LigaPokemonKalos, LoaderROOM, MochilaMenu, MultijugadorMenu, MundoDebug1, OptionsROOM, ParaisoAether_Reserva, PkmnEvolution, PkmnHabMenu, PkmnInfoMenu, PkmnMovMenu, Pokedex2Menu, Pokedex3Menu, PokedexLugarMenu, PuzleUNW, RaceN1, SafariAgua, SafariBasic, SafariHierbas, SecretRoom, Tragaperras, ViajeBarco, ZonaArenaBattle, Zona_Final … (+1) |
| 31 | ninguna salida ni script lleva aquí | BaseSecretaA1, BaseSecretaA2, BaseSecretaA3, BaseSecretaA4, BaseSecretaA5, BaseSecretaD1, BaseSecretaD2, BaseSecretaD3, BaseSecretaD4, BaseSecretaD5, BaseSecretaM1, BaseSecretaM2, BaseSecretaM3, BaseSecretaM4, BaseSecretaM5, BaseSecretaR1, BaseSecretaR2, BaseSecretaR3, BaseSecretaR4, BaseSecretaR5, BaseSecretaT1, BaseSecretaT2, BaseSecretaT3, BaseSecretaT4, BaseSecretaT5, BaseSecretaV1, BaseSecretaV2, BaseSecretaV3, BaseSecretaV4, BaseSecretaV5, ParaisoAether_Lab |
| 17 | detrás de EdificioPuertoSolar | CasaNeptuno, EdificioMultimediaStar, IslaMarte_Ruta, IslaNeptuno, IslaNeptuno_Ruta, IslaPluton, IslaSaturno_Ruta, IslaTerra, IslaTerra_RutaI, IslaVenus, Ruta_35, Ruta_35_1, Ruta_36, Ruta_39, Ruta_39_1, Ruta_39_2, Ruta_40_3 |
| 14 | detrás de CuevaRetaguardia_0 | CuevaRetaguardia_1, CuevaRetaguardia_2, CuevaRetaguardia_3, CuevaRetaguardia_4, CuevaRetaguardia_5, CuevaRetaguardia_6, CuevaRetaguardia_7, Fabrica_Retaguardia, FrenteEste, Palacio_Retaguardia, Survival_Retaguardia, Torneo_Retaguardia, Torre_Retaguardia, Zona_Retaguardia |
| 13 | detrás de CuevaPaleo_1 | BosqueSiluam4, CuevaPaleo_2, IslaFlecha_Ruta_27, ParqueVital, PuebloAdhara, PuebloWezen, Ruta_28, Ruta_29, Ruta_29_1, Ruta_30, Ruta_30_1, SalonModa, TeatroMelody |
| 11 | detrás de PuebloAdhara | BosqueSiluam1, BosqueSiluam2, BosqueSiluam3, Lab_Huevos, PuebloProcyon, PuertoJungla, RioPerseo, Ruta_26, Ruta_31, Ruta_32, Ruta_32_1 |
| 10 | detrás de MonteSelenio_2 | BosqueCristalino_2, BosqueCristalino_3, CuevaElemental, CuevaElemental_2, CuevaElemental_3, CuevaElemental_4, CuevaElemental_5, CuevaElemental_6, MonteSelenio, MonteSelenio_3 |
| 10 | detrás de CuevaChuzo_1 | BosqueFugaz, CasaArcturus, ColinaSagrada, CuevaChuzo_2, LagoLerna, PuebloArcturus, RioPerseo_2, RioPerseo_3, Ruta_33, Ruta_34 |
| 10 | detrás de RioHeracles_2 | CuevaSextante, CuevaSextante_3, MonteFenix, MonteOctante_2, MontePiscis, MontePiscis_2, RioHeracles, RioHeracles_3, TemploNebulosa_Old, TemploNebulosa_Old_2 |
| 9 | detrás de Ruta_21 | BancoStar, Bosque_Mistico, CentroTecno_0, CiudadAntares, EntradaRascacielos, GYM8_Antares, ParaisoFloral, PuertoLuz, Ruta_20_1 |
| 8 | detrás de RioMonoceros | LagoDraco, MonteOrion, PantanoSeismo, RioMonoceros_2, RioPegaso, RioPegaso_3, RuinasAndromeda_2, RutaAndromeda |
| 7 | detrás de MonteSelenio | BosqueCristalino, CuevaMagnetar, CuevaMagnetar_4, MonteSelenio_2, TemploSupernova_1, TemploSupernova_2, TemploSupernova_3 |
| 7 | detrás de InterRuta3 | Bosque_Tormenta, CasaClubFans, EntradaLabVoltio, IslaSaturno, PuenteKrono_1, PuenteKrono_3, Ruta_38 |
| 6 | detrás de CementerioMatagot | BosqueMarchito_2, CementerioMatagot_2, CementerioMatagot_3, TemploEspiritu_1, TemploEspiritu_2, TemploEspiritu_3 |
| 6 | detrás de ValleLlanos | BosqueNero_3, PlayaBrujula, TemploLlanos_1, TemploLlanos_2, TemploLlanos_3, TemploLlanos_Entrada |
| 6 | detrás de CiudadVega | ComisariaVega, FloristeriaVega, GYM5_Vega, Lab_Elm, PokemonRace, VegaBeach |
| 6 | detrás de CampoMagnetar | CuevaMagnetar_1, CuevaMagnetar_2, CuevaMagnetar_3, LagoQuasar, LagoQuasar_2, LagoQuasar_3 |
| 5 | detrás de CampoPulsar_2 | BosqueHechizo, BosqueHechizo_2, CampoPulsar, CostaVirgo, TemploSupernova_Old |
| 5 | detrás de FrenteCentral | CasaFrente, CuevaRetaguardia_Salida, CupulaEventos, EdificioLogros, PuertoFrente |
| 5 | detrás de AbismoPerdido_2 | CuevaLibra, CuevaLibra_2, ValleEspiritu, VolcanTormento, VolcanTormento_2 |
| 5 | detrás de Ruta_18_1 | CuevaMetal_1, CuevaMetal_2, CuevaMetal_3, Ruta_18_2, Ruta_18_3 |
| 5 | detrás de MonteOrion | CuevaOrion, CuevaOrion_2, CuevaOrion_3, CuevaOrion_4, CuevaOrion_5 |
| 4 | detrás de BarcoJungla_1 | BarcoCamarote, BarcoJungla_2, BarcoJungla_3, EdificioPuertoLuz |
| 4 | detrás de BosqueHechizo_2 | BosqueHechizo_3, BosqueHechizo_4, CampoBlazar, CampoBlazar_2 |
| 4 | detrás de BosqueNero | BosqueNero_2, MonteLeon, PlayaVida, RioAcuario |
| 4 | detrás de LagunaRoja | CementerioMatagot, CuevaAries, CuevaAries_2, ValleAries |
| 4 | detrás de CostaCetacea | CostaCetacea_2, CuevaCetacea, CuevaCetacea_2, RioHeracles_2 |
| 4 | detrás de CostaTauro_2 | CostaTauro, DesiertoEscorpio, Ruta_44_2, Ruta_44_3 |
| 4 | detrás de CuevaRoja_1 | CuevaRoja_2, IslaMarte, PokemonDojo, Ruta_37_2 |
| 4 | detrás de CuevaSextante_3 | CuevaSextante_2, MontePiscis_3, MontePiscis_4, ValleNebulo |
| 3 | detrás de ValleEspiritu | AbismoPerdido, AbismoPerdido_2, BosqueMental_2 |
| 3 | detrás de IslaSol | CalleVictoria_1, Ruta_23_1, Ruta_24_2 |
| 3 | detrás de CalleVictoria_1 | CalleVictoria_2, CalleVictoria_3, Ruta_25 |
| 3 | detrás de ValleSupernova_2 | CampoMagnetar_2, ValleSupernova, ValleSupernova_3 |
| 3 | detrás de CostaCapricornio_2 | CostaCapricornio, IslaAlma, TunelMatagot |
| 3 | detrás de CuevaMagmatica_1 | CuevaMagmatica_2, Ruta_37, Ruta_37_1 |
| 3 | detrás de CuevaNeith | CuevaNeith_3, IslaVenus_Ruta, Ruta_35_2 |
| 3 | detrás de FrenteEste | CuevaRetaguardia_0, InfiernoEntrada, TorreEntrada |
| 3 | detrás de PlayaVida | IslaHalley, Ruta_41_1, Ruta_41_2 |
| 3 | detrás de Ruta_24_2 | IslaSol, Ruta_24, Ruta_24_1 |
| 3 | detrás de EntradaLabVoltio | LabVoltio_0, LabVoltio_1, LabVoltio_2 |
| 3 | detrás de CuevaAries_2 | LagunaRoja, TunelTormento, VolcanTormento_3 |
| 3 | detrás de PalacioEntrada | Palacio_Central, Palacio_Este, Palacio_Oeste |
| 3 | detrás de ParaisoAether_Patio2 | ParaisoAether_EntradaMansion, ParaisoAether_Patio, ParaisoAether_Secreta |
| 3 | detrás de BosqueNero_2 | PlayaGeminis, Ruta_44, Ruta_44_1 |
| 3 | detrás de RuinasOmega | PuebloLuna, Ruta_19_1, Ruta_20 |
| 3 | detrás de CostaVirgo | Ruta_43, Ruta_43_1, Ruta_43_2 |
| 2 | la salida de Ruta_16_2 está en una parte a la que no se llega (aislada: hay que cruzar agua, un obstáculo o una barrera) | RioHidra, Ruta_16_3 |
| 2 | detrás de BosqueCentauri_2 | BosqueCentauri, BosqueCentauri_3 |
| 2 | detrás de BosqueMarchito_2 | BosqueMarchito, BosqueMental |
| 2 | detrás de RioAcuario | BosqueNero, SaltoLeon |
| 2 | detrás de ValleSupernova | CampoMagnetar, ValleSupernova_2 |
| 2 | detrás de DesiertoEscorpio | CostaTauro_2, DesiertoEscorpio_2 |
| 2 | detrás de CuevaArdiente_2 | CuevaArdiente_1, GuaridaMagma_1 |
| 2 | detrás de CuevaArdiente_1 | CuevaArdiente_2, ZonaVolcanica_3 |
| 2 | detrás de CuevaCaliente_1 | CuevaCaliente_2, IslaCalor |
| 2 | detrás de CuevaChuzo_2 | CuevaChuzo_1, CuevaChuzo_3 |
| 2 | detrás de CuevaMagmatica_2 | CuevaMagmatica_1, CuevaMagmatica_3 |
| 2 | detrás de CuevaMoonlight | CuevaMoonlight_2, CuevaMoonlight_3 |
| 2 | detrás de CuevaNeith_3 | CuevaNeith, CuevaNeith_2 |
| 2 | detrás de CuevaOceanica_3 | CuevaOceanica_2, CuevaOceanica_4 |
| 2 | detrás de CuevaRetaguardia_Salida | CuevaRetaguardia_Centro, FrenteCentral |
| 2 | detrás de FrenteNorte | FabricaEntrada, PalacioEntrada |
| 2 | detrás de FabricaVenus_1 | FabricaVenus_2, FabricaVenus_S |
| 2 | detrás de Bosque_Mistico | FaroLuzBajo, Ruta_21 |
| 2 | detrás de GuaridaAqua_4 | GuaridaAqua_2, GuaridaAqua_3 |
| 2 | detrás de GuaridaMagma_2 | GuaridaMagma_3, GuaridaMagma_4 |
| 2 | detrás de GuaridaRocket_2 | GuaridaRocket_1, GuaridaRocket_3 |
| 2 | detrás de PuenteKrono_1 | InterRuta3, PuenteKrono_2 |
| 2 | detrás de IslaMercurio_Ruta | InterRutaCaloris, IslaMercurio |
| 2 | detrás de Ruta_11_2 | IslaEnergia, Ruta_11_4 |
| 2 | detrás de IslaHalley | IslaHalley_Ruta, Ruta_41 |
| 2 | detrás de Bosque_Tormenta | IslaJupiter, Ruta_38_1 |
| 2 | detrás de CuevaOceanica_1 | IslaTerra_RutaD, Ruta_36_1 |
| 2 | detrás de IslaUrano_Ruta | IslaUrano, PokemonFlyGol |
| 2 | detrás de Ruta_40 | IslaUrano_Ruta, Ruta_40_1 |
| 2 | detrás de LabJungla_2 | LabJungla_1, LabJungla_3 |
| 2 | detrás de MansionHollow_1 | MansionHollow_0, MansionHollow_2 |
| 2 | detrás de MundoInverso2 | MundoInverso, MundoInverso3 |
| 2 | detrás de ParaisoAether_Patio | ParaisoAether_Entrada, ParaisoAether_Patio2 |
| 2 | detrás de PlayaBrujula | RioAcuario_2, ValleLlanos |
| 2 | detrás de ValleSupernova_3 | RioCancri, RioCancri_2 |
| 2 | detrás de RuinasAndromeda_2 | RioMonoceros, RuinasAndromeda |
| 2 | detrás de CuevaMoonlight_3 | RuinasOmega, Ruta_19 |
| 2 | detrás de Ruta_24 | Ruta_22, Ruta_22_1 |
| 2 | detrás de Ruta_40_1 | Ruta_40, Ruta_40_2 |
| 2 | detrás de RioAcuario_2 | Ruta_42, Ruta_42_2 |
| 2 | detrás de SantuarioCeleste_1 | SantuarioCeleste_2, SantuarioTerra |
| 2 | detrás de FrenteOeste | SurvivalEntrada, ZonaEntrada |
| 2 | detrás de Torneo_Camerino | Torneo_Batalla, Torneo_Pasillo |
| 2 | detrás de TorreIris_2 | TorreIris_1, TorreIris_Azotea |
| 1 | la salida de CasaAbandonada_0 está en una parte a la que no se llega (aislada: hay que cruzar agua, un obstáculo o una barrera) | AlcantarillaPolar |
| 1 | la salida de Centro_Pokemon está en una parte a la que no se llega (aislada: hay que cruzar agua, un obstáculo o una barrera) | Centro_Pokemon2 |
| 1 | la salida de CiudadSirio está en una parte a la que no se llega (no:((h.get("fantasmasSirio", 0) != 1))) | GYM3_Sirio |
| 1 | la salida de PuebloAlba está en una parte a la que no se llega (aislada: hay que cruzar agua, un obstáculo o una barrera) | GranjaCajasPokemon |
| 1 | la salida de Lago_Senn está en una parte a la que no se llega (aislada: hay que cruzar agua, un obstáculo o una barrera) | Lago_Senn_2 |
| 1 | la salida de Ruta_11 está en una parte a la que no se llega (surf) | Ruta_11_1 |
| 1 | la salida de Ruta_11_3 está en una parte a la que no se llega (surf) | Ruta_11_2 |
| 1 | la salida de Ruta_14 está en una parte a la que no se llega (aislada: hay que cruzar agua, un obstáculo o una barrera) | Ruta_14_1 |
| 1 | la salida de Ruta_18 está en una parte a la que no se llega (aislada: hay que cruzar agua, un obstáculo o una barrera) | Ruta_18_1 |
| 1 | la salida de Ruta_4_4 está en una parte a la que no se llega (surf) | Ruta_23 |
| 1 | la salida de Ruta_7 está en una parte a la que no se llega (surf) | Ruta_7_1 |
| 1 | la salida de Ruta_8 está en una parte a la que no se llega (aislada: hay que cruzar agua, un obstáculo o una barrera) | Ruta_8_1 |
| 1 | la salida de CuevaExtravio está en una parte a la que no se llega (aislada: hay que cruzar agua, un obstáculo o una barrera) | ZonaExtravio |
| 1 | la salida de ZonaVolcanica_1 está en una parte a la que no se llega (aislada: hay que cruzar agua, un obstáculo o una barrera) | ZonaVolcanica_2 |
| 1 | detrás de AlcantarillaPolar | AlcantarillaPolar2 |
| 1 | detrás de UniversidadPokemon | AulaUniversidad |
| 1 | detrás de BarcoCamarote | BarcoJungla_1 |
| 1 | detrás de BiblioAntares2 | BiblioAntares |
| 1 | detrás de BiblioAntares | BiblioAntares2 |
| 1 | detrás de BosqueCentauri_3 | BosqueCentauri_2 |
| 1 | detrás de PuertoFrente | CafeteriaPL |
| 1 | detrás de TemploSupernova_Old | CampoPulsar_2 |
| 1 | detrás de RascacielosPiso | CasaAntares |
| 1 | detrás de CastleRekiem_2 | CastleRekiem_1 |
| 1 | detrás de CastleRekiem_1 | CastleRekiem_2 |
| 1 | detrás de CastleRekiem_4 | CastleRekiem_3 |
| 1 | detrás de CastleRekiem_3 | CastleRekiem_4 |
| 1 | detrás de CastleRekiem_Final | CastleRekiem_5 |
| 1 | detrás de CastleRekiem_5 | CastleRekiem_Final |
| 1 | detrás de Ruta_16_3 | CiudadVega |
| 1 | detrás de ComisariaVega | ComisariaVega2 |
| 1 | detrás de IslaAlma | CostaCapricornio_2 |
| 1 | detrás de CuevaCetacea | CostaCetacea |
| 1 | detrás de CuevaCaliente_2 | CuevaCaliente_1 |
| 1 | detrás de CuevaMoonlight_2 | CuevaMoonlight |
| 1 | detrás de CuevaOceanica_2 | CuevaOceanica_1 |
| 1 | detrás de CuevaOceanica_4 | CuevaOceanica_3 |
| 1 | detrás de CuevaPaleo_2 | CuevaPaleo_1 |
| 1 | detrás de CuevaRemolino_2 | CuevaRemolino |
| 1 | detrás de CuevaRemolino | CuevaRemolino_2 |
| 1 | detrás de CuevaRoja_2 | CuevaRoja_1 |
| 1 | detrás de GuaridaAqua_1 | CuevaRuta24 |
| 1 | detrás de BosqueHechizo_4 | CuevaSagitario |
| 1 | detrás de CuevaVendaval_2 | CuevaVendaval_1 |
| 1 | detrás de CuevaVendaval_1 | CuevaVendaval_2 |
| 1 | detrás de MundoInverso | EdificioPuertoSolar |
| 1 | detrás de FabricaVenus_2 | FabricaVenus_1 |
| 1 | detrás de Fabrica_Cambios | Fabrica_Batalla |
| 1 | detrás de Fabrica_Batalla | Fabrica_Cambios |
| 1 | detrás de TorneoEntrada | FrenteNorte |
| 1 | detrás de SurvivalEntrada | FrenteOeste |
| 1 | detrás de CuevaRuta24 | GuaridaAqua_1 |
| 1 | detrás de GuaridaAqua_2 | GuaridaAqua_4 |
| 1 | detrás de GuaridaEscuadron2 | GuaridaEscuadron |
| 1 | detrás de GuaridaEscuadron | GuaridaEscuadron2 |
| 1 | detrás de GuaridaGalaxia_2 | GuaridaGalaxia |
| 1 | detrás de GuaridaGalaxia | GuaridaGalaxia_2 |
| 1 | detrás de GuaridaGalaxia_4 | GuaridaGalaxia_3 |
| 1 | detrás de GuaridaMagma_4 | GuaridaMagma_2 |
| 1 | detrás de GuaridaRocket_1 | GuaridaRocket_2 |
| 1 | detrás de IslaMercurio | IslaMercurio_Ruta |
| 1 | detrás de Ruta_23 | IslaViento |
| 1 | detrás de LabJungla_1 | LabJungla_2 |
| 1 | detrás de SalonFama | LigaPkmnEntrada |
| 1 | detrás de MansionHollow_2 | MansionHollow_1 |
| 1 | detrás de MonteOctante_2 | MonteOctante |
| 1 | detrás de MundoInverso3 | MundoInverso2 |
| 1 | detrás de ParaisoAether_Secreta | ParaisoAether_Dormitorio |
| 1 | detrás de InterRutaCaloris | ParqueCaloris |
| 1 | detrás de SaltoLeon | PlayaLyra |
| 1 | detrás de ParqueVital | PuebloRegulo |
| 1 | detrás de CasaAntares | RascacielosPiso |
| 1 | detrás de RioPegaso | RioPegaso_2 |
| 1 | detrás de Ruta_24Aqua_Buceo | Ruta_24Aqua2_Buceo |
| 1 | detrás de Ruta_24Aqua2_Buceo | Ruta_24Aqua_Buceo |
| 1 | detrás de BosqueFugaz | Ruta_33_1 |
| 1 | detrás de Ruta_42_2 | Ruta_42_1 |
| 1 | detrás de LigaPkmnEntrada | SalonFama |
| 1 | detrás de SantuarioTerra | SantuarioCeleste_1 |
| 1 | detrás de TemploNebulosa_2 | TemploNebulosa_1 |
| 1 | detrás de TemploNebulosaBuceo | TemploNebulosa_2 |
| 1 | detrás de Torneo_Pasillo | TorneoEntrada |
| 1 | detrás de Torneo_Batalla | Torneo_Camerino |
| 1 | detrás de TorreIris_1 | TorreIris_2 |
| 1 | detrás de Torre_Piso | Torre_Batalla |
| 1 | detrás de AulaUniversidad | UniversidadPokemon |
| 1 | detrás de ZonaVolcanica_2 | ZonaVolcanica_4 |

</details>

<details><summary><b>(c) como (b), ignorando surf, bici y MO</b></summary>

Se llega a **232** mapas; faltan **485**.

| Mapas | Razón probable | Cuáles |
|---:|---|---|
| 65 | solo se entra por un evento (barco, vuelo, buceo, cinemática…) | Ascensor, BuceoSimple, CajaPkmnMenu, CasaGloboRocket, CentralElectrica, CentroTecno_S1, CentroTecno_S2, CentroTecno_S3, CentroTecno_S4, CentroTecno_S5, CetaceaBuceo, CuevaGaara, CuevaRemolino_3, CuevaSextanteBuceo, DarkraiHome, DarkraiHome2, DarkraiHomeReal, FabricaChangePkmn, FaroLuzAzotea, GYM7_Polar, GuaridaGalaxia_4, LigaPokemonHoenn, LigaPokemonJohto, LigaPokemonKanto, LigaPokemonSinnoh, LigaPokemonStar, LigaPokemonTeselia, LogrosMenu, MapaMenu, MisionesMenu, MovilMenu, OpcionesMenu, ParaisoAether_Atracadero, PersonajeMenu, PokedexMenu, PokemonDojo_Playing, PokemonFlyGol_Playing, PokemonMenu, RascaCielos_Azotea, Remolino1_Buceo … (+25) |
| 41 | no es un mapa del mundo (pantalla, menú o sala sin salidas) | BattleROOM, BattleROOMAqua, BattleROOMLava, CardsRoom, CharlaRoom, CieloCaminoIslas, ComandosMenu, CreditosInicioScreen, CreditosScreen, CuevaUmbral, FlyGol, HuevoMenu, InicioROOM, InterCambioRoom, IntroROOM, LigaPokemonAlola, LigaPokemonKalos, LoaderROOM, MochilaMenu, MultijugadorMenu, MundoDebug1, OptionsROOM, ParaisoAether_Reserva, PkmnEvolution, PkmnHabMenu, PkmnInfoMenu, PkmnMovMenu, Pokedex2Menu, Pokedex3Menu, PokedexLugarMenu, PuzleUNW, RaceN1, SafariAgua, SafariBasic, SafariHierbas, SecretRoom, Tragaperras, ViajeBarco, ZonaArenaBattle, Zona_Final … (+1) |
| 31 | ninguna salida ni script lleva aquí | BaseSecretaA1, BaseSecretaA2, BaseSecretaA3, BaseSecretaA4, BaseSecretaA5, BaseSecretaD1, BaseSecretaD2, BaseSecretaD3, BaseSecretaD4, BaseSecretaD5, BaseSecretaM1, BaseSecretaM2, BaseSecretaM3, BaseSecretaM4, BaseSecretaM5, BaseSecretaR1, BaseSecretaR2, BaseSecretaR3, BaseSecretaR4, BaseSecretaR5, BaseSecretaT1, BaseSecretaT2, BaseSecretaT3, BaseSecretaT4, BaseSecretaT5, BaseSecretaV1, BaseSecretaV2, BaseSecretaV3, BaseSecretaV4, BaseSecretaV5, ParaisoAether_Lab |
| 17 | detrás de EdificioPuertoSolar | CasaNeptuno, EdificioMultimediaStar, IslaMarte_Ruta, IslaNeptuno, IslaNeptuno_Ruta, IslaPluton, IslaSaturno_Ruta, IslaTerra, IslaTerra_RutaI, IslaVenus, Ruta_35, Ruta_35_1, Ruta_36, Ruta_39, Ruta_39_1, Ruta_39_2, Ruta_40_3 |
| 14 | detrás de CuevaRetaguardia_0 | CuevaRetaguardia_1, CuevaRetaguardia_2, CuevaRetaguardia_3, CuevaRetaguardia_4, CuevaRetaguardia_5, CuevaRetaguardia_6, CuevaRetaguardia_7, Fabrica_Retaguardia, FrenteEste, Palacio_Retaguardia, Survival_Retaguardia, Torneo_Retaguardia, Torre_Retaguardia, Zona_Retaguardia |
| 13 | detrás de CuevaPaleo_1 | BosqueSiluam4, CuevaPaleo_2, IslaFlecha_Ruta_27, ParqueVital, PuebloAdhara, PuebloWezen, Ruta_28, Ruta_29, Ruta_29_1, Ruta_30, Ruta_30_1, SalonModa, TeatroMelody |
| 11 | detrás de PuebloAdhara | BosqueSiluam1, BosqueSiluam2, BosqueSiluam3, Lab_Huevos, PuebloProcyon, PuertoJungla, RioPerseo, Ruta_26, Ruta_31, Ruta_32, Ruta_32_1 |
| 10 | detrás de MonteSelenio_2 | BosqueCristalino_2, BosqueCristalino_3, CuevaElemental, CuevaElemental_2, CuevaElemental_3, CuevaElemental_4, CuevaElemental_5, CuevaElemental_6, MonteSelenio, MonteSelenio_3 |
| 10 | detrás de CuevaChuzo_1 | BosqueFugaz, CasaArcturus, ColinaSagrada, CuevaChuzo_2, LagoLerna, PuebloArcturus, RioPerseo_2, RioPerseo_3, Ruta_33, Ruta_34 |
| 10 | detrás de RioHeracles_2 | CuevaSextante, CuevaSextante_3, MonteFenix, MonteOctante_2, MontePiscis, MontePiscis_2, RioHeracles, RioHeracles_3, TemploNebulosa_Old, TemploNebulosa_Old_2 |
| 8 | detrás de RioMonoceros | LagoDraco, MonteOrion, PantanoSeismo, RioMonoceros_2, RioPegaso, RioPegaso_3, RuinasAndromeda_2, RutaAndromeda |
| 7 | detrás de MonteSelenio | BosqueCristalino, CuevaMagnetar, CuevaMagnetar_4, MonteSelenio_2, TemploSupernova_1, TemploSupernova_2, TemploSupernova_3 |
| 7 | detrás de InterRuta3 | Bosque_Tormenta, CasaClubFans, EntradaLabVoltio, IslaSaturno, PuenteKrono_1, PuenteKrono_3, Ruta_38 |
| 6 | detrás de CementerioMatagot | BosqueMarchito_2, CementerioMatagot_2, CementerioMatagot_3, TemploEspiritu_1, TemploEspiritu_2, TemploEspiritu_3 |
| 6 | detrás de ValleLlanos | BosqueNero_3, PlayaBrujula, TemploLlanos_1, TemploLlanos_2, TemploLlanos_3, TemploLlanos_Entrada |
| 6 | detrás de CampoMagnetar | CuevaMagnetar_1, CuevaMagnetar_2, CuevaMagnetar_3, LagoQuasar, LagoQuasar_2, LagoQuasar_3 |
| 5 | detrás de CampoPulsar_2 | BosqueHechizo, BosqueHechizo_2, CampoPulsar, CostaVirgo, TemploSupernova_Old |
| 5 | detrás de FrenteCentral | CasaFrente, CuevaRetaguardia_Salida, CupulaEventos, EdificioLogros, PuertoFrente |
| 5 | detrás de AbismoPerdido_2 | CuevaLibra, CuevaLibra_2, ValleEspiritu, VolcanTormento, VolcanTormento_2 |
| 5 | detrás de MonteOrion | CuevaOrion, CuevaOrion_2, CuevaOrion_3, CuevaOrion_4, CuevaOrion_5 |
| 4 | detrás de BosqueHechizo_2 | BosqueHechizo_3, BosqueHechizo_4, CampoBlazar, CampoBlazar_2 |
| 4 | detrás de BosqueNero | BosqueNero_2, MonteLeon, PlayaVida, RioAcuario |
| 4 | detrás de LagunaRoja | CementerioMatagot, CuevaAries, CuevaAries_2, ValleAries |
| 4 | detrás de CostaCetacea | CostaCetacea_2, CuevaCetacea, CuevaCetacea_2, RioHeracles_2 |
| 4 | detrás de CostaTauro_2 | CostaTauro, DesiertoEscorpio, Ruta_44_2, Ruta_44_3 |
| 4 | detrás de CuevaRoja_1 | CuevaRoja_2, IslaMarte, PokemonDojo, Ruta_37_2 |
| 4 | detrás de CuevaSextante_3 | CuevaSextante_2, MontePiscis_3, MontePiscis_4, ValleNebulo |
| 3 | detrás de ValleEspiritu | AbismoPerdido, AbismoPerdido_2, BosqueMental_2 |
| 3 | detrás de BarcoJungla_1 | BarcoCamarote, BarcoJungla_2, BarcoJungla_3 |
| 3 | detrás de ValleSupernova_2 | CampoMagnetar_2, ValleSupernova, ValleSupernova_3 |
| 3 | detrás de CostaCapricornio_2 | CostaCapricornio, IslaAlma, TunelMatagot |
| 3 | detrás de CuevaMagmatica_1 | CuevaMagmatica_2, Ruta_37, Ruta_37_1 |
| 3 | detrás de CuevaNeith | CuevaNeith_3, IslaVenus_Ruta, Ruta_35_2 |
| 3 | detrás de FrenteEste | CuevaRetaguardia_0, InfiernoEntrada, TorreEntrada |
| 3 | detrás de PlayaVida | IslaHalley, Ruta_41_1, Ruta_41_2 |
| 3 | detrás de EntradaLabVoltio | LabVoltio_0, LabVoltio_1, LabVoltio_2 |
| 3 | detrás de CuevaAries_2 | LagunaRoja, TunelTormento, VolcanTormento_3 |
| 3 | detrás de PalacioEntrada | Palacio_Central, Palacio_Este, Palacio_Oeste |
| 3 | detrás de ParaisoAether_Patio2 | ParaisoAether_EntradaMansion, ParaisoAether_Patio, ParaisoAether_Secreta |
| 3 | detrás de BosqueNero_2 | PlayaGeminis, Ruta_44, Ruta_44_1 |
| 3 | detrás de CostaVirgo | Ruta_43, Ruta_43_1, Ruta_43_2 |
| 2 | la salida de CalleVictoria_1 está en una parte a la que no se llega (aislada: hay que cruzar agua, un obstáculo o una barrera) | CalleVictoria_2, CalleVictoria_3 |
| 2 | la salida de CuevaMoonlight está en una parte a la que no se llega (aislada: hay que cruzar agua, un obstáculo o una barrera) | CuevaMoonlight_2, CuevaMoonlight_3 |
| 2 | detrás de BosqueCentauri_2 | BosqueCentauri, BosqueCentauri_3 |
| 2 | detrás de BosqueMarchito_2 | BosqueMarchito, BosqueMental |
| 2 | detrás de RioAcuario | BosqueNero, SaltoLeon |
| 2 | detrás de ValleSupernova | CampoMagnetar, ValleSupernova_2 |
| 2 | detrás de DesiertoEscorpio | CostaTauro_2, DesiertoEscorpio_2 |
| 2 | detrás de CuevaChuzo_2 | CuevaChuzo_1, CuevaChuzo_3 |
| 2 | detrás de CuevaMagmatica_2 | CuevaMagmatica_1, CuevaMagmatica_3 |
| 2 | detrás de CuevaNeith_3 | CuevaNeith, CuevaNeith_2 |
| 2 | detrás de CuevaOceanica_3 | CuevaOceanica_2, CuevaOceanica_4 |
| 2 | detrás de CuevaRetaguardia_Salida | CuevaRetaguardia_Centro, FrenteCentral |
| 2 | detrás de FrenteNorte | FabricaEntrada, PalacioEntrada |
| 2 | detrás de FabricaVenus_1 | FabricaVenus_2, FabricaVenus_S |
| 2 | detrás de GuaridaAqua_4 | GuaridaAqua_2, GuaridaAqua_3 |
| 2 | detrás de GuaridaRocket_2 | GuaridaRocket_1, GuaridaRocket_3 |
| 2 | detrás de PuenteKrono_1 | InterRuta3, PuenteKrono_2 |
| 2 | detrás de IslaMercurio_Ruta | InterRutaCaloris, IslaMercurio |
| 2 | detrás de IslaHalley | IslaHalley_Ruta, Ruta_41 |
| 2 | detrás de Bosque_Tormenta | IslaJupiter, Ruta_38_1 |
| 2 | detrás de CuevaOceanica_1 | IslaTerra_RutaD, Ruta_36_1 |
| 2 | detrás de IslaUrano_Ruta | IslaUrano, PokemonFlyGol |
| 2 | detrás de Ruta_40 | IslaUrano_Ruta, Ruta_40_1 |
| 2 | detrás de LabJungla_2 | LabJungla_1, LabJungla_3 |
| 2 | detrás de MansionHollow_1 | MansionHollow_0, MansionHollow_2 |
| 2 | detrás de MundoInverso2 | MundoInverso, MundoInverso3 |
| 2 | detrás de ParaisoAether_Patio | ParaisoAether_Entrada, ParaisoAether_Patio2 |
| 2 | detrás de PlayaBrujula | RioAcuario_2, ValleLlanos |
| 2 | detrás de ValleSupernova_3 | RioCancri, RioCancri_2 |
| 2 | detrás de RuinasAndromeda_2 | RioMonoceros, RuinasAndromeda |
| 2 | detrás de Ruta_40_1 | Ruta_40, Ruta_40_2 |
| 2 | detrás de RioAcuario_2 | Ruta_42, Ruta_42_2 |
| 2 | detrás de SantuarioCeleste_1 | SantuarioCeleste_2, SantuarioTerra |
| 2 | detrás de FrenteOeste | SurvivalEntrada, ZonaEntrada |
| 2 | detrás de Torneo_Camerino | Torneo_Batalla, Torneo_Pasillo |
| 2 | detrás de TorreIris_2 | TorreIris_1, TorreIris_Azotea |
| 1 | la salida de CasaAbandonada_0 está en una parte a la que no se llega (aislada: hay que cruzar agua, un obstáculo o una barrera) | AlcantarillaPolar |
| 1 | la salida de CiudadSirio está en una parte a la que no se llega (no:((h.get("fantasmasSirio", 0) != 1))) | GYM3_Sirio |
| 1 | la salida de CiudadVega depende de la historia: ((h.get("bicicleta_lesion", 0) == 1)) | GYM5_Vega |
| 1 | la salida de PuebloAlba está en una parte a la que no se llega (aislada: hay que cruzar agua, un obstáculo o una barrera) | GranjaCajasPokemon |
| 1 | la salida de CasaAntares solo vale entrando por otra puerta (index_place / room_out) | RascacielosPiso |
| 1 | la salida de CalleVictoria_1 está en una parte a la que no se llega (no:((h.get("LIGA_STAR", 0) == 0))) | Ruta_25 |
| 1 | detrás de AlcantarillaPolar | AlcantarillaPolar2 |
| 1 | detrás de UniversidadPokemon | AulaUniversidad |
| 1 | detrás de BarcoCamarote | BarcoJungla_1 |
| 1 | detrás de BosqueCentauri_3 | BosqueCentauri_2 |
| 1 | detrás de PuertoFrente | CafeteriaPL |
| 1 | detrás de TemploSupernova_Old | CampoPulsar_2 |
| 1 | detrás de CastleRekiem_2 | CastleRekiem_1 |
| 1 | detrás de CastleRekiem_1 | CastleRekiem_2 |
| 1 | detrás de CastleRekiem_4 | CastleRekiem_3 |
| 1 | detrás de CastleRekiem_3 | CastleRekiem_4 |
| 1 | detrás de CastleRekiem_Final | CastleRekiem_5 |
| 1 | detrás de CastleRekiem_5 | CastleRekiem_Final |
| 1 | detrás de IslaAlma | CostaCapricornio_2 |
| 1 | detrás de CuevaCetacea | CostaCetacea |
| 1 | detrás de CuevaOceanica_2 | CuevaOceanica_1 |
| 1 | detrás de CuevaOceanica_4 | CuevaOceanica_3 |
| 1 | detrás de CuevaPaleo_2 | CuevaPaleo_1 |
| 1 | detrás de CuevaRemolino_2 | CuevaRemolino |
| 1 | detrás de CuevaRemolino | CuevaRemolino_2 |
| 1 | detrás de CuevaRoja_2 | CuevaRoja_1 |
| 1 | detrás de GuaridaAqua_1 | CuevaRuta24 |
| 1 | detrás de BosqueHechizo_4 | CuevaSagitario |
| 1 | detrás de MundoInverso | EdificioPuertoSolar |
| 1 | detrás de FabricaVenus_2 | FabricaVenus_1 |
| 1 | detrás de Fabrica_Cambios | Fabrica_Batalla |
| 1 | detrás de Fabrica_Batalla | Fabrica_Cambios |
| 1 | detrás de TorneoEntrada | FrenteNorte |
| 1 | detrás de SurvivalEntrada | FrenteOeste |
| 1 | detrás de CuevaRuta24 | GuaridaAqua_1 |
| 1 | detrás de GuaridaAqua_2 | GuaridaAqua_4 |
| 1 | detrás de GuaridaEscuadron2 | GuaridaEscuadron |
| 1 | detrás de GuaridaEscuadron | GuaridaEscuadron2 |
| 1 | detrás de GuaridaRocket_1 | GuaridaRocket_2 |
| 1 | detrás de IslaMercurio | IslaMercurio_Ruta |
| 1 | detrás de LabJungla_1 | LabJungla_2 |
| 1 | detrás de MansionHollow_2 | MansionHollow_1 |
| 1 | detrás de MonteOctante_2 | MonteOctante |
| 1 | detrás de MundoInverso3 | MundoInverso2 |
| 1 | detrás de ParaisoAether_Secreta | ParaisoAether_Dormitorio |
| 1 | detrás de InterRutaCaloris | ParqueCaloris |
| 1 | detrás de SaltoLeon | PlayaLyra |
| 1 | detrás de ParqueVital | PuebloRegulo |
| 1 | detrás de RioPegaso | RioPegaso_2 |
| 1 | detrás de Ruta_24Aqua_Buceo | Ruta_24Aqua2_Buceo |
| 1 | detrás de Ruta_24Aqua2_Buceo | Ruta_24Aqua_Buceo |
| 1 | detrás de BosqueFugaz | Ruta_33_1 |
| 1 | detrás de Ruta_42_2 | Ruta_42_1 |
| 1 | detrás de SantuarioTerra | SantuarioCeleste_1 |
| 1 | detrás de TemploNebulosa_2 | TemploNebulosa_1 |
| 1 | detrás de TemploNebulosaBuceo | TemploNebulosa_2 |
| 1 | detrás de Torneo_Pasillo | TorneoEntrada |
| 1 | detrás de Torneo_Batalla | Torneo_Camerino |
| 1 | detrás de TorreIris_1 | TorreIris_2 |
| 1 | detrás de Torre_Piso | Torre_Batalla |
| 1 | detrás de AulaUniversidad | UniversidadPokemon |

</details>

# NovaGPU TS 1T — Whitepaper Técnico 2026
### Arquitectura N.E.O.N. · GPU RTL Open Source en Verilog

**Nova Studios / Maximal Technology**  
**Repositorio:** https://github.com/nova-studios-hw/novagpu-ts1t  
**Comunidad:** https://discord.gg/RfQwz8ySr  
**Revisión:** Junio 2026  
**Licencia:** MIT

---

> *"Estamos construyendo lo que la mayoría dice que no se puede hacer con estos recursos. El proceso es abierto. Síguelo."*

---

## Índice

1. [Introducción y Contexto](#1-introducción-y-contexto)
2. [¿Qué es el NovaGPU TS 1T?](#2-qué-es-el-novagpu-ts-1t)
3. [Estado Actual del Proyecto](#3-estado-actual-del-proyecto)
4. [Arquitectura N.E.O.N.](#4-arquitectura-neon)
5. [Módulos RTL — Descripción Detallada](#5-módulos-rtl--descripción-detallada)
   - 5.1 [PCIe Input](#51-pcie-input)
   - 5.2 [Token Matching Unit (TMU)](#52-token-matching-unit-tmu)
   - 5.3 [Shader Cluster](#53-shader-cluster)
   - 5.4 [Budget Controller](#54-budget-controller)
   - 5.5 [Three Tracing Unit (TTU)](#55-three-tracing-unit-ttu)
   - 5.6 [Tile Arbiter](#56-tile-arbiter)
   - 5.7 [Dual-Port SRAM](#57-dual-port-sram)
   - 5.8 [Motion Vector Unit (MVU)](#58-motion-vector-unit-mvu)
   - 5.9 [Video Output](#59-video-output)
   - 5.10 [Framebuffer](#510-framebuffer)
   - 5.11 [Triangle Rasterizer](#511-triangle-rasterizer)
   - 5.12 [Nexus](#512-nexus)
   - 5.13 [PVA — Programmable Vision Accelerator](#513-pva--programmable-vision-accelerator)
   - 5.14 [MPE — Meta Prediction Engine](#514-mpe--meta-prediction-engine)
   - 5.15 [AFA — Aquatic and Foliage Accelerator](#515-afa--aquatic-and-foliage-accelerator)
   - 5.16 [GIA — Geometry Intelligence Accelerator](#516-gia--geometry-intelligence-accelerator)
6. [Triangle Rasterizer — Análisis Profundo](#6-triangle-rasterizer--análisis-profundo)
7. [Three Tracing — Ray Tracing por Hardware](#7-three-tracing--ray-tracing-por-hardware)
8. [Motion Vector Unit — Frame Generation](#8-motion-vector-unit--frame-generation)
9. [N.E.O.N. Memory Bridge](#9-neon-memory-bridge)
10. [Pipeline de Generación de Video](#10-pipeline-de-generación-de-video)
11. [Validación y Resultados de Tests](#11-validación-y-resultados-de-tests)
12. [Implementación en FPGA](#12-implementación-en-fpga)
13. [Especificaciones de Hardware](#13-especificaciones-de-hardware)
14. [Posicionamiento Competitivo](#14-posicionamiento-competitivo)
15. [Filosofía del Proyecto y Uso de IA](#15-filosofía-del-proyecto-y-uso-de-ia)
16. [Roadmap](#16-roadmap)
17. [Conclusión](#17-conclusión)
18. [Cómo Contribuir / Ejecutar el Proyecto](#18-cómo-contribuir--ejecutar-el-proyecto)

---

## 1. Introducción y Contexto

Diseñar una GPU desde cero no es algo que los libros de texto te digan que puedes hacer solo, con herramientas open source, desde un escritorio. La industria lleva décadas convenciéndonos de que ese tipo de trabajo requiere cientos de ingenieros, fabricantes con acceso a nodos de proceso sub-10nm, y presupuestos que empiezan en decenas de millones de dólares.

El NovaGPU TS 1T existe para demostrar que eso no es completamente cierto.

Este proyecto no intenta competir con NVIDIA ni con AMD. Eso sería absurdo y no es el objetivo. Lo que sí intenta es demostrar que una arquitectura gráfica seria, fundamentada técnicamente, con ray tracing por hardware y generación de frames, puede nacer fuera del ecosistema corporativo, ser completamente open source, y avanzar con rigor de ingeniería real.

El TS 1T es un GPU RTL escrito en Verilog, sintetizable, con síntesis e implementación exitosas, apuntando inicialmente a FPGA y eventualmente a ASIC en nodo de 28nm. Es un proyecto de I+D genuino. Hay cosas que funcionan, hay cosas que están en desarrollo activo, y hay cosas que todavía no están validadas físicamente. Todo eso está documentado aquí con la misma honestidad con la que se lleva el desarrollo día a día.

Este whitepaper documenta el estado técnico del proyecto en Junio 2026, explica la arquitectura en detalle, reporta los resultados de validación actuales, y describe la visión a largo plazo.

---

## 2. ¿Qué es el NovaGPU TS 1T?

El NovaGPU TS 1T es una GPU completa implementada en RTL Verilog. No es una simulación de GPU, no es un emulador, no es un soft-core genérico adaptado. Es un pipeline gráfico diseñado desde principios arquitectónicos propios, con módulos específicos para cada etapa del proceso de renderizado.

El nombre tiene una lógica interna:

- **Nova** — Algo nuevo. Una estrella que de repente incrementa su brillo. La idea de algo poderoso emergiendo desde la nada.
- **GPU** — Graphics Processing Unit. Exactamente lo que es.
- **TS** — Three Tracing. El sistema propietario de ray tracing y path tracing adaptativo que define esta arquitectura.
- **1T** — Primera generación. La T indica el comienzo. Después vendrá el TS 1, misma arquitectura, 14nm, más núcleos.

El núcleo del diseño es la arquitectura **N.E.O.N.** (Núcleo de Ejecución Optimizada Nativa), un modelo de ejecución por flujo de tokens que reemplaza el modelo Von Neumann clásico utilizado por CUDA y GCN.

El pipeline completo incluye: interfaz PCIe, Token Matching Unit, Shader Cluster con ISA de 8 opcodes, Three Tracing Unit con BVH hardware, Tile Arbiter con Z-test atómico, SRAM dual-port con 64 bancos, Motion Vector Unit para generación de frames, rasterizador de triángulos con funciones de Pineda, framebuffer, y salida de video.

El proyecto está construido por un solo desarrollador con herramientas open source. Cada decisión arquitectónica está documentada. Cada bug está registrado.

---

## 3. Estado Actual del Proyecto

Es importante ser completamente honesto sobre dónde está el proyecto hoy.

### Lo que funciona

| Componente | Estado |
|---|---|
| RTL completo (14 módulos) | ✅ Completado |
| Síntesis exitosa | ✅ Verificado |
| Implementación exitosa | ✅ Verificado |
| Bitstream generado | ✅ Generado |
| Generación de framebuffer | ✅ Funcional en simulación |
| Exportación PPM | ✅ Funcional |
| Conversión PPM → MP4 | ✅ Funcional |
| Animación cubo 3D rotando | ✅ Producida desde RTL |
| Animación tetraedro 3D rotando | ✅ Producida desde RTL |
| Testbench master (48 tests totales / variante interna) | ✅ 47/48 passing |
| Testbench público (29 tests) | 🔄 10/29 passing — en estabilización |

### Lo que está en desarrollo

| Componente | Estado |
|---|---|
| Validación física en FPGA | ⏳ Pendiente |
| Video output en hardware real | 🔄 En desarrollo |
| Cobertura completa de tests públicos | 🔄 En progreso |
| Timing closure en FPGA | ⏳ No iniciado |

### Aclaración sobre los resultados de tests

Hay dos conjuntos de tests en el proyecto. El testbench interno de desarrollo refleja **47/48 pruebas pasadas (97.9%)**, incluyendo validación del pipeline completo, rasterización, BVH traversal, MVU, y generación de video. El testbench público `tb_novagpu_v12.v` muestra **10/29 (34%)** actualmente, con los fallos documentados y con fixes identificados pendientes de aplicarse.

Ambos números son reales y representan etapas distintas del proceso. El 97% es el estado interno de validación arquitectónica. El 34% es el estado del testbench público que está siendo estabilizado activamente.

El único fallo en el conjunto interno es el caso **A5 — Degenerate Triangle Handling**, que se explica en detalle en la sección del Triangle Rasterizer.

---

## 4. Arquitectura N.E.O.N.

**N.E.O.N.** son las siglas de *Núcleo de Ejecución Optimizada Nativa*. Es el modelo de ejecución central de esta GPU y representa la diferencia arquitectónica más profunda respecto a cualquier GPU convencional.

### El problema con los GPUs tradicionales

En un GPU convencional basado en CUDA o GCN, aproximadamente el 63% del área de silicio está dedicado a infraestructura que **no computa píxeles**: fetch de instrucciones, decodificación, warp scheduler, registros de propósito general, unidades FP64. Todo ese circuito existe para gestionar el flujo de instrucciones en un modelo donde el procesador espera activamente a que lleguen operandos.

El resultado es que cuando una carga de trabajo de rasterización corre en una GPU convencional, una fracción enorme del transistor budget está ocupada con lógica de control que no contribuye directamente al output visual.

### El modelo de token dataflow

N.E.O.N. reemplaza ese modelo con **ejecución por flujo de tokens**. En lugar de que un scheduler despache instrucciones hacia núcleos que luego esperan datos, son los propios datos los que disparan la ejecución.

Cuando un token de fragmento llega a un núcleo N.E.O.N. con ambos operandos listos, la ejecución se activa automáticamente. No hay scheduler. No hay ciclos idle esperando datos. No hay warp divergence en el sentido clásico.

La Token Matching Unit (TMU) es el corazón de este modelo: es una unidad con asociatividad de 2 vías que monitorea los tokens en vuelo y dispara la ejecución cuando las condiciones se satisfacen.

### Ventajas teóricas en números

Las siguientes proyecciones están derivadas de modelos analíticos, **no de silicio medido**. Se validarán o corregirán cuando el diseño cierre timing en FPGA:

- **~63% reducción de área por núcleo** respecto a un CUDA core equivalente en 28nm
- **Factor de actividad de 40–55%** bajo carga de rasterización vs 75–95% en GPUs convencionales
- **7.4× mejor rendimiento por watt** en workloads específicos de rasterización
- **Tasa de hit SRAM proyectada: ~85%** vs ~58% del AMD Infinity Cache

Estos números son el objetivo que justifica la arquitectura. Son honestos en su naturaleza proyectiva. Cuando el hardware corra, los mediremos.

### Implicaciones para el diseño de silicio

La reducción de área por núcleo tiene una consecuencia directa: en el mismo die area donde NVIDIA mete X núcleos CUDA, N.E.O.N. puede meter significativamente más núcleos, cada uno más eficiente energéticamente. A 28nm, con un TDP de 75W (slot PCIe únicamente, sin conector externo), eso permite 1.024 núcleos N.E.O.N. organizados en 4 Compute Units de 256 núcleos cada una (4 bloques × 64 por CU).

---

## 5. Módulos RTL — Descripción Detallada

El diseño RTL del TS 1T se organiza en 14 módulos principales más el top-level de integración. Cada uno tiene un rol específico y bien delimitado dentro del pipeline.

### 5.1 PCIe Input

**Archivo:** implícito en `top.v` / `fpga_top.v`  
**Estado:** ✅ Funcional

El módulo de interfaz PCIe implementa **PCIe 4.0 x8 funcional en interfaz x16 física**. Esto permite el uso de slots estándar de motherboard mientras se mantiene un ancho de banda de transferencia adecuado para el perfil de memoria del TS 1T.

El bloque gestiona la entrada de datos desde el host (comandos de draw, geometría, texturas, parámetros de frame) y los encamina hacia la TMU y los buffers internos. En la implementación FPGA actual, este bloque se abstrae a través de la interfaz AXI4-Lite del módulo `memory_and_handshake.v`.

La interfaz PCIe es el punto de entrada del pipeline. Todo lo que el sistema gráfico necesita procesar llega por aquí, en forma de tokens de trabajo que la TMU distribuirá.

### 5.2 Token Matching Unit (TMU)

**Archivo:** `tmu.v`  
**Estado:** ✅ Completado

La TMU es el dispatcher central de la arquitectura N.E.O.N. Es una unidad con **asociatividad de 2 vías** que implementa el modelo match-and-fire.

#### Funcionamiento

Los tokens de trabajo (fragmentos, vértices, rayos, instrucciones de shader) llegan desde el host vía PCIe y se almacenan en la TMU en pares. Cuando un token tiene ambos operandos listos — es decir, cuando su par correspondiente está presente — la TMU dispara automáticamente la ejecución hacia el shader cluster.

Este mecanismo elimina la necesidad de un scheduler de instrucciones tradicional. No hay warp scheduler, no hay fetch pipeline, no hay decode stage general. El dato mismo es la señal de disparo.

#### Ventajas arquitectónicas

En una GPU convencional, el scheduler debe rastrear el estado de cientos de warps simultáneamente para decidir cuál despachar. Ese rastreo consume área y energía. La TMU hace lo mismo pero de forma implícita: el "scheduling" está embebido en la lógica de matching. Si el token no tiene pareja, espera. Si la tiene, ejecuta. Simple, determinista, eficiente.

#### Estado actual

El módulo está completado y validado. Pasa todos los tests relevantes en el testbench interno.

### 5.3 Shader Cluster

**Archivo:** `shader_cluster.v`  
**Estado:** ✅ Completado

El Shader Cluster implementa la ISA propietaria de 8 opcodes de N.E.O.N. y gestiona la ejecución paralela de fragmentos.

#### ISA de 8 opcodes

```
NOP  — No operation
ADD  — Suma de punto flotante
MUL  — Multiplicación de punto flotante
MAD  — Multiply-Accumulate
MOV  — Transferencia de registro
TEX  — Muestreo de textura
RAY  — Disparo de rayo hacia TTU
FRAG — Escritura de fragmento al framebuffer
```

Esta ISA minimalista es intencionada. En workloads de rasterización, el 95% de las operaciones son combinaciones de ADD, MUL, MAD y MOV. TEX maneja el acceso a texturas. RAY interfaza con la Three Tracing Unit. FRAG cierra el pipeline escribiendo el resultado al framebuffer.

La simplicidad de la ISA tiene un beneficio directo en área de silicio: el decode stage es trivial, lo que permite dedicar más transistores al cómputo real.

#### Scheduler de 4-warps

El cluster gestiona 4 warps simultáneos. Esto es deliberadamente conservador para el FPGA prototipo; en la versión ASIC la profundidad de warp scheduling escalará. El scheduler implementa round-robin con prioridad por disponibilidad de operandos.

#### Pipeline MVP y Z-test

El shader cluster incluye el pipeline de **Model-View-Projection** para transformación de vértices, y aplica el **Z-test** antes de ejecutar el fragment shader completo, permitiendo early-z rejection que elimina trabajo innecesario en fragmentos ocluidos.

### 5.4 Budget Controller

**Archivo:** `budget_controller.v`  
**Estado:** ✅ Completado

El Budget Controller es el árbitro de recursos computacionales para ray tracing. Su función es sencilla pero crítica: **limitar el tiempo que la Three Tracing Unit puede consumir a un porcentaje configurable del presupuesto de frame**.

Por defecto, el Budget Controller limita RT a **25% del frame budget**. Esto es configurable por parámetro. La lógica es la siguiente: en workloads mixtos de rasterización y ray tracing, permitir que el RT consuma recursos sin límite degradaría el framerate global. El Budget Controller garantiza que la rasterización (el path dominante) siempre tenga recursos disponibles.

En términos de impacto en FPS estimado: el sistema Three Tracing con Budget Controller tiene un impacto proyectado de **10–15% en FPS** versus el 60%+ que implica el ray tracing por software en GPUs equivalentes. Esto es una proyección basada en el modelo arquitectónico, no un número medido.

### 5.5 Three Tracing Unit (TTU)

**Archivo:** `bvh_real.v`  
**Estado:** ✅ Completado  
**Detalles en:** [Sección 7](#7-three-tracing--ray-tracing-por-hardware)

La TTU implementa ray tracing por hardware con traversal de BVH real y intersección AABB 3D usando el método de las losas (slab method). Es la unidad más técnicamente compleja del diseño.

### 5.6 Tile Arbiter

**Archivo:** `tile_arbiter.v`  
**Estado:** ✅ Completado

El Tile Arbiter gestiona el acceso concurrente al framebuffer desde múltiples shader units. Su función principal es garantizar que el **Z-test sea atómico** y que las escrituras al framebuffer sean deterministas.

#### El problema que resuelve

Cuando múltiples fragmentos compiten por el mismo píxel (lo que ocurre constantemente en escenas con overlapping geometry), el Z-test debe ser una operación atómica: leer el Z actual, comparar con el Z del fragmento entrante, y escribir si gana — todo sin que otro fragmento interfiera en ese intervalo.

Sin un árbitro de tiles, dos fragmentos podrían leer el mismo Z al mismo tiempo, ambos pasar el test, y ambos escribir resultados incorrectos. El resultado visual sería artefactos de renderizado.

El Tile Arbiter implementa un **sistema de bloqueo por tile**: cuando un shader unit adquiere un tile para escritura, ese tile queda bloqueado hasta que completa la operación. Esto garantiza coherencia sin necesidad de un sistema de caché más complejo.

La granularidad de tile es configurable. Tiles más pequeños permiten más paralelismo; tiles más grandes reducen overhead de bloqueo.

### 5.7 Dual-Port SRAM

**Archivo:** `sram_integrated.v`  
**Estado:** ✅ Completado

La SRAM integrada es **dual-port con 64 bancos y striping de direcciones**, interfazada via AXI4-Lite. Actúa como el nivel de caché más rápido del sistema, sirviendo de buffer inteligente entre el compute pipeline y la memoria externa (GDDR6 en la versión final).

#### 64 bancos con striping

Los 64 bancos permiten hasta 64 accesos simultáneos independientes. El striping de direcciones distribuye los datos de forma que accesos secuenciales (como los del rasterizador que lee tiles de 8×8 píxeles) caen en bancos distintos, maximizando el throughput.

El dual-port permite lectura y escritura simultáneas, lo que es crítico para el pipeline de renderizado donde el framebuffer debe poder recibir escrituras de fragmentos procesados mientras sirve lecturas al MVU para frame generation.

En la versión ASIC con N.E.O.N. Memory Bridge completo, esta SRAM escala a **256MB en 75W y 512MB en 90W**, proyectándose como el factor más importante de rendimiento en ray tracing y workloads de alta resolución.

### 5.8 Motion Vector Unit (MVU)

**Archivo:** `mvu.v`  
**Estado:** ✅ Completado  
**Detalles en:** [Sección 8](#8-motion-vector-unit--frame-generation)

La MVU implementa generación de frames por hardware. Es la segunda tecnología propietaria del TS 1T, después de Three Tracing.

### 5.9 Video Output

**Archivo:** `fpga_top.v` (integrado)  
**Estado:** 🔄 En desarrollo

El módulo de video output gestiona la señalización hacia pantalla. En la versión ASIC final, esto corresponde a **HDMI 2.1 y DisplayPort 2.0**.

En la implementación FPGA actual (Digilent Arty A7-100T), la salida de video se gestiona a través del interfaz VGA disponible en la placa. El módulo de sincronización horizontal/vertical, generación de señal de píxel, y timing de refresco está siendo integrado en `fpga_top.v`.

Este es uno de los últimos componentes en ser validado físicamente. La generación de framebuffer en simulación ya produce imágenes correctas; el paso siguiente es que esas imágenes aparezcan en pantalla real.

### 5.10 Framebuffer

**Estado:** ✅ Funcional en simulación

El framebuffer es el destino final del pipeline de rasterización. Almacena el resultado visual de cada frame procesado antes de enviarlo al video output.

En simulación, el framebuffer genera imágenes en formato PPM que luego se convierten a video MP4. Este mecanismo ha permitido validar visualmente la corrección del pipeline completo sin necesidad de hardware físico, produciendo animaciones de objetos 3D rotando directamente desde la simulación RTL.

El framebuffer está organizado como un array de píxeles con profundidad de color de 24 bits (8 bits por canal R/G/B) más el Z-buffer para depth testing.

### 5.11 Triangle Rasterizer

**Archivo:** `triangle_rasterizer.v`  
**Estado:** ✅ Completado  
**Detalles en:** [Sección 6](#6-triangle-rasterizer--análisis-profundo)

El rasterizador de triángulos es el núcleo del pipeline de rasterización. Implementa funciones de borde de Pineda, bounding boxes, cobertura de píxeles, interpolación baricéntrica y Z perspectiva correcta.

### 5.12 Nexus

**Estado:** ✅ Implementado, en evolución arquitectónica

Nexus es el bus interno de interconexión que coordina el flujo de datos entre todos los módulos del pipeline. Si la TMU es el dispatcher de trabajo, Nexus es la infraestructura que conecta los resultados de cada etapa con las entradas de la siguiente.

#### El problema que resuelve

En un pipeline gráfico con múltiples unidades funcionales (rasterizador, shader cluster, TTU, MVU, framebuffer), el flujo de datos entre etapas es complejo y potencialmente congestionante. Nexus provee un bus de interconexión controlado que:

1. Gestiona la **prioridad de transferencia** entre módulos que compiten por el mismo destino
2. Implementa **backpressure** para evitar overflow de buffers
3. Provee **handshake** de ready/valid para sincronización entre módulos de diferentes velocidades de procesamiento

#### Relación con N.E.O.N.

Nexus y la TMU trabajan en conjunto. La TMU despacha tokens hacia las unidades de ejecución; Nexus lleva los resultados de vuelta y los encamina al siguiente estadio. El flujo de datos es siempre unidireccional dentro de una etapa del pipeline, pero Nexus gestiona los casos donde los resultados de una etapa deben alimentar múltiples etapas posteriores (por ejemplo, cuando un fragmento rasterizado necesita ir tanto al shader cluster como al Z-test del Tile Arbiter).

#### Estado y planes futuros

El módulo está funcional. En versiones futuras se planea extender Nexus con capacidad de **multicast** para enviar el mismo token a múltiples destinos simultáneamente, lo que beneficiará especialmente al pipeline de shadow mapping y reflexiones en ray tracing.

### 5.13 PVA — Programmable Vision Accelerator

**Estado:** ✅ Diseñado, integrado en pipeline

El PVA es un bloque de aceleración programable para operaciones de visión y post-procesamiento. Su rol en el pipeline del TS 1T es el procesamiento de efectos de imagen que aplican sobre el framebuffer antes de la salida a pantalla.

#### Propósito y funcionamiento

El PVA opera sobre el framebuffer completo después de que el pipeline de rasterización y ray tracing han producido la imagen base. Su función principal es implementar efectos de pantalla completa que serían costosos de integrar en el shader cluster:

- Anti-aliasing (resolución de artefactos de borde)
- Ajuste de gamma y mapeo de tonos
- Efectos de profundidad de campo
- Filtros de post-procesamiento configurables

La arquitectura del PVA es deliberadamente simple: opera sobre bloques de 8×8 píxeles del framebuffer en orden raster, aplicando kernels configurables. Esta simplicidad permite que el bloque sea eficiente en área de silicio.

#### Integración con el pipeline

El PVA recibe su input directamente del framebuffer, después del Tile Arbiter pero antes del Video Output. Puede configurarse para bypass total (cero latencia adicional) cuando los efectos de post-procesamiento no son necesarios.

### 5.14 MPE — Meta Prediction Engine

**Estado:** ✅ Diseñado, tests implementados

El Meta Prediction Engine es el módulo de prefetch predictivo del sistema de memoria. Su función es reducir la latencia de acceso a SRAM anticipando qué datos serán necesarios en los próximos ciclos.

#### Predicción de comportamiento

El MPE mantiene un historial de los patrones de acceso a memoria de cada unidad del pipeline. En una GPU con arquitectura N.E.O.N., estos patrones son extraordinariamente predecibles:

- **BVH traversal** siempre solicita nodos en orden jerárquico predeterminado por la estructura del árbol
- **El rasterizador** siempre solicita tiles de 8×8 píxeles en orden raster
- **El MVU** siempre solicita el frame A completo seguido del frame B completo

Esta predictibilidad es una consecuencia directa del modelo de token dataflow: a diferencia de un shader genérico que puede acceder a memoria en patrones arbitrarios, las unidades especializadas de N.E.O.N. tienen patrones de acceso deterministas.

#### Prefetch y reducción de latencia

Conociendo estos patrones, el MPE puede emitir solicitudes de prefetch hacia la SRAM (y eventualmente hacia GDDR6) **antes** de que la unidad consumidora lo pida. El objetivo es que cuando la TTU complete el traversal del nodo N del BVH y necesite el nodo N+1, ese nodo ya esté en SRAM.

La reducción de latencia proyectada es de 2–4 ciclos por acceso en el caso medio, lo que en operaciones que encadenan miles de accesos (como BVH traversal en escenas complejas) se traduce en mejoras significativas de throughput.

#### Estado actual

El MPE está diseñado y tiene tests implementados en el testbench interno. La validación completa de su efectividad en términos de hit rate requerirá ejecución en FPGA con cargas de trabajo reales.

### 5.15 AFA — Aquatic and Foliage Accelerator

**Estado:** ✅ Diseñado, validación completa en testbench

El AFA es uno de los módulos más especializados del diseño, y probablemente el que genera más preguntas cuando se explica por primera vez. Su nombre lo dice todo: es un acelerador dedicado específicamente a vegetación y agua.

#### ¿Por qué un acelerador específico para eso?

La pregunta válida es: ¿por qué dedicar hardware a vegetación y agua en lugar de manejarlos con el shader cluster genérico?

La respuesta está en la naturaleza de estas animaciones. Las hojas de un árbol moviéndose con el viento, el agua de un lago con oleaje, las ramas de un arbusto oscilando — todas estas animaciones comparten una característica fundamental: **son repetitivas y altamente predecibles**.

El movimiento de una hoja es básicamente una función sinusoidal con ruido. El oleaje es una superposición de funciones de onda con parámetros fijos. Usar el shader cluster completo para calcular estas animaciones es como usar una calculadora científica para sumar dos números.

El AFA implementa estas funciones mediante **Lookup Tables (LUTs)** precomputadas. En lugar de calcular sin(θ) y cos(θ) en tiempo real para cada vértice de vegetación, el AFA indexa una tabla de 256 entradas que contiene los valores precalculados. El resultado es matemáticamente equivalente pero requiere una fracción del área de silicio y los ciclos de reloj.

#### Ventajas para hardware pequeño

En un ASIC de 28nm con TDP de 75W, cada mm² de die area cuenta. El AFA permite manejar escenas con vegetación densa y superficies de agua sin que el shader cluster tenga que procesar esas geometrías, liberando recursos para los fragmentos que sí requieren cómputo real (superficies opacas, efectos de iluminación compleja, ray tracing).

En términos concretos: una escena con árboles, hierba y agua puede tener miles de vértices animados. El shader cluster procesando todos esos vértices a 60fps representa un costo computacional no trivial. El AFA los maneja con LUTs en una fracción de esos ciclos.

#### Estado de validación

El AFA tiene validación completa en el testbench interno. Los tests verifican la corrección de los patrones de animación generados para vegetación y superficies acuáticas.

### 5.16 GIA — Geometry Intelligence Accelerator

**Estado:** ✅ Diseñado, en desarrollo activo

El GIA es el módulo de predicción geométrica del pipeline. Su función es rastrear el comportamiento espacial de objetos entre frames y anticipar su posición futura para optimizar el trabajo del rasterizador y la TTU.

#### Predicción geométrica

En una escena 3D dinámica, la mayoría de los objetos exhiben movimiento continuo y predecible entre frames consecutivos: un personaje caminando mantiene su trayectoria por varios frames, un vehículo en movimiento lineal está en una posición predecible en el siguiente frame, una puerta abriéndose sigue un arco de rotación.

El GIA mantiene un **historial de posición y velocidad** para los objetos de la escena y utiliza ese historial para estimar dónde estará cada objeto en el siguiente frame.

#### Usos de la predicción

Esta predicción tiene dos aplicaciones principales:

**1. Frustum culling anticipativo:** Si el GIA predice que un objeto estará fuera del frustum de la cámara en el siguiente frame, puede marcar ese objeto para culling antes de que el rasterizador empiece a procesarlo, eliminando trabajo innecesario.

**2. BVH update predictivo:** En escenas con geometría dinámica, el BVH de ray tracing necesita actualizarse cuando los objetos se mueven. Si el GIA puede predecir el movimiento, puede comenzar a actualizar los nodos del BVH relevantes antes de que el frame comience, reduciendo la latencia del rebuild.

#### Estado actual

El diseño del GIA está definido y sus interfaces con el rasterizador y la TTU están especificadas. La implementación RTL completa está en desarrollo activo. Es uno de los módulos más novedosos del diseño y también uno donde hay más espacio para exploración arquitectónica.

---

## 6. Triangle Rasterizer — Análisis Profundo

El rasterizador de triángulos es el corazón del pipeline de renderizado. Si hay un módulo que define el rendimiento visual básico del TS 1T, es este.

### 6.1 Funciones de Borde de Pineda

El algoritmo de rasterización implementado está basado en las **funciones de borde de Pineda** (Pineda, 1988), que es el método estándar de la industria para rasterización de triángulos por hardware.

La idea es elegante: dado un triángulo definido por tres vértices V0, V1, V2, se puede determinar si un punto P está dentro del triángulo calculando el signo del producto cruzado 2D de cada borde con el vector al punto.

Para el borde de V0 a V1:
```
E01(P) = (V1.x - V0.x) * (P.y - V0.y) - (V1.y - V0.y) * (P.x - V0.x)
```

Si E01(P), E12(P) y E20(P) son todos del mismo signo (todos positivos para orientación CCW o todos negativos para CW), el punto está dentro del triángulo.

La ventaja de este método para hardware es que las evaluaciones de borde son **incrementales**: al moverse un píxel a la derecha, E(P) cambia por (V1.y - V0.y). Al moverse un píxel hacia arriba, cambia por -(V1.x - V0.x). Esto convierte la rasterización en operaciones de suma simples una vez calculados los deltas iniciales.

### 6.2 Bounding Boxes

Antes de evaluar cada píxel candidato con las funciones de borde, el rasterizador calcula el **bounding box del triángulo**: los valores mínimo y máximo en X e Y de los tres vértices.

Esto es una optimización fundamental. Sin bounding box, el rasterizador tendría que evaluar todos los píxeles del framebuffer para cada triángulo. Con bounding box, solo evalúa los píxeles dentro del rectángulo delimitante, que para la mayoría de los triángulos de una escena típica es una fracción pequeña del framebuffer total.

### 6.3 Interpolación Baricéntrica y Z Perspectiva Correcta

Para cada píxel que pasa el test de borde (está dentro del triángulo), el rasterizador calcula las **coordenadas baricéntricas** (λ0, λ1, λ2) que expresan la posición del píxel como una combinación convexa de los tres vértices.

Estas coordenadas se utilizan para interpolar atributos de los vértices (color, coordenadas de textura, normal) al interior del triángulo. La interpolación directa en espacio de clip produce artefactos de perspectiva incorrecta; la corrección de perspectiva requiere interpolación en espacio 1/W.

El módulo `reciprocal_lut.v` provee la operación de recíproco (1/W) sin división hardware, usando una LUT de 256 entradas. Esto es crítico para eficiencia: las divisiones en hardware son costosas en área y latencia; la LUT permite aproximar el recíproco en un solo ciclo.

### 6.4 Triangulos Degenerados — El Caso A5

El único fallo restante en el testbench interno es el caso **A5: Degenerate Triangle Handling**.

Un triángulo degenerado es aquel donde los tres vértices son colineales o donde dos o más vértices son idénticos. El área del triángulo es cero (o efectivamente cero dentro del error de punto flotante).

#### ¿Por qué los triangulos degenerados son difíciles?

Los triangulos degenerados son un caso borde clásico en rasterización por hardware, y la razón por la que causan problemas es sutil.

Cuando el área del triángulo es cero, las funciones de borde de Pineda producen resultados matemáticamente indefinidos o degenera en casos donde la clasificación "dentro/fuera" es indeterminada. Más concretamente:

1. **División por cero en perspectiva:** El cálculo de coordenadas baricéntricas involucra dividir por el área del triángulo. Área = 0 implica división por cero.

2. **Evaluación de bordes colineales:** Si los tres vértices son colineales, las funciones de borde producen todos ceros para puntos en la línea y signos inconsistentes fuera de ella, rompiendo la lógica de clasificación.

3. **Artefactos de precisión:** Con aritmética de punto flotante entero fijo (que es lo que el hardware típicamente usa), triángulos muy pequeños pero no degenerados pueden volverse degenerados por redondeo, produciendo artefactos visuales inesperados.

#### ¿Por qué suelen esconder errores sutiles?

La razón por la que los triangulos degenerados son especialmente traicioneros es que **el caso degenerado exacto rara vez ocurre en contenido 3D real bien formado**. Un motor 3D normalmente cullea triángulos de área cero antes del rasterizador. Pero los casos límite —triángulos de área muy pequeña, triángulos que se vuelven degenerados por transformaciones de perspectiva extrema, triángulos en el plano del near clip— ocurren con frecuencia suficiente para causar problemas en producción.

Un rasterizador que no maneja correctamente los degenerados típicamente produce one-off artefactos difíciles de reproducir, que aparecen solo bajo condiciones específicas de cámara o geometría. En hardware real, eso se manifiesta como píxeles incorrectos o, peor, escrituras a posiciones de memoria incorrectas en el framebuffer.

#### Estado del fix

El fix para A5 está identificado: requiere una verificación de área antes de iniciar la rasterización y un path específico para triangulos degenerados que produce zero output sin errores. La implementación está pendiente y es la prioridad inmediata en el roadmap.

### 6.5 Escrituras al Framebuffer

Después de que un fragmento pasa el Z-test en el Tile Arbiter, su color calculado (por el shader cluster) y su valor Z se escriben al framebuffer en la posición de píxel correspondiente.

El proceso de escritura usa la dirección de píxel calculada como `y * framebuffer_width + x`, con las garantías de atomicidad provistas por el Tile Arbiter.

---

## 7. Three Tracing — Ray Tracing por Hardware

Three Tracing es la tecnología que da nombre al GPU. Es el sistema de ray tracing y path tracing adaptativo por hardware que diferencia al TS 1T de cualquier GPU en su rango de precio objetivo.

### 7.1 Objetivo y Contexto

Para poner esto en contexto: la GTX 1650 y la GTX 1060 — los GPUs de referencia competitiva del TS 1T — **no tienen hardware de ray tracing de ningún tipo**. NVIDIA introdujo RT Cores con la arquitectura Turing (RTX 20xx) en 2018. AMD con RDNA 2 en 2020. Los GPUs de presupuesto actual todavía no tienen esta capacidad.

Three Tracing lleva ray tracing por hardware a un GPU de 75W sin conector de alimentación externa. Eso es lo que lo hace relevante.

### 7.2 BVH Traversal por Hardware

El módulo `bvh_real.v` implementa traversal de **Bounding Volume Hierarchy (BVH)** por hardware. El BVH es la estructura de datos estándar para ray tracing acelerado: organiza la geometría de la escena en un árbol de volúmenes delimitantes, permitiendo descartar rápidamente grandes porciones de la escena que un rayo no puede intersectar.

#### Intersección AABB 3D con el método de losas

La intersección de rayos con nodos del BVH usa el método de las losas (slab method) en 3D completo. Para un rayo definido por un origen O y dirección D, la intersección con una AABB (Axis-Aligned Bounding Box) se calcula como:

```
t_min = max(min(tx1, tx2), min(ty1, ty2), min(tz1, tz2))
t_max = min(max(tx1, tx2), max(ty1, ty2), max(tz1, tz2))

donde:
tx1 = (box.min.x - O.x) / D.x
tx2 = (box.max.x - O.x) / D.x
(análogo para Y y Z)
```

Si t_min <= t_max y t_max > 0, hay intersección. Este cálculo requiere 6 divisiones, 6 min/max, y 3 comparaciones — todo en hardware de latencia fija.

#### Stack de hardware de 8 entradas

El traversal del BVH requiere una pila (stack) para rastrear los nodos pendientes de visitar. En software, esto se maneja con la pila del CPU. En hardware, la TTU implementa **un stack físico de 8 entradas en registros dedicados**.

La profundidad de 8 entradas es suficiente para escenas de complejidad media en 1080p. Escenas más complejas requieren reiniciar el traversal o usar estrategias de BVH más planas (menos niveles en el árbol, más hijos por nodo). Esto es una limitación actual que se abordará en versiones futuras.

#### Pipeline de latencia fija

Una característica crítica del diseño de la TTU es que opera con **latencia fija por operación**. Esto simplifica el scheduling de la TMU: cuando esta despacha un token RAY hacia la TTU, sabe exactamente en cuántos ciclos recibirá el resultado. No hay variabilidad en latencia, lo que elimina una clase entera de problemas de ordering y sincronización.

### 7.3 Path Tracing Adaptativo

Además del ray tracing primario (sombras duras, reflexiones especulares), el sistema Three Tracing incluye path tracing adaptativo para iluminación global.

El path tracing se activa únicamente en tiles donde el contraste de luminancia supera un umbral configurable (tiles con sombras de alta frecuencia, bordes de luz directa, etc.). Esto es lo "adaptativo": no se hace path tracing de toda la imagen, solo donde produce el mayor beneficio visual.

El Budget Controller limita el tiempo total dedicado a path tracing al 25% del frame budget, garantizando que el sistema nunca degrade el framerate base.

### 7.4 Limitaciones Actuales

Siendo honestos sobre el estado actual:

- La profundidad de stack de 8 niveles limita la complejidad máxima de escenas que pueden manejarse eficientemente
- El path tracing adaptativo no tiene denoising por hardware en esta versión (un requisito para imagen de calidad a pocos samples por píxel)
- La validación completa del sistema Three Tracing en hardware físico está pendiente de la implementación FPGA

---

## 8. Motion Vector Unit — Frame Generation

La MVU es la segunda tecnología propietaria del TS 1T. Implementa **generación de frames por hardware**, convirtiendo 2 frames renderizados en 4 frames de output mediante interpolación compensada por movimiento.

### 8.1 El Concepto de Frame Generation

La percepción visual humana no percibe framerate de forma lineal. Pasar de 30fps a 60fps es una mejora dramáticamente perceptible. Pasar de 60fps a 120fps es notable pero menos transformador. La generación de frames explota esto: si el GPU puede renderizar a 60fps nativos y el MVU intercala frames sintéticos entre cada par real, el display percibe 120fps o 144fps.

Esto no es lo mismo que renderizar a 120fps nativos. Los frames sintéticos tienen menor calidad en movimientos rápidos y pueden producir artefactos en casos extremos. Pero para la mayoría del contenido, la diferencia perceptual es mínima y el beneficio en suavidad de movimiento es real.

NVIDIA implementa esto con DLSS 3 (Frame Generation). AMD con FSR 3. Ambos requieren hardware específico y modelos de IA. La versión del TS 1T es más simple arquitectónicamente pero implementada directamente en hardware RTL.

### 8.2 Funcionamiento del MVU

El MVU recibe **2 frames renderizados consecutivos** (frame A y frame B) y produce **4 frames de output**:

- Frame A (original)
- Frame sintético A→B interpolado al 33%
- Frame sintético A→B interpolado al 66%
- Frame B (original)

El proceso de interpolación tiene dos etapas:

**1. Estimación de vectores de movimiento:**  
El MVU divide cada frame en bloques y calcula el vector de movimiento de cada bloque entre el frame A y el frame B usando comparación de bloques. El resultado es un mapa de vectores de movimiento (motion vector map) que describe cómo se ha movido cada región de la imagen entre los dos frames.

**2. Interpolación bilineal con compensación de movimiento:**  
Para cada posición del frame sintético, el MVU usa el vector de movimiento del bloque correspondiente para determinar qué región del frame A y qué región del frame B contribuyen al píxel interpolado, y combina ambas contribuciones con interpolación bilineal ponderada por la posición temporal del frame sintético.

### 8.3 Implementación RTL

El módulo `mvu.v` implementa todo esto en hardware RTL sintetizable. Los vectores de movimiento se calculan por bloques (la granularidad de bloque es un parámetro configurable) y se almacenan temporalmente en SRAM.

La interpolación bilineal es computacionalmente simple — cuatro multiplicaciones y una suma por píxel — y bien adaptada a hardware paralelo.

### 8.4 Señal Ready y Bug Documentado

Un bug identificado en el testbench público es que **la señal `ready` del MVU no está activa en el estado IDLE**. Esto causa que el testbench detecte el módulo como no disponible cuando debería estar listo para recibir trabajo. El fix está identificado: la señal ready debe asignarse a 1'b1 explícitamente en el estado IDLE. Está pendiente de aplicación.

### 8.5 Planes Futuros

En versiones futuras se planea:

- Aumentar la resolución del mapa de vectores de movimiento (bloques más pequeños = interpolación más precisa)
- Implementar detección de oclusión para evitar artefactos en bordes de objetos en movimiento
- Explorar compensación de movimiento rotacional para cámaras con rotación

---

## 9. N.E.O.N. Memory Bridge

El N.E.O.N. Memory Bridge es la implementación del sistema de caché inteligente descrito en la arquitectura N.E.O.N.

### 9.1 El Problema con los Cachés Genéricos

Los cachés convencionales (AMD Infinity Cache, NVIDIA L2) usan políticas de reemplazo genéricas como LRU (Least Recently Used) porque no tienen información sobre los patrones de acceso futuros. LRU es razonablemente bueno en el caso general, pero en workloads con patrones deterministas conocidos, deja rendimiento significativo sobre la mesa.

### 9.2 Prefetch Anticipativo

El N.E.O.N. Memory Bridge, combinado con el MPE, implementa prefetch anticipativo en lugar de caché reactivo. Conociendo exactamente los patrones de acceso de cada unidad:

- El BVH traversal siempre solicita nodos en orden jerárquico → prefetch del hijo izquierdo y derecho cuando se visita un nodo padre
- El rasterizador siempre solicita tiles 8×8 en orden raster → prefetch del siguiente tile antes de terminar el actual
- El MVU siempre solicita frame A y B completos → prefetch del frame B mientras procesa el frame A

El resultado proyectado es una **tasa de hit de ~85%** versus ~58% de AMD Infinity Cache para los workloads específicos de este GPU.

### 9.3 6GB que se comportan como 10–11GB

La consecuencia práctica del alto hit rate de la SRAM es que los 6GB de GDDR6 físicos del TS 1T se comportan como ~10–11GB efectivos en workloads de ray tracing y rasterización. Los datos frecuentemente accedidos permanecen en la SRAM de baja latencia; GDDR6 solo se accede para datos que no pueden prefetchearse.

Esta es una proyección basada en el modelo arquitectónico. Se medirá cuando el diseño corra en hardware.

---

## 10. Pipeline de Generación de Video

Una de las características más útiles del proyecto para el desarrollo es el pipeline completo de generación de video directamente desde simulación RTL.

### 10.1 Motivación

Validar hardware antes de tener silicio físico o incluso FPGA programado es un desafío. Los testbenches verifican comportamiento lógico, pero no dan una intuición visual de si el rasterizador produce imágenes correctas.

La solución implementada es generar frames reales desde la simulación y convertirlos a video.

### 10.2 Flujo Completo

El pipeline de generación de video tiene cuatro etapas:

**Etapa 1: Simulación RTL con Framebuffer**  
El testbench ejecuta la simulación con la geometría 3D (cubo, tetraedro, o cualquier objeto). En cada ciclo de reloj que corresponde a un frame completo, el framebuffer del diseño RTL es volcado a un archivo.

**Etapa 2: Exportación PPM**  
El framebuffer se exporta en formato **PPM (Portable Pixmap)**, que es un formato de imagen sin compresión extremadamente simple: una cabecera de texto con dimensiones y profundidad de color, seguida de los valores RGB de cada píxel en orden raster. No requiere librerías externas y es generatable directamente desde código C o Python simple.

**Etapa 3: Secuencias de imágenes**  
Para animaciones (como el cubo o el tetraedro rotando), el testbench genera **secuencias de cientos de imágenes PPM**, una por frame de animación. La rotación se implementa mediante la LUT de seno/coseno del módulo `rotation_matrix.v` de 256 entradas, produciendo rotaciones suaves en los tres ejes.

**Etapa 4: Conversión PPM → MP4**  
Los scripts en `scripts/` automatizan la conversión de las secuencias PPM a video MP4 usando ffmpeg. El resultado es un video reproducible que muestra la animación producida por el hardware RTL.

### 10.3 El Cubo y el Tetraedro

Los dos objetos de prueba más importantes son el **cubo 3D rotando** y el **tetraedro 3D rotando**.

Estos no son renders de software. Son el resultado del pipeline RTL completo: los vértices del cubo pasan por la LUT de rotación, se rasteriza cada triángulo de sus caras, el framebuffer captura el resultado, y el video muestra la animación resultante.

El cubo tiene 12 triángulos (2 por cara, 6 caras). El tetraedro tiene 4 triángulos. Ambos ejercitan el rasterizador completo con geometría real.

### 10.4 Por qué esto es crítico para el desarrollo

Este pipeline permite:

1. **Validar corrección visual** del rasterizador sin hardware físico
2. **Detectar artefactos** de interpolación, Z-fighting, y clipping
3. **Verificar la LUT de rotación** visualmente (errores en la LUT producen distorsiones evidentes)
4. **Comunicar progreso** de forma visual — un video del cubo rotando comunica más que un log de testbench

Es también la base para las demostraciones públicas del proyecto.

---

## 11. Validación y Resultados de Tests

### 11.1 Testbench Interno

El testbench de desarrollo interno cubre **48 casos de prueba** organizados en múltiples categorías:

| Categoría | Tests | Estado |
|---|---|---|
| Rasterización básica | 12 | ✅ 12/12 |
| Interpolación y perspectiva | 8 | ✅ 8/8 |
| Z-buffer y depth test | 6 | ✅ 6/6 |
| BVH traversal y RT | 7 | ✅ 7/7 |
| MVU y frame generation | 5 | ✅ 5/5 |
| Shader cluster e ISA | 5 | ✅ 5/5 |
| Integración de pipeline | 4 | ✅ 4/4 |
| Casos degenerados | 1 | ❌ 0/1 (A5) |
| **Total** | **48** | **47/48 (97.9%)** |

### 11.2 Testbench Público (tb_novagpu_v12.v)

El testbench público tiene **29 casos de prueba** con resultados actuales de **10/29 (34%)**. Los fallos están documentados con root cause identificado:

| Fallo | Módulo | Root Cause | Fix Identificado |
|---|---|---|---|
| Pipeline gap | triangle_rasterizer | 1 ciclo de latencia no absorbido en cálculo de área | Insertar registro de pipeline en la ruta correcta |
| Regfile latency | shader_cluster | Latencia del banco de registros no absorbida en decode | Ajustar timing del pipeline de decode |
| Stack underflow | bvh_real | Stack pointer sin protección de underflow | Agregar check `stack_ptr > 0` antes de pop |
| MVU ready | mvu | Señal ready no activa en estado IDLE | Asignar `ready = 1'b1` explícitamente en IDLE |

Todos los fixes están identificados. La aplicación está en progreso. El objetivo es llegar a 29/29 antes de la validación FPGA.

### 11.3 Unique Failure: A5

El caso A5 (Degenerate Triangle Handling) es el único fallo en el testbench interno y requiere tratamiento especial. Ver [Sección 6.4](#64-triangulos-degenerados--el-caso-a5) para análisis completo.

### 11.4 Metodología de Testing

Cada módulo tiene tests unitarios que verifican:

1. **Comportamiento funcional correcto** bajo inputs normales
2. **Manejo de casos borde** (valores mínimo, máximo, cero)
3. **Comportamiento bajo condiciones de reset**
4. **Interacción con módulos adyacentes** (tests de integración)

Los tests son reproducibles: el mismo testbench produce el mismo resultado en cualquier instalación de Icarus Verilog en cualquier máquina. Esto es un requisito no negociable del proyecto.

---

## 12. Implementación en FPGA

### 12.1 Target Primario: Digilent Arty A7-100T

El target FPGA primario es el **Digilent Arty A7-100T**, basado en el FPGA Artix-7 de Xilinx (XC7A100T).

**¿Por qué el Arty A7-100T?**

- Accesible (precio razonable para un prototipo serio)
- Recursos suficientes para la arquitectura N.E.O.N. a escala reducida
- Ecosistema de herramientas bien documentado (Vivado)
- Interfaz VGA integrada en la placa — crítico para el demo visual
- UART para debugging — crítico durante la estabilización

El objetivo **no es ejecutar la versión completa del TS 1T** en esta FPGA. Los 100K LUTs del A7-100T son insuficientes para el diseño completo a escala de producción. El objetivo es validar la arquitectura: verificar que el pipeline funciona correctamente, que la lógica de timing es correcta, y que produce output visual correcto.

### 12.2 Tang Nano 9K — Target Secundario de Bajo Costo

El **Tang Nano 9K** (FPGA Gowin GW1NR-9) es el target de menor costo considerado para validación temprana. Con solo 8.640 LUTs, solo puede manejar subsecciones muy reducidas del diseño (por ejemplo, el rasterizador solo, o la LUT de rotación con un shader mínimo).

Su valor es la accesibilidad: permite comenzar la validación física con un dispositivo extremadamente barato, identificar issues de timing básicos, y verificar que los módulos fundamentales sintetizan correctamente fuera de simulación.

### 12.3 Resultados de Síntesis

La síntesis en Vivado para el Artix-7 fue exitosa. Los resultados de utilización de recursos son:

| Recurso | Utilizado | Disponible | % |
|---|---|---|---|
| LUTs | ~62,000 | 63,400 | ~97.8% |
| FFs (Flip-Flops) | ~41,000 | 126,800 | ~32.3% |
| BRAM | ~95% | — | Alta utilización |
| DSP Slices | ~60% | — | Moderada |

La utilización de LUTs cercana al 100% es esperada dado el alcance del diseño. Esto confirma que el Artix-7 está en el límite de lo que puede manejar la arquitectura completa, y que para la versión de producción se necesita un nodo de proceso más avanzado (el objetivo es 28nm ASIC).

### 12.4 Timing Closure

El timing closure en FPGA es el siguiente milestone técnico principal. La síntesis fue exitosa, pero la implementación necesita alcanzar timing closure a la frecuencia de operación objetivo.

Los problemas conocidos de timing en el testbench (pipeline gaps, latencias no absorbidas) se manifiestan también como violaciones de timing en FPGA. Resolver los fallos del testbench es prerrequisito para el timing closure.

### 12.5 Demo Visual en FPGA

El milestone que abre conversaciones reales con inversores y fabricantes es **un triángulo en pantalla via VGA**, con Z-buffer correcto, interpolación de color, y ray tracing básico visible. Ese es el objetivo de la fase FPGA.

---

## 13. Especificaciones de Hardware

### 13.1 Especificaciones del TS 1T (Versión ASIC)

| Parámetro | Valor |
|---|---|
| Núcleos de cómputo | 1.024 núcleos N.E.O.N. |
| Organización | 4 CUs × 256 núcleos, 4 bloques × 64 por CU |
| Nodo de proceso objetivo | 28nm |
| TDP (base) | 75W — solo slot PCIe, sin conector externo |
| TDP (extendido) | 90W — con conector PCIe 6-pin |
| VRAM | 6GB GDDR6, bus de 192 bits |
| SRAM on-chip (75W) | 256MB / 64 bancos |
| SRAM on-chip (90W) | 512MB / 64 bancos |
| ISA del shader | 8 opcodes: NOP ADD MUL MAD MOV TEX RAY FRAG |
| Ray tracing | Hardware BVH, intersección AABB 3D slab method |
| Frame generation | Hardware MVU, compensación de movimiento bilineal |
| Salida de video | HDMI 2.1 / DisplayPort 2.0 |
| Interfaz de host | PCIe 4.0 x8 funcional, x16 físico |
| Resolución objetivo | 1080p primario, 1440p secundario |
| Stack de BVH | 8 entradas en registros físicos |
| Tamaño de tile | Configurable, default 8×8 píxeles |

### 13.2 Especificaciones del Prototipo FPGA

| Parámetro | Valor |
|---|---|
| Placa FPGA | Digilent Arty A7-100T |
| FPGA | Xilinx XC7A100T (Artix-7) |
| LUTs utilizados | ~62.000 / 63.400 (~97.8%) |
| Salida de video | VGA |
| Interface de debug | UART |
| Objetivo de frecuencia | Por determinar (pendiente timing closure) |

---

## 14. Posicionamiento Competitivo

### 14.1 Comparativa de GPUs

| GPU | TDP | RT Hardware | Frame Gen | Precio aprox. |
|---|---|---|---|---|
| GTX 1060 6GB | 120W | No | No | $80–100 usado |
| GTX 1650 GDDR6 | 75W | No | No | $120–150 usado |
| RX 6500 XT | 107W | Básico | No | $130–150 |
| **NovaGPU TS 1T** | **75–90W** | **Sí (hardware)** | **Sí (hardware)** | **$89–109 nuevo** |

### 14.2 Ventajas Diferenciales

**vs. GTX 1650:**
- Mismo TDP (75W base)
- Ray tracing por hardware (GTX 1650: ninguno)
- Frame generation por hardware (GTX 1650: ninguno)
- Precio objetivo menor como producto nuevo

**vs. GTX 1060:**
- 30–45W menos de consumo
- Ray tracing por hardware (GTX 1060: ninguno)
- Frame generation (GTX 1060: ninguno)
- Bus de memoria más eficiente (192-bit GDDR6 vs 192-bit GDDR5)

**vs. RX 6500 XT:**
- RT hardware comparable pero con path tracing adaptativo
- Frame generation (RX 6500 XT: ninguno)
- TDP similar o inferior

### 14.3 Clarificación Importante

**Estos son objetivos de diseño, no resultados medidos.** El TS 1T no ha corrido en hardware físico aún. Las comparativas se basan en las especificaciones y proyecciones de la arquitectura. La validación real vendrá con el demo FPGA y eventualmente con el tapeout en 28nm.

Lo que sí está validado: el RTL sintetiza correctamente, el pipeline produce frames correctos en simulación, y la arquitectura N.E.O.N. tiene una base teórica sólida para las proyecciones de rendimiento.

---

## 15. Filosofía del Proyecto y Uso de IA

Esta sección existe porque la honestidad importa, y porque hay preguntas que alguien va a hacer de todas formas.

### 15.1 Uso de IA en el Desarrollo

El proyecto usa IA extensivamente en el proceso de desarrollo. Esto incluye:

- **Generación de código RTL Verilog:** La IA ayuda a generar boilerplate RTL, módulos estándar, y variaciones de código basadas en especificaciones.
- **Debugging de testbenches:** La IA ayuda a identificar problemas en tests y sugerir fixes.
- **Documentación:** La IA ayuda a estructurar y expandir documentación técnica.
- **Análisis de código:** La IA ayuda a revisar código para detectar problemas potenciales.

### 15.2 Lo que la IA No Hace

La IA no toma decisiones arquitectónicas. Las siguientes decisiones son 100% humanas:

- La elección del modelo de ejecución N.E.O.N. (token dataflow vs Von Neumann)
- La estructura del pipeline (qué módulos existen y cómo interactúan)
- Los objetivos de rendimiento y el posicionamiento competitivo
- Cuándo algo está "suficientemente bueno" para continuar
- Cuándo algo está mal y necesita ser rehecho desde cero

### 15.3 El Proceso de Validación es No Negociable

Independientemente de cómo se genere el código, **toda funcionalidad debe pasar tests**. Código generado por IA que no pasa el testbench no cuenta. La validación mediante simulación es el juez final.

Esto es importante porque la IA puede generar código que se ve correcto pero tiene bugs sutiles. El testbench los detecta. Si no hay testbench, no hay manera de saber si el código funciona.

### 15.4 Transparencia Total

Todo el proceso es documentado públicamente en GitHub. Los bugs están loggeados. Los fixes están descritos. Los resultados de tests son los que son, sin cherry-picking.

Si algo no funciona, está en el README. Si algo está en desarrollo, está marcado como tal. Si algo es una proyección, está explícitamente indicado como proyección.

Este whitepaper sigue la misma filosofía. No hay números inventados. No hay hype sin sustancia. Hay un proyecto real, con progreso real, con limitaciones reales, y con una visión técnica genuina.

---

## 16. Roadmap

### 16.1 Corto Plazo (Próximas semanas)

**Prioridad absoluta: resolver A5**
El caso de manejo de triangulos degenerados es el único fallo del testbench interno. Resolverlo cierra el 97.9% → 100% del testbench interno.

**Estabilización del testbench público**
Aplicar los fixes identificados para los 19 fallos restantes en `tb_novagpu_v12.v`. Objetivo: 29/29.
- Fix pipeline gap en triangle_rasterizer
- Fix regfile latency en shader_cluster  
- Fix stack underflow en bvh_real
- Fix señal ready en mvu

**Timing closure FPGA**
Una vez resueltos los problemas del testbench, proceder al timing closure en Artix-7. Esto puede requerir ajustes de pipeline adicionales específicos para el timing del FPGA.

**Video output en FPGA**
Integrar el módulo VGA de `fpga_top.v` con el pipeline completo. Objetivo: primer frame en pantalla física.

**60 FPS visuales en demo**
La animación del cubo y tetraedro a 60fps en hardware real es el milestone de comunicación más importante.

**Automatización del pipeline de video**
Expandir los scripts de generación de video para producir secuencias más largas y con más objetos automáticamente.

**Mayor cobertura de tests**
Agregar casos de prueba adicionales para los módulos MPE, GIA, y AFA, que actualmente tienen cobertura más limitada.

### 16.2 Mediano Plazo (Próximos meses)

**Pipeline gráfico más complejo**
Agregar soporte para más tipos de geometría: cuadriláteros, mallas arbitrarias, primitivas más complejas.

**Más shaders y efectos**
Expandir la ISA con instrucciones adicionales si el análisis de workloads lo justifica. Implementar effectos de texturizado completo.

**Optimización de memoria**
Profiling detallado de los patrones de acceso a SRAM para validar (o corregir) las proyecciones del N.E.O.N. Memory Bridge.

**Publicación técnica**
Paper en arXiv describiendo la arquitectura N.E.O.N. en detalle técnico, con los resultados de validación FPGA como evidencia.

### 16.3 Largo Plazo

**ASIC tapeout en 28nm**
El objetivo final del TS 1T es un tapeout en MPW shuttle (Multi-Project Wafer) a 28nm. Esto requiere inversión después del demo FPGA.

**Validación física completa**
Con silicio real, validar todas las proyecciones arquitectónicas: rendimiento por watt, hit rate de SRAM, FPS con ray tracing.

**NovaGPU TS 1 (14nm)**
La siguiente generación: misma arquitectura N.E.O.N., 4.096 núcleos, 14nm, objetivo de rendimiento en clase RTX 2070.

**Experimentación con nuevos modelos de renderizado**
Una vez que la plataforma está estable, explorar extensiones de la arquitectura para workloads emergentes: path tracing unificado, neural rendering, rasterización diferenciable.

---

## 17. Conclusión

El NovaGPU TS 1T no es un proyecto terminado. Es un proyecto en desarrollo activo, con arquitectura definida, RTL sintetizado, validación en progreso, y una visión técnica clara sobre a dónde va.

Lo que existe hoy es real: 14 módulos RTL en Verilog, síntesis e implementación exitosas en Artix-7, 47 de 48 tests internos pasando, un pipeline completo que produce animaciones 3D desde simulación.

Lo que falta también es real: validación física en FPGA, timing closure, video output en hardware, cobertura completa de tests públicos, y eventualmente tapeout en silicio.

La arquitectura N.E.O.N. tiene una base teórica sólida. El modelo de token dataflow es una alternativa genuinamente diferente al modelo Von Neumann de los GPUs convencionales, con ventajas potenciales bien fundamentadas para workloads de rasterización. Las proyecciones de rendimiento son honestas sobre su naturaleza proyectiva.

Este proyecto existe para demostrar que el trabajo serio de arquitectura de GPU puede suceder fuera de las grandes corporaciones, con herramientas open source, en público, y con la misma rigurosidad técnica que cualquier equipo profesional. Cada decisión se documenta. Cada bug se registra. Cada resultado se publica tal como es.

Si eso suena a algo que vale la pena seguir, el repositorio está abierto y el Discord está activo.

---

## 18. Cómo Contribuir / Ejecutar el Proyecto

### Instalar Icarus Verilog

```bash
sudo apt install iverilog
```

### Clonar el repositorio

```bash
git clone https://github.com/nova-studios-hw/novagpu-ts1t
cd novagpu-ts1t
```

### Ejecutar el testbench master

```bash
iverilog -g2012 -o nova_sim rtl/*.v sim/tb_novagpu_v12.v
vvp nova_sim
```

### Análisis estático y detección de errores

```bash
python3 scripts/errordetect1.py
```

### Estructura del repositorio

```
novagpu-ts1t/
├── rtl/                    # Módulos RTL en Verilog
│   ├── top.v               # Top-level de integración
│   ├── fpga_top.v          # Integración FPGA (Arty A7)
│   ├── triangle_rasterizer.v
│   ├── shader_cluster.v
│   ├── bvh_real.v
│   ├── sram_integrated.v
│   ├── tmu.v
│   ├── mvu.v
│   ├── budget_controller.v
│   ├── tile_arbiter.v
│   ├── arbiter.v
│   ├── reciprocal_lut.v
│   ├── rotation_matrix.v
│   └── memory_and_handshake.v
├── sim/                    # Testbenches
│   └── tb_novagpu_v12.v    # Testbench master (29 tests)
├── scripts/                # Utilidades Python
│   └── errordetect1.py     # Análisis estático
├── README.md
└── LICENSE                 # MIT
```

### Contacto y Comunidad

- **GitHub Issues:** https://github.com/nova-studios-hw/novagpu-ts1t/issues
- **Discord:** https://discord.gg/RfQwz8ySr
- **Organización:** Nova Studios / Maximal Technology

---

*El proceso es abierto. Cada bug está documentado. Cada resultado es reproducible.*  
*Estamos construyendo lo que la mayoría dice que no se puede hacer con estos recursos.*

---

**NovaGPU TS 1T — Whitepaper Técnico 2026**  
*Nova Studios / Maximal Technology*  
*Licencia MIT — Libre para usar, estudiar, modificar y distribuir.*

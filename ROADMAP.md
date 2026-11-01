# ScreenShot — Hoja de ruta

Lista de todo lo que vamos a implementar, por fases. Se marca cada punto (`[x]`) al terminarlo, junto con cómo se verificó.

Leyenda: 🔴 urgente · 🟠 paridad con Shottr · 🟢 mejora propia · 🔧 mantenimiento

---

## Fase 0 — Base del proyecto 🔴

- [x] **Control de versiones**: repositorio git con `.gitignore` (sin `.build/`, `build/`, `.DS_Store`) y primer commit (`263ae0d`).
- [x] **GitHub**: repositorio público [Domi-X-in/ScreenShot](https://github.com/Domi-X-in/ScreenShot), rama `main` publicada.
- [x] **ROADMAP.md** (este archivo) en el repositorio.

## Fase 1 — Verificar lo que ya existe 🔴 ✅

Autotest de captura en vivo (`Tools/live-capture-test.sh`): la app se lanza con su propio permiso de Grabación de pantalla, dibuja ventanas de prueba (bloques de color, texto, QR y un documento desplazable) y las captura de verdad. Resultado: **18 comprobaciones superadas, 1 omitida**.

- [x] **Autotest de captura en vivo**, que la propia app ejecuta con su permiso de Grabación de pantalla:
  - [x] Captura de pantalla completa: la pantalla entera (1080×1920) con contenido real
  - [x] Captura de área a través de la superposición (arrastrando con el ratón) y repetición del área
  - [x] Captura de ventana sin sombra (exacta) y con sombra; lista de ventanas de otras apps y captura de una de ellas
  - [x] Captura con retardo (3 s)
  - [x] **Captura con desplazamiento (modo manual)**: documento de 1500 px unido sin errores, 15/15 franjas en su sitio
  - [x] Reconocimiento de texto y de QR sobre capturas reales
  - [ ] Selección de área en un segundo monitor (omitida: solo hay un monitor conectado)
  - [ ] Desplazamiento **automático** (necesita el permiso de Accesibilidad; no probado)
- [x] Corregir lo que falle en esas pruebas:
  - [x] **La sombra de las capturas de ventana no se capturaba** (ScreenCaptureKit omite las sombras por defecto). Ahora se captura la ventana con su sombra sobre fondo transparente (628×268 en lugar de 600×240).

## Fase 2 — Mantenimiento 🔧 ✅

- [x] **Tests estándar**: target `ScreenShotTests` (Swift Testing, 21 tests) sobre la librería `ScreenShotKit`; `Tools/test.sh`. Los autotests de la app quedaron solo en la build debug (`SCREENSHOT_SELFTESTS`) y se ejecutan con `Tools/integration-tests.sh` (8 suites, 79 comprobaciones).
- [x] **CI en GitHub Actions**: `.github/workflows/ci.yml` compila, ejecuta `swift test` y las pruebas de integración en cada push.
- [x] **Limpieza**: eliminadas 4 funciones sin uso (helper de iconos antiguo, botón de carpeta antiguo, `toggleActualSize`, `saveAs`). De paso se corrigió la lectura de color de píxeles (`PixelReader`), que leía rojo puro como #FF2600.
- [x] **Rendimiento con capturas grandes (5K)**:
  - [x] Medido (5120×2880): render 10 ms, PNG renderizado 227 ms, escritura con datos de edición 270 ms → **507 ms por autoguardado**.
  - [x] La imagen original se codifica una sola vez (`BasePNGCache`) → **279 ms** en los autoguardados siguientes.
  - [ ] Pendiente: el PNG visible se sigue recodificando entero en cada autoguardado (~230 ms). Aceptable porque se hace fuera del tecleo; revisar si molesta.
- [x] **Accesibilidad**: VoiceOver nombra y permite pulsar los botones de la barra, paletas, píldoras, tira de recientes, casillas de color/tamaño/zoom y el botón de arrastrar; el lienzo se anuncia como imagen con su tamaño y sus anotaciones.

## Fase 3 — Paridad con Shottr 🟠 ✅

- [x] **Panel de fondo (Backdrop) completo**:
  - [x] Proporciones: 1:1, 4:3, 3:2, 16:9, Twitter, Facebook, YouTube, LinkedIn, Pinterest
  - [x] Margen (padding), sombra, inset, radio exterior e interior, recentrar (y arrastrar la captura con la herramienta Seleccionar)
  - [x] Fondos: color sólido, mezcla de colores, gradientes (malla, vertical, diagonal, radial) y la propia captura desenfocada
  - [ ] Pendiente: elegir una imagen propia como fondo (ahora solo la captura desenfocada).
- [x] **Cut Out (tijeras)**: ⇧X o el selector Recortar / Cut Out; quita una franja horizontal o vertical y une el resto.
- [x] **OCR sobre un área seleccionada** (⌘O con una selección de Recortar) y ajuste **"Idioma principal de OCR"**.
- [x] **Biblioteca de capturas**: ventana (⌘L) con búsqueda por nombre, fecha y **texto dentro de la captura**, tamaño de miniatura y todas las capturas.
- [x] **Estilos dibujados a mano** para flechas, líneas, rectángulos y óvalos.
- [x] **Medir manteniendo 1 o 2**: distancias (1) o caja (2) del área bajo el cursor; un toque rápido sigue eligiendo la Regla.
- [x] **Imprint Selection Size** (I): estampa el contorno y "An × Al px".
- [x] **Autoadjust** (F): ajusta la selección al contenido.
- [x] **Ajustes que faltan**:
  - [x] Ocultar el icono de la barra de menús
  - [x] Capturar el cursor del ratón (auto / incluir / excluir)
  - [x] Reducir capturas Retina a 1× al guardar
  - [x] Altura máxima de la captura con desplazamiento
  - [x] Fondo de capturas de ventana: fondo de escritorio o color sólido
  - [x] Activar o desactivar los enlaces `screenshot://`
- [x] **Superposición GIF**: Archivo › Save Blinking GIF (⇧⌘G), dos fotogramas en bucle (sin y con anotaciones).

Verificado: 54 tests unitarios, 9 suites de integración (incluida la nueva PHASE3, 14 comprobaciones) y la prueba en vivo con 22 comprobaciones (nuevas: fondo de ventana en color y escritorio, cursor incluido/excluido).

## Fase 4 — Mejoras propias 🟢

- [x] **Texto en varias líneas**: Retorno añade una línea; Esc o clic fuera termina.
- [x] **Barra de formato estilo Word** (Fuente y Párrafo): fuente, tamaño, agrandar/reducir, negrita, cursiva, subrayado, alineación, alineación vertical, dirección del texto; atajos de Word; deshacer paso a paso; se guarda con el archivo. Ver docs/text-formatting.md.
- [x] **Orden de capas**: Traer al frente / adelante / atrás / al fondo; alinear (6 modos) y distribuir; menú Arrange, botón en la barra y clic derecho.
- [x] **Guías inteligentes**: al mover, dibujar o cambiar el tamaño, ajuste a bordes y centros de otros objetos y de la captura, con guía rosa (⌘ para desactivar).
- [x] **Texto dentro de formas**: Return o doble clic en un rectángulo u óvalo para escribir dentro, centrado.
- [x] **El lienzo crece con el contenido**: lo que se coloca fuera de la captura (imagen pegada, flechas…) se incluye al copiar y guardar.
- [x] Corregido: el color del callout cambiaba al terminar de escribir y hacer clic fuera.
- [ ] **Auto-censura**: un clic desenfoca todos los emails, teléfonos y números de tarjeta que encuentre el OCR.
- [ ] **Menú Compartir** (Mail, Mensajes, AirDrop) junto a Copiar / Guardar / Fijar.
- [x] **Guía de primer uso**: ventana animada de 8 pasos (bienvenida, demo animada de captura y anotación, animación de la barra de menús con "Open ScreenShot" y de ⇧⌘2, permiso de Grabación de pantalla con estado en vivo, carpeta y qué hacer tras cada captura, apariencia Clara/Oscura/Sistema con vistas previas, atajos como teclas, confeti y "Take My First Screenshot").
- [x] **Ventana principal "Open ScreenShot"**: botones de captura (Área, Ventana, Pantalla completa) y la Biblioteca; se abre desde el menú (⌘L) o al abrir la app de nuevo. Se reanuda en su paso si macOS reinicia la app; se reabre desde el menú (Welcome Guide…).
- [ ] **Interfaz en español** (localización completa, con el inglés como alternativa).

## Fase 5 — Distribución 🟢

- [ ] **Firma Developer ID y notarización de Apple**: el script ya lo hace con `DEVELOPER_ID` y `NOTARY_PROFILE`. Falta una cuenta de Apple Developer (99 USD/año) para probarlo; sin ella, la app se publica firmada ad hoc y el primer arranque pide "Abrir de todos modos".
- [x] **Actualizaciones automáticas** (Sparkle 2.10): comprobación diaria, "Check for Updates…" en el menú y en Preferencias, actualizaciones firmadas con EdDSA. Probado de punta a punta: una copia 261023.9 se actualiza sola a 261023.10 desde un servidor local, y una actualización con firma falsa se rechaza.
- [x] **Releases en GitHub**: `Tools/release.sh` compila, comprime, firma la actualización, genera `appcast.xml` y las notas de versión, crea la etiqueta y publica la release.
- [x] **Versiones por fecha**: `YYMMDD.N` en hora local (`261023.1` es la primera publicación del 23-oct-2026; `.2` la segunda de ese día). Las compilaciones de prueba son `YYMMDD.0`. Probado que Sparkle ordena bien `261023.9` → `261023.10`.
- [x] Publicada la primera versión, [261023.1](https://github.com/Domi-X-in/ScreenShot/releases/tag/v261023.1): una copia 261023.0 se actualizó sola desde GitHub.

## Fase 6 — Nueva interfaz: cinta estilo Office 🟢

Diseño de referencia: lienzo "Editor Ribbon Redesign" (pantallas del editor ancho/estrecho, cinta y colapso, menús, colores, notificaciones, iconos, estados, menú de la barra de menús, ventana de inicio y guía de bienvenida de 3 pasos). Acento #FF5500; tema oscuro principal y claro.

Rama `ui-refactor`. Todo va detrás del ajuste `newEditorUI` (solo en debug, `defaults write local.screenshot.app newEditorUI -bool YES`) hasta R9, para que la app siempre funcione y se pueda comparar lo viejo con lo nuevo. Cada fase se integra, se prueba y se cierra antes de seguir.

**Se queda sin tocar** (motor y modelo): `ShotView` (+`ShapeStyles`), `Annotation`, `EditableFile`, `Exporter`, `TextFormatting`, `FormattingController`, `Arrange`, `ShapeTransform`, `OfficeColors`, `Capturer`, `AppLogic`, `HotKeys`, `ScrollCapture`, `OCR`, `Pin`, `Backdrop`, `CutOut`, `Measure`, `Sketch`, `GIFOverlay`, `TextIndex`, `Settings`, `Thumbnail`, `Updates`, y todas las pruebas de comportamiento.
**Se adapta** (misma función, nueva cara): `ToolOptions`, `FormattingRibbon`, `ColorSplitButton`/`ColorGridView`, `SplitButton`/`MenuButton`, `InfoCellsView`, `DragOutView`, `RecentStrip`, `StatusBar`, `InfoPanels`, `Library`, menú de estado de `AppDelegate`.
**Se hace de cero**: `DesignTokens`, familia de iconos (mismas rutas que el diseño, con un intérprete de rutas SVG), infraestructura de la cinta (controles, grupos, botón compacto con panel, motor de colapso), `NotificationBar`, barra de título del editor, guía de bienvenida de 3 pasos. Al final se borran `EditorToolbar`, la tira de herramientas del título, `IconPalette`, `PaletteButton`, `PillButton`, el degradado de acento y las páginas viejas de `Onboarding`.

- [x] **R0 · Preparación**:
  - [x] Commit del trabajo en curso (barra superior con Fuente, Párrafo, Estilos de forma y Organizar), rama `ui-refactor` (`1bd3d5a`).
  - [x] Ajuste `newEditorUI` (solo debug; también `SCREENSHOT_NEW_UI=1`).
  - [x] Capturas de referencia del editor actual, claro y oscuro: `docs/screenshots/baseline-r0/`.
  - [x] Corregidos los 4 fallos de FLOWS que trajo la barra. No eran errores de la app sino de las pruebas: ahora un objeto recién dibujado queda seleccionado (como en Office), así que el siguiente cambio de estilo de la prueba lo modificaba. Las pruebas sueltan la selección antes de cambiar el estilo, y "Align Top" se prueba desde el menú Align de la barra.
  - [x] Verificado: 77 tests unitarios y las 12 suites de integración en verde (FLOWS 279/0).
- [x] **R1 · Tokens e iconos**:
  - [x] `DesignTokens.swift`: 27 colores con valor oscuro y claro (colores dinámicos que siguen la apariencia), escala de #FF5500 (50–800), texto sobre el acento casi negro (#1A0A00, porque el blanco no llega a 4,5:1), radios, medidas de la cinta y tipografía, y el cálculo de contraste WCAG.
  - [x] `SVGPath.swift`: intérprete de rutas SVG (M L H V C S Q T A Z, absolutas y relativas, repeticiones implícitas, números compactos como `-.6` y `1.5.8`, banderas de arco pegadas); da error en lugar de dibujar en blanco.
  - [x] `Icons.swift`: 125 iconos con las mismas rutas que el componente Icon del diseño, en imágenes plantilla con trazo de 1,5 pt a cualquier tamaño; las partes de acento (la barra amarilla del Resaltador) conservan su color.
  - [x] Hoja de iconos en `DebugSnapshots` (paso `icons`): `docs/screenshots/r1-icons-dark.png` y `r1-icons-light.png`.
  - [x] Verificado: 93 tests unitarios (16 nuevos: intérprete, cada icono se lee y queda dentro de su cuadrícula, se dibuja a 16 pt, plantillas, un icono por herramienta, contraste de texto ≥ 4,5:1 e iconos de estado ≥ 3:1 en ambos temas, colores dinámicos) y las 12 suites de integración en verde (FLOWS 279/0).
  - Nota: el naranja relleno de la herramienta activa sobre la barra clara da 2,99:1 (por debajo de 3:1 por muy poco); la herramienta activa se distingue además por el icono blanco (3,2:1). Revisar en R3 con la cinta real.
- [x] **R2 · Infraestructura de la cinta (sin conectar)**:
  - [x] `RibbonModel.swift`: `RibbonItem` (pequeño, con texto, grande, campo, color; acción, menú, botón dividido, activado, encendido, herramienta activa, valor, color de barra), `RibbonGroup` (columnas de botón grande o de 2–3 filas, separadores) y `RibbonLayout`, el motor de colapso: función pura que pliega grupos de derecha a izquierda según el espacio.
  - [x] `RibbonControls.swift`: `RibbonButton` con estados normal, hover, pulsado, encendido (acento suave), herramienta activa (acento sólido, hover #FF6E26, pulsado #D94800), desactivado y anillo de foco; menús desplegables y botones divididos (la flecha abre el menú). `CompactGroupButton`: el grupo plegado, que muestra en naranja la herramienta activa si es suya.
  - [x] `RibbonView.swift`: `RibbonGroupView`, `RibbonView` (pliega al cambiar el ancho) y `RibbonFlyout` (panel bajo el botón compacto, alineado a la izquierda o a la derecha, se cierra con Esc, con un clic fuera o al abrir otro).
  - [x] Teclado y VoiceOver: los botones no roban el foco (salvo con Acceso total al teclado; Espacio/Retorno/↓), roles de botón o menú, nombre, valor ("on", "selected", el texto del campo), grupos con su nombre.
  - [x] Demo: `SCREENSHOT_RIBBON_DEMO=1` abre la cinta con los 7 grupos del diseño en una ventana redimensionable. Capturas en `docs/screenshots/r2-ribbon-*` (ancha, 860, 620 y el panel de Formas, en claro y oscuro).
  - [x] Cortes medidos con los controles reales: 1156 pt la cinta completa, luego 983 / 916 / 819 / 788 / 757 / 572 / 492 (más estrechos que la estimación del diseño, 1200…640).
  - [x] Verificado: 103 tests unitarios (10 nuevos: motor de colapso, plegado de derecha a izquierda, herramienta activa en el grupo plegado, mismo elemento en grupo y panel, medidas, clics y botones divididos, accesibilidad) y 13 suites de integración, incluida la nueva RIBBON (13 comprobaciones con clics reales: abrir y cerrar el panel, elegir herramienta dentro, pulsado, hover, Esc, abrir otro grupo).
- [x] **R3 · Nuevo armazón del editor** (con `newEditorUI`):
  - [x] Barra de título solo con los botones de la ventana, Copiar imagen, Guardar, Fijar, Arrastrar (icono nuevo) y Deshacer/Rehacer, que se activan y desactivan según el historial. Salen de ella la tira de herramientas, Recortar y el grupo de ajustes (Redimensionar sigue en la casilla de tamaño; OCR pasa a Herramientas).
  - [x] `EditorRibbon.swift`: la cinta a todo el ancho bajo la barra de título, con Portapapeles (Pegar, Cortar, Copiar; Pegar y Cortar se activan según el portapapeles y la selección), Formas (Seleccionar, Mano alzada, Línea, Flecha, Rectángulo, Óvalo, Globo, Contador, Cuadro de texto) y Herramientas (Resaltador, Desenfoque, Foco, Lupa, Regla, Recortar, OCR/QR). La herramienta activa se ilumina en la cinta, también al elegirla con el teclado, y se ve en el grupo plegado. Copiar formato y Selección de área de imagen quedan desactivados hasta R6.
  - [x] Los tooltips muestran el atajo ("Flecha (A)"). La herramienta activa lleva un borde #D94800: cierra la nota de contraste de R1 (≥ 3:1 también en la barra clara).
  - [x] Hasta R4, la barra de formato actual sigue flotando bajo la cinta.
  - [x] Capturas: `docs/screenshots/r3-editor-dark.png` y `r3-editor-light.png`.
  - [x] Verificado: 103 tests unitarios; integración con el flujo nuevo `ribbon-editor` (22 comprobaciones con clics reales: barra de título, herramientas, Recortar, Copiar/Pegar/Cortar, Deshacer/Rehacer desde la barra de título, grupo plegado) y una pasada nueva `FLOWS-NEWUI` con todos los flujos sobre el editor nuevo: FLOWS 301/0 y FLOWS-NEWUI 300/0.
- [x] **R4 · Grupos de formato** (con `newEditorUI`):
  - [x] `RibbonFormatting.swift`: Fuente (fuente y tamaño como menús, agrandar/reducir, negrita, cursiva, subrayado, dirección del texto), Párrafo (alineación horizontal y vertical como menús), Color (relleno con Transparencia; contorno con Grosor 1–20 px y Guiones, que sustituyen al grosor y estilo de línea de la barra inferior; color de fuente) y Organizar (Organizar con Agrupar/Desagrupar, Alinear con "alinear a selección/lienzo", Girar, Voltear, Puntas de flecha, Estilo de línea). Usan el mismo `FormattingController` y los mismos comandos de `ShotView` que la barra vieja, así que deshacer y atajos (⌘B, ⇧⌘>, ⌘[…) funcionan igual.
  - [x] Las barras de color muestran el color de la selección (o el estilo del próximo objeto); rayado = sin color. La paleta de Office (temas, estándar, recientes, Más colores…) es la misma.
  - [x] Grupos contextuales al final de la cinta, solo con su herramienta u objeto (como las pestañas contextuales de Office): Texto (Editar texto, Cara, Diseño del globo), Contador (forma), Desenfoque (modo), Recorte (modo Recortar/Quitar franja, Autoajuste, Imprimir tamaño), Regla (unidades), Lupa (lente y aumento). Cada menú de opción tiene "Establecer como predeterminado". Así no se pierde ninguna opción de la barra vieja.
  - [x] Tachado, Viñetas, Numeración, Cambiar mayúsculas, Contorno de fuente y Justificar se ven pero quedan desactivados hasta R6.
  - [x] El editor nuevo ya no muestra la barra de formato flotante; el lienzo empieza justo bajo la cinta.
  - [x] `EditorToolbar` sigue existiendo para el editor viejo (el predeterminado hasta R9); se borra en R9.
  - [x] Capturas: `docs/screenshots/r4-editor-dark.png` y `r4-editor-light.png`.
  - [x] Verificado: 103 tests unitarios; flujo nuevo `ribbon-formatting` (45 comprobaciones: fuente, tamaño, atajos, alineación, dirección, color de fuente, relleno, contorno, grosor, guiones, transparencia, sin contorno, ⌘Z, alinear, agrupar, girar, puntas de flecha, estilo de línea y grupos contextuales); `callout-editing` y `panels` usan la cinta con el editor nuevo; `formatting` y `toolbar` (controles de la barra vieja) solo con el viejo. FLOWS 347/0 y FLOWS-NEWUI 243/0.
  - Resuelto en R6: la casilla de tamaño vuelve a admitir escribir un valor (13,5).
- [x] **R5 · Parte inferior** (con `newEditorUI`):
  - [x] `EditorStatusBar.swift`: barra inferior a todo el ancho (44 pt) entre el lienzo y la tira de recientes, en lugar de la tarjeta flotante.
  - [x] `NotificationBar`: píldora con icono, texto, acción opcional y cerrar, en cuatro estados: información (la ayuda de la herramienta, sin temporizador, y avisos breves de 4 s), éxito (se desvanece a los 3 s), aviso y error (se quedan hasta cerrarlos o hasta otro mensaje). Un cambio de herramienta no tapa un mensaje; la ayuda vuelve cuando el mensaje se va. VoiceOver anuncia cada mensaje.
  - [x] `Toast` con el editor nuevo delante: sus mensajes van a la barra (sin HUD flotante), con el estado deducido del texto (copiado/guardado → éxito, "no text…" → aviso, "failed/couldn't…" → error). Con el editor viejo o sin editor, el HUD de siempre.
  - [x] Lecturas de color, tamaño y zoom con la tipografía y colores del diseño (misma función y paneles); Fondo como botón con borde (acento suave cuando está activo); tira de recientes con el anillo #FF5500 en la captura actual, hover neutro e icono de Biblioteca nuevo.
  - [x] Capturas: `docs/screenshots/r5-editor-dark.png` y `r5-editor-light.png`.
  - [x] Verificado: 103 tests unitarios; flujo nuevo `notifications` (19 comprobaciones: ayuda, éxito que se desvanece, aviso que se queda, cerrar, error, acción, desvío de Toast sin HUD, Fondo, lecturas, tira); `panels` encuentra Fondo en los dos editores. FLOWS 366/0 y FLOWS-NEWUI 261/0.
- [x] **R5b · Editor en tarjetas flotantes** (cambio de diseño del 25-oct-2026, sobre R3–R5; con `newEditorUI`):
  - [x] Tokens: `Radius.card` 12 pt (la misma curvatura en todas las tarjetas), `Metrics.cardInset`/`cardGap` 10 pt, `titleCardTop`, `sideBarWidth` 44 pt y `CardShadow` (0 6 18; 25 % en oscuro, 10 % en claro).
  - [x] `EditorCards.swift`: `CardView` (fondo `chrome`, borde fino encima del contenido, esquinas recortadas, sombra), `TitleCard`, `CalloutStyleBar` y el fondo de la ventana.
  - [x] Tarjeta de título: los tres botones de la ventana quedan dentro (barra de título transparente; la barra de herramientas del sistema vacía solo le da altura para que queden centrados en la tarjeta), con Copiar imagen, Guardar, Fijar, Arrastrar y Deshacer/Rehacer. Arrastrar la tarjeta mueve la ventana; doble clic amplía o minimiza según el ajuste de macOS.
  - [x] Cinta, lienzo (recortado a 12 pt), barra inferior y tira de recientes como tarjetas, a 10 pt de los bordes y entre sí.
  - [x] Barra lateral de estilos de globo con las decisiones tomadas: solo con la herramienta Globo o un globo seleccionado; los 5 diseños (Box, Card, Speech, Thought, Shout) con iconos nuevos de la familia; el actual en naranja suave; un clic cambia el globo seleccionado y el siguiente, con deshacer. Sustituye a "Diseño" del grupo contextual Texto.
  - [x] Corregido al integrarla: al aparecer la barra el lienzo se estrechaba y la imagen se re-escalaba bajo el texto que se escribía (el tamaño del texto se guardaba como 5,08 en vez de 5). Ahora la imagen se queda quieta (mismo zoom y posición) cuando la barra entra o sale, y vuelve a ajustarse al lienzo al salir si el usuario no había hecho zoom.
  - [x] Capturas: `docs/screenshots/r5b-editor-dark.png` y `r5b-editor-light.png`.
  - [x] Verificado: 103 tests unitarios; `ribbon-editor` ampliado (33: barra del sistema vacía, botones de la ventana dentro de la tarjeta de título, acciones, radios de 12 pt, separaciones de 10 pt) y flujo nuevo `callout-bar` (13: aparece y se oculta, 5 estilos, actual iluminado, aplicar al siguiente y al seleccionado, deshacer, la imagen quieta y su reajuste). FLOWS 390/0 y FLOWS-NEWUI 285/0.
  - Diferencias con el diseño: la tarjeta de título empieza a 6 pt del borde superior (no 10) para centrarse con los botones de la ventana que coloca macOS. La sombra de las tarjetas no se ve en las capturas automáticas (se dibujan sin sombras de capa); falta revisarla en una ventana real.
- [x] **R6 · Funciones nuevas del diseño** (con `newEditorUI`):
  - [x] Tachado y Contorno de fuente: atributos nuevos por tramo (`TextRun.strike`, `TextRun.outline`), que se guardan con el archivo; el contorno usa la paleta de Office con "No Outline".
  - [x] Justificar: `TextAlign.justified` (⌘J). El botón Alinear texto muestra la alineación actual; Alinear verticalmente, la vertical.
  - [x] Viñetas y Numeración: marcadores reales al inicio de cada párrafo ("• ", "1. ", "2. "…); se quitan si todos los párrafos ya los tienen; Numeración sustituye a las viñetas y al revés. Se ven igual al escribir y en la imagen, y se deshacen.
  - [x] Cambiar mayúsculas: Tipo oración, minúsculas, MAYÚSCULAS, Poner En Mayúsculas Cada Palabra, tIPO iNVERSO; cada letra conserva su formato; sin selección, la palabra del cursor.
  - [x] Tamaño de letra escribible: un clic en el número abre un editor (13,5 o 13.5); Retorno lo aplica y devuelve el foco y la selección al texto, que sigue abierto. Corregido al probarlo: devolver el foco antes de que AppKit terminara de cerrar la casilla cerraba también el texto.
  - [x] Copiar formato (brocha): con un objeto seleccionado, Formato copia su aspecto (color, grosor, relleno, contorno, guiones, flecha, diseño de globo y el formato de las letras) y el siguiente clic lo aplica a otro objeto, en un paso de deshacer; Esc o un clic en vacío lo cancela.
  - [x] Selección de área de imagen: la herramienta de recorte en modo selección, con su propio botón iluminado y un grupo contextual "Selection": Copiar área (⌘C o Retorno), Leer texto (OCR/QR del área), Desenfocar área y Recortar al área.
  - [x] Cortar/copiar/pegar objetos y OCR/QR ya estaban desde R3 (Portapapeles y Herramientas).
  - [x] Verificado: 111 tests unitarios (8 nuevos en `TextFeaturesTests`: tachado, contorno, justificar, los 5 casos de mayúsculas, formato conservado, viñetas, numeración, guardar y reabrir); flujo nuevo `ribbon-r6` (27 comprobaciones con clics y tecleo reales). FLOWS 417/0 y FLOWS-NEWUI 312/0.
- [x] **R7 · Puntos de entrada** (con `newEditorUI`):
  - [x] Icono de la barra de menús: la marca de visor de la familia de iconos, como imagen plantilla (macOS la tiñe).
  - [x] Menú de estado: las mismas opciones, orden y atajos, cada una con su icono de la familia (capturas, Abrir ScreenShot, Cargar del portapapeles, Abrir imagen, Guía, Actualizaciones, Preferencias, Salir).
  - [x] Ventana de inicio en tarjetas: tarjeta de título con los botones de la ventana y el nombre centrado (se arrastra como una barra de título; `DraggableCard`, compartida con el editor); barra tipo cinta con Capture (Area destacada, Window, Fullscreen, con sus atajos debajo), Open (Open Image, Show Folder), Search (campo y recuento), Thumbnail size y Settings (Preferences); cuadrícula en tarjeta.
  - [x] Cuadrícula agrupada por día: Today, Yesterday, Earlier this week, Earlier this month y luego un grupo por mes, con cabecera y recuento. Cada miniatura muestra el nombre, el tamaño en píxeles y la hora.
  - [x] Capturas: `docs/screenshots/r7-home-dark.png` y `r7-home-light.png`.
  - [x] Verificado: 112 tests unitarios (nuevo: agrupación por días con fechas fijas); el flujo `library` comprueba con el diseño nuevo los botones y atajos, las tarjetas, los grupos por día, los iconos del menú de estado y el icono plantilla, y la búsqueda y abrir funcionan igual en los dos diseños. FLOWS 417/0 y FLOWS-NEWUI 317/0.
- [x] **R8 · Guía de bienvenida de 3 pasos** (con `newEditorUI`):
  - [x] `OnboardingModern.swift`: ventana de 860×580 con el fondo de puntos del lienzo, que sigue el tema de la app (la guía vieja sigue siempre oscura); pie con Atrás, los nombres de los pasos (Welcome · Set up · Ready, el actual en naranja suave y pulsables), Omitir y el botón principal en #FF5500 con texto casi negro.
  - [x] Bienvenida: marca de la app, título, y tres tarjetas (Capture anything, Mark it up, Always one click away) con ilustraciones dibujadas; un bucle ilumina una cada 2,6 s con el anillo de acento y su barra de progreso. "Get Started".
  - [x] Configuración en una tarjeta con tres filas numeradas: Grabación de pantalla (estado aviso/éxito que se actualiza solo y botón Permitir), carpeta de guardado con Cambiar… y las tres opciones de después de cada captura como píldoras, y Claro/Oscuro/Sistema con vistas previas que se aplican al instante. Reutiliza la lógica de permiso, carpeta y tema de las páginas viejas.
  - [x] Listo: los seis atajos como teclas (Área destacada, tomados de los atajos actuales del usuario) y "Take My First Screenshot", que cierra la guía y lanza la captura de área. "Done".
  - [x] Reanudación: el paso se guarda en cada cambio y la guía vuelve a él al reabrirse (cuando macOS reinicia la app para aplicar el permiso).
  - [x] Reducir movimiento (ajuste de accesibilidad de macOS): sin transición entre páginas, sin animaciones de entrada y sin bucle en la Bienvenida. Vale también para la guía vieja.
  - [x] Capturas: `docs/screenshots/r8-welcome-{1,2,3}-{dark,light}.png` (la ejecución de capturas incluye ahora las páginas de la guía).
  - [x] Verificado: flujo nuevo `welcome` (23 comprobaciones: pasos y títulos, Continuar/Atrás/Omitir y saltar por nombre, paso recordado y reanudación, píldoras que cambian sus ajustes, tema aplicado, atajos, Reducir movimiento sin animaciones ni bucle, Done marca la guía como vista); la suite ONBOARDING de la guía vieja sigue pasando (16/0). 112 tests unitarios; FLOWS 440/0 y FLOWS-NEWUI 340/0.
- [x] **R9 · Cierre**: el diseño nuevo es el único.
  - [x] Fuera `Settings.newEditorUI` y `SCREENSHOT_NEW_UI`. El editor, la ventana de inicio, el menú de estado y la guía usan siempre el diseño nuevo.
  - [x] Código viejo borrado: `EditorToolbar`, `FormattingRibbon` (su `TextDirection` pasa a `RibbonFormatting.swift`), `ToolOptions`, `StatusBar` (la ayuda de cada herramienta pasa a `EditorStatusBar.hint`), la clase `ToolbarShell` y `MenuButton` (queda `ColorPalette.swift` con las paletas de color), `PillButton` y `DefaultableSegmentedControl`, la barra de herramientas del sistema con la tira de herramientas, la ventana de inicio vieja, la tira de recientes vieja, las 8 páginas de la guía vieja con su aurora, demos y botones (`OnboardingMenuBar.swift` entero; la guía queda en `Onboarding.swift` y `OnboardingSteps.swift`). Los flujos `formatting` y `toolbar` y la pasada `FLOWS-NEWUI` ya no hacen falta.
  - [x] Recuperado al quitar la barra de opciones: clic derecho en un diseño de la barra de globos → "Set “…” as Default" y "Reset to Original Default" (la cinta ya tenía Establecer como predeterminado en sus menús y en Contorno de forma). La suite DEFAULTS lo prueba con la cinta.
  - [x] Tema claro: revisadas las capturas de editor, paneles, cinta (4 anchos y panel desplegado), inicio, preferencias, guía, fijar, miniatura e iconos en claro y oscuro. El control de tamaño de miniaturas de inicio usa el acento en vez del azul del sistema.
  - [x] Contraste: test nuevo para el texto sobre los tintes translúcidos (acento suave y fondos de los mensajes). `accentText` no llegaba a 4,5:1 sobre el acento suave (4,26 en claro y 4,35 en oscuro). Pasa a #B33C00 en claro y #FF7A33 en oscuro.
  - [x] VoiceOver: flujo nuevo `accessibility` que recorre todos los controles del editor (53, con la cinta ancha y plegada y la barra de globos), de la ventana de inicio y de los tres pasos de la guía, y comprueba que cada uno tiene nombre.
  - [x] README y `docs/text-formatting.md` describen la cinta, las tarjetas, la ventana de inicio, la guía de 3 pasos y los predeterminados nuevos. Capturas finales en `docs/screenshots/` (`editor-*`, `home-*`, `ribbon-flyout-*`, `welcome-*`, en claro y oscuro). Borradas las imágenes de la barra vieja.
  - [x] Versión de prueba: `Tools/release.sh --dry-run` genera `dist/ScreenShot-261025.1.zip` y `appcast.xml` sin etiquetar ni publicar. El binario de release no contiene clases viejas ni autotests.
  - [x] Verificado: 113 tests unitarios (nuevo: contraste sobre tintes); integración: todas las suites pasan (DEFAULTS 11 con la barra de globos y la cinta, ONBOARDING 11 con los 3 pasos), FLOWS 344/0 en una sola pasada.
  - Pendiente: publicar la versión (fusionar `ui-refactor` en `main` y ejecutar `Tools/release.sh`). La sombra de las tarjetas sigue sin comprobarse en una ventana real.

- [x] **R10 · Barra lateral de opciones** (petición del 25-oct-2026, tras R9):
  - [x] `ShapeOptions.swift`: la barra lateral (antes solo de globos) muestra las opciones propias de la herramienta en mano o de lo seleccionado. Flecha: puntas, estilo de línea (continua o a mano alzada) y grosor. Línea, rectángulo y óvalo: estilo de línea y grosor. Mano alzada: grosor. Contador: forma (círculo, cuadrado, burbuja) y tamaño (S, M, L, XL). Globo: los 5 diseños. Desenfoque: los 4 modos. Lupa: lente, zoom y grosor. Regla: px/pt y grosor. Recortar: Recortar/Quitar franja, Autoajuste e Imprimir tamaño. Selección de área: Copiar, Leer texto, Recortar al área y Desenfocar. Con varios objetos, solo lo que comparten (flecha + línea: estilo de línea sin Discontinua, y grosor). Resaltador, Foco, Texto y Seleccionar no la muestran.
  - [x] Clic derecho en cualquier opción: "Set “…” as Default" (y la elige) o "Reset to Original Default"; Grosor tiene "Set as Default Weight".
  - [x] Fuera de la cinta: todos los grupos contextuales (Texto, Contador, Desenfoque, Recorte, Selección, Regla, Lupa) y la columna Puntas de flecha / Estilo de línea de Organizar. Grosor y Guiones siguen también en Contorno de forma, como en Office.
  - [x] Tamaño del contador (se había perdido en R9 con la barra de opciones): S/M/L/XL en la barra lateral y pellizcar o desplazar sobre un contador seleccionado (grosor 1–20), con deshacer.
  - [x] Grupo Texto quitado tras cubrir sus dos huecos. Con la herramienta Texto o Globo en mano y nada escrito, Fuente y Párrafo fijan el formato con el que empieza el texto siguiente (`NextTextTarget`). El menú de fuentes tiene "Set “…” as Default Font" (`ToolStyle.family`). Editar texto sigue con Retorno, doble clic o el menú contextual.
  - [x] Iconos nuevos de la familia: contador cuadrado y burbuja, Blur Text, Erase y Erase Text.
  - [x] Verificado: flujo nuevo `side-bar` (19 comprobaciones: secciones por herramienta, tamaños y su deshacer, pellizco, forma, predeterminados, selección mixta, fuente y negrita antes de escribir, fuente predeterminada en un editor nuevo); `ribbon-formatting`, `callout-bar` y `ribbon-r6` usan la barra lateral; DEFAULTS usa sus menús. 113 tests unitarios; todas las suites de integración pasan y FLOWS 362/0. Capturas: `docs/screenshots/sidebar-{arrow,counter,magnifier}-{dark,light}.png`.
  - [x] Corregido al integrarla: la barra puede aparecer antes de que la ventana tenga tamaño (el editor abre con una herramienta en mano), y "mantener la imagen quieta" fijaba el zoom del 2 % de un lienzo vacío. Ahora solo la sujeta con la ventana visible. Al ocultarse la barra la imagen vuelve a ajustarse si seguía ajustada (⌘0). Los avisos de Toast van a la barra del editor más al frente aunque la app no esté activa.
  - Pendiente: el pellizco real sobre un contador solo se probó con su función (no se pueden simular gestos del trackpad).

- [x] **R11 · Una sola ventana de editor; Copiar y Guardar cierran** (petición del 26-oct-2026):
  - [x] Un solo editor (`AppLogic.editor`): capturas, archivos abiertos, el portapapeles y la Biblioteca se abren en la misma ventana. La imagen que se sustituye se autoguarda antes si se editó (como al cerrar); una captura sin editar se sustituye sin dejar archivo. Fuera "Open in New Window" del menú de la tira de recientes.
  - [x] Los botones Copiar y Guardar de la tarjeta de título (solo los botones; ⌘C, ⌘S y Esc no cambian): copian o guardan, cierran todas las ventanas de la app salvo los pines (editor, inicio, Preferencias, guía, miniatura, paneles de color y fuente) y devuelven el foco a la app anterior para pegar enseguida. La app sigue en la barra de menús. Si el guardado falla, no se cierra nada y el error se ve en la barra. Se llaman "Copy and Close" y "Save and Close".
  - [x] Ajuste en Preferencias › General › Editor: "Close all windows after Copy or Save (title bar buttons)", activado por defecto.
  - [x] Verificado: flujo nuevo `single-editor` (14 comprobaciones: misma ventana, autoguardado de la sustituida, abrirla de nuevo, captura sin editar sin archivo, Copiar y Guardar cierran editor, inicio y Preferencias y dejan el pin, guardado fallido no cierra, ajuste desactivado). `copy-paste` y DEFAULTS adaptados a una sola ventana. 113 tests unitarios; todas las suites de integración pasan y FLOWS 377/0.
- [x] **R12 · Icono en el Dock** (petición del 1-nov-2026; primer paso para que el editor sea la ventana principal):
  - [x] La app tiene icono en el Dock por defecto (política `.regular`). `LSUIElement` sigue en Info.plist para que el icono no parpadee con el ajuste desactivado. Ajuste en Preferencias › General: "Show the app icon in the Dock"; no se pueden ocultar a la vez el icono del Dock y el de la barra de menús.
  - [x] Menú principal completo: About, Hide Others, Show All, Window y Help.
  - [x] La cortina de captura pasa a ser un panel que no activa la app, porque con Dock una ventana normal no se abre sobre otra app en pantalla completa. Copiar y Guardar devuelven el foco activando la app anterior, porque `NSApp.deactivate()` ya no basta.
  - [x] Decidido: sobre una app en pantalla completa, el editor se abre en el Space del escritorio y Copy and Close vuelve al de la app, como cualquier app del Dock.
  - [x] Antes de R12: una captura nueva recibe archivo al salir del editor (al cerrar o sustituirla), aunque no se haya editado. Cambia lo decidido en R11.
  - [x] Verificado: flujos nuevos `dock` y `close-reopen`, `Tools/fullscreen-test.sh` a mano (cortina y pin sobre pantalla completa) y prueba manual de foco, cursor y pantalla completa con atajos reales. 113 tests unitarios; todas las suites de integración pasan, FLOWS 408/0 y LIVE 22/0 (1 omitida: requiere dos pantallas).
- [x] **R13 · El editor persiste; el Dock lo muestra** (petición del 1-nov-2026):
  - [x] El botón rojo, ⌘W, Esc, Pin, Copy and Close y Save and Close solo ocultan el editor, tras guardar. Vuelve igual, con su historial de deshacer.
  - [x] El clic en el Dock (y abrir la app desde Finder o Spotlight) siempre muestra el editor, también con un pin o la Biblioteca en pantalla. Sin editor abre la captura más reciente; con la carpeta vacía, la Biblioteca hasta que exista el estado vacío (R14). Un arranque normal hace lo mismo; al iniciar sesión o con un enlace o archivo, no.
  - [x] El Edit del pin vuelve al archivo del que salió, con sus objetos editables, en lugar de abrir la imagen aplanada (visto en la prueba manual).
  - [x] Los nombres de Copy y Save siguen el ajuste al momento: el editor oculto ya no se recrea, así que leerlos al abrir dejaría de bastar.
  - [x] Verificado: flujo `close-reopen` ampliado (ocultar por cada camino, volver con el mismo documento e historial, desde minimizado, sin editor). 113 tests unitarios; todas las suites de integración pasan, FLOWS 419/0 y LIVE 22/0 (1 omitida: requiere dos pantallas). Falta comprobar a mano el clic real en el Dock y el arranque al iniciar sesión.
- [x] **R14 · El editor como inicio** (petición del 1-nov-2026):
  - [x] Botón New Capture en la tarjeta de título (Área; su menú añade Ventana y Pantalla completa). El editor se aparta para no salir en la captura y vuelve si se cancela, si falla o si la captura solo copia.
  - [x] Con la carpeta vacía, el editor muestra una página con Área, Ventana, Pantalla completa y Abrir imagen, sobre un documento en blanco que nunca se guarda ni se puede editar.
  - [x] Menú de estado: "Open ScreenShot" abre el editor y "Library…" (⌘L) la Biblioteca.
  - [x] Verificado: flujo nuevo `editor-home` (la parte de carpeta vacía se ejecuta sin `-saveFolder`, porque ese argumento fija la carpeta). 113 tests unitarios; todas las suites de integración pasan, FLOWS 425/0 y LIVE 22/0 (1 omitida: requiere dos pantallas).

Camino crítico: R1 → R2 → R3. R4, R5 y R7 dependen de R3 pero no entre sí; R6 y R8 pueden ir en paralelo desde R2. R5b va antes de R6: cambia la colocación de la cinta, el lienzo y las barras, y conviene asentarla antes de añadir más controles. R7 (ventana de inicio) y R8 (bienvenida) deben adoptar el mismo estilo de tarjetas.

---

## Cómo se verifica cada punto

- Compilación limpia con `./build.sh`.
- `Tools/test.sh` (54 tests) y `Tools/integration-tests.sh` (93 comprobaciones en 9 suites) más los nuevos de cada función.
- Capturas de la interfaz en modo claro y oscuro (`SCREENSHOT_SNAPSHOT_DIR`).
- Las funciones de captura en vivo, con el autotest de la Fase 1.

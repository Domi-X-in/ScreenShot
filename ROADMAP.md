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
- [ ] **R2 · Infraestructura de la cinta (sin conectar)**: botones grande, pequeño, dividido, desplegable, campo y color con sus 5 estados; grupos con etiqueta; botón compacto con panel; colapso de derecha a izquierda (1200/1020/960/860/830/800/640); teclado y VoiceOver. Pruebas: tabla de anchos → grupos colapsados; ventana de demostración en debug.
- [ ] **R3 · Nuevo armazón del editor**: barra de título solo con ventana, Copiar imagen, Guardar, Fijar, Arrastrar, Deshacer/Rehacer; cinta con Portapapeles, Formas y Herramientas conectados a `Tool` y a `ShotView`; herramienta activa en naranja aunque su grupo esté colapsado. Pruebas: `FlowsSelfTest+Toolbar` y `+Editor`, capturas ancho/estrecho.
- [ ] **R4 · Grupos de formato**: Fuente, Párrafo, Color (relleno, contorno con grosor y guiones, color y contorno de fuente) y Formato de formas (Organizar, Alinear, Girar, Voltear, puntas de flecha, estilo de línea). Se borra `EditorToolbar`. Pruebas: `+Formatting`, `+StyleSync`, `+Callout`, `ArrangeTests`, `FormattingTests`.
- [ ] **R5 · Parte inferior**: `NotificationBar` (info, éxito, aviso, error, con temporizador y acción) en lugar del texto de ayuda y los Toast del editor; lecturas de color/tamaño/zoom, Fondo y tira de recientes con el nuevo estilo.
- [ ] **R6 · Funciones nuevas del diseño** (PR pequeños): tachado, justificado, viñetas, numeración, cambiar mayúsculas/minúsculas, contorno de fuente, copiar formato, cortar/copiar/pegar objetos, OCR/QR y selección de área de imagen como herramientas del editor.
- [ ] **R7 · Puntos de entrada**: nuevo icono de la barra de menús, menú de estado con iconos, ventana de inicio con barra tipo cinta y agrupación por día.
- [ ] **R8 · Guía de bienvenida de 3 pasos**: Bienvenida con bucle animado, Configuración (permiso, carpeta, tema), Listo (atajos y primera captura); se mantiene la reanudación tras reiniciar y "Reducir movimiento".
- [ ] **R9 · Cierre**: quitar `newEditorUI` y el código viejo, revisar tema claro y accesibilidad, actualizar `docs/screenshots`, README y esta hoja de ruta, versión de prueba con `release.sh`.

Camino crítico: R1 → R2 → R3. R4, R5 y R7 dependen de R3 pero no entre sí; R6 y R8 pueden ir en paralelo desde R2.

---

## Cómo se verifica cada punto

- Compilación limpia con `./build.sh`.
- `Tools/test.sh` (54 tests) y `Tools/integration-tests.sh` (93 comprobaciones en 9 suites) más los nuevos de cada función.
- Capturas de la interfaz en modo claro y oscuro (`SCREENSHOT_SNAPSHOT_DIR`).
- Las funciones de captura en vivo, con el autotest de la Fase 1.

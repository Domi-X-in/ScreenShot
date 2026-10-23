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

- [ ] **Texto en varias líneas** (Mayús+Retorno añade un salto de línea).
- [ ] **Orden de capas**: Traer al frente / Enviar al fondo; alinear y distribuir varios objetos.
- [ ] **Auto-censura**: un clic desenfoca todos los emails, teléfonos y números de tarjeta que encuentre el OCR.
- [ ] **Menú Compartir** (Mail, Mensajes, AirDrop) junto a Copiar / Guardar / Fijar.
- [ ] **Guía de primer uso**: permisos y atajos.
- [ ] **Interfaz en español** (localización completa, con el inglés como alternativa).

## Fase 5 — Distribución 🟢

- [ ] **Firma Developer ID y notarización de Apple** (requiere una cuenta de Apple Developer).
- [ ] **Actualizaciones automáticas** (Sparkle) a partir de las releases de GitHub.
- [ ] **Releases en GitHub** con el `.app` comprimido y notas de versión.

---

## Cómo se verifica cada punto

- Compilación limpia con `./build.sh`.
- `Tools/test.sh` (54 tests) y `Tools/integration-tests.sh` (93 comprobaciones en 9 suites) más los nuevos de cada función.
- Capturas de la interfaz en modo claro y oscuro (`SCREENSHOT_SNAPSHOT_DIR`).
- Las funciones de captura en vivo, con el autotest de la Fase 1.

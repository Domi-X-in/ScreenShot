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

## Fase 2 — Mantenimiento 🔧

- [ ] **Tests estándar**: mover los 8 autotests a un target `swift test`, fuera de la app que se distribuye.
- [ ] **CI en GitHub Actions**: compilar y ejecutar los tests en cada push.
- [ ] **Limpieza**: quitar el código que dejó sin uso el rediseño (helper de iconos de la barra antigua, botón de carpeta antiguo de la tira, etc.).
- [ ] **Rendimiento con capturas grandes (5K)**:
  - [ ] Medir el autoguardado en capturas Retina grandes.
  - [ ] Guardar la imagen original una sola vez en lugar de en cada autoguardado.
  - [ ] Evitar recodificar el PNG completo cuando solo cambian las anotaciones.
- [ ] **Accesibilidad**: nombres para VoiceOver en los botones personalizados de la barra, paletas y tira de recientes.

## Fase 3 — Paridad con Shottr 🟠

- [ ] **Panel de fondo (Backdrop) completo**:
  - [ ] Proporciones: 1:1, 4:3, 3:2, 16:9, Twitter, Facebook, YouTube, LinkedIn, Pinterest
  - [ ] Margen (padding), sombra, inset, radio exterior e interior, recentrar
  - [ ] Fondos: color sólido, mezcla de colores, gradientes (malla, vertical, diagonal, radial) e imagen con desenfoque
- [ ] **Cut Out (tijeras)**: quitar una franja horizontal o vertical y unir el resto.
- [ ] **OCR sobre un área seleccionada** y ajuste **"Idioma principal de OCR"**.
- [ ] **Biblioteca de capturas**: ventana con búsqueda, tamaños de miniatura y lista de todas las capturas (no solo las 10 últimas).
- [ ] **Estilos dibujados a mano** para flechas y formas.
- [ ] **Medir manteniendo 1 o 2**: distancia bajo el cursor mientras se mantiene la tecla.
- [ ] **Imprint Selection Size**: estampar el tamaño de la selección en la imagen.
- [ ] **Autoadjust**: ajuste automático de la selección al contenido.
- [ ] **Ajustes que faltan**:
  - [ ] Ocultar el icono de la barra de menús
  - [ ] Capturar el cursor del ratón (auto / incluir / excluir)
  - [ ] Reducir capturas Retina a 1× al guardar
  - [ ] Altura máxima de la captura con desplazamiento
  - [ ] Fondo de capturas de ventana: fondo de escritorio o color sólido
  - [ ] Activar o desactivar los enlaces `screenshot://`
- [ ] **Superposición GIF**: animación de dos fotogramas (superposición y captura).

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
- Autotests existentes (79 comprobaciones) más los nuevos de cada función.
- Capturas de la interfaz en modo claro y oscuro (`SCREENSHOT_SNAPSHOT_DIR`).
- Las funciones de captura en vivo, con el autotest de la Fase 1.

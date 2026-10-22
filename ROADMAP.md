# ScreenShot — Hoja de ruta

Lista de todo lo que vamos a implementar, por fases. Se marca cada punto (`[x]`) al terminarlo, junto con cómo se verificó.

Leyenda: 🔴 urgente · 🟠 paridad con Shottr · 🟢 mejora propia · 🔧 mantenimiento

---

## Fase 0 — Base del proyecto 🔴

- [x] **Control de versiones**: repositorio git con `.gitignore` (sin `.build/`, `build/`, `.DS_Store`) y primer commit (`263ae0d`).
- [x] **GitHub**: repositorio público [Domi-X-in/ScreenShot](https://github.com/Domi-X-in/ScreenShot), rama `main` publicada.
- [x] **ROADMAP.md** (este archivo) en el repositorio.

## Fase 1 — Verificar lo que ya existe 🔴

Las capturas reales nunca se han probado de principio a fin; las pruebas actuales cubren el editor, no la captura.

- [ ] **Autotest de captura en vivo**, que la propia app ejecuta con su permiso de Grabación de pantalla:
  - [ ] Captura de pantalla completa
  - [ ] Captura de área y repetición del área
  - [ ] Captura de ventana (con y sin sombra) y de la ventana activa
  - [ ] Captura con retardo (3 s)
  - [ ] **Captura con desplazamiento (scroll)**: automática y manual
  - [ ] Reconocimiento de texto/QR sobre una captura real
  - [ ] Selección de área en un segundo monitor (si hay uno conectado)
- [ ] Corregir lo que falle en esas pruebas.

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

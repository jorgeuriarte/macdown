# Diario de desarrollo — MacDown (fork propio)

## 2026-06-13 — Arranque del fork de mantenimiento

### Qué se hizo
- Análisis del ecosistema: 1146 forks de `MacDownApp/macdown`, 52 con actividad
  posterior al upstream, **32 con commits propios**.
- Decisión de base: **`plateaukao/macdown`** (activo, arquitectura ObjC original).
- Decisión de repo: **independiente (mirror)**, con remotes a upstream y forks clave.
- Clonada la base en local y configurados 10 remotes.
- Escrito el tracker de forks (`claude_tools/track_forks.py` + `.sh` + `seeds.txt`),
  que detecta forks con commits propios y novedades entre ejecuciones.
- Generado el informe inicial [`docs/FORKS.md`](FORKS.md) (baseline).
- Escrito `CLAUDE.md` del proyecto.

### Decisiones tomadas
- Build canónico en **GitHub Actions** (el entorno local macOS 26.x / Xcode 26.x es
  demasiado nuevo para el deployment target histórico).
- `markly` y `swift` quedan como **referencia, no mergeables** (rebrand cerrado /
  port divergente a Swift).

### Aprendizajes
- El fix transversal que aplican casi todos los forks vivos es el crash de arranque
  por out-of-bounds en `MPToolbarController toolbarDefaultItemIdentifiers:`.
- El segundo patrón universal es Apple Silicon (arm64) + subir deployment target.

### Próximos pasos
- Crear el repo en GitHub y hacer push.
- Montar el workflow de build/release/tag en GitHub Actions e iterar hasta verde.
- Verificar que el `.app` resultante arranca; portar el fix del toolbar si falta.

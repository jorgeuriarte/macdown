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

### Resultados (misma sesión)
- Repo creado: **github.com/jorgeuriarte/macdown** (privado) y push de `master`.
- Workflow `.github/workflows/build.yml`: build universal (arm64+x86_64) sin firma
  en `macos-14`, genera el parser PEG, `pod install`, empaqueta ZIP+DMG.
  **Build verde a la primera.**
- Pipeline de release/tagging probado: tag **v0.8.1** → release publicada con
  `MacDown.dmg` + `MacDown.zip`, versión inyectada desde el tag (0.8.1, build 4).
- Smoke test del binario publicado: proceso vivo 7s sin crash report → **no
  reproduce el crash de arranque del toolbar**.

### Pendiente / salvedades honestas
- **Sin firma ni notarización**: Gatekeeper bloqueará la app (abrir con clic
  derecho → Abrir, o `xattr -dr com.apple.quarantine MacDown.app`). Firma con
  Developer ID = mejora futura (requiere certificado).
- **Verificación visual completa**: falta abrir la app en un Mac y usarla de
  verdad (el entorno de desarrollo es headless con Xcode roto).
- **Dependabot heredado** de plateaukao genera PRs/runs de ruido: decidir si
  desactivarlo o acotarlo.
- El versionado correcto solo se inyecta en releases (tags); los builds de
  `master` muestran 0.1.

### Próximos pasos
- Cherry-pick incremental de features (Quick Look de treehouse, export de nyimbi…).
- Firmar/notarizar releases.
- (Opcional) Workflow programado que ejecute el tracker de forks y avise de novedades.

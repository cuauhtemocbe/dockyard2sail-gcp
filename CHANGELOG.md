# Changelog

Todos los cambios notables de este proyecto se documentan en este archivo.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
y este proyecto adhiere a [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Módulo `terraform/bootstrap/` (una vez por proyecto): bucket de estado remoto con versionado y retención configurable, pool y provider de Workload Identity Federation para GitHub, SA `plan` de solo lectura (cualquier ref) y SA `apply` de escritura (solo `refs/heads/main`), sin llaves JSON. Incluye su README y los targets `make bootstrap`, `bootstrap-migrate` y `bootstrap-output`.
- `.gitignore` reforzado contra credenciales: variantes de archivos de entorno, llaves y keystores, credenciales de `gcloud`, `gha-creds-*.json` y planes en JSON.
- Job `gitleaks` en CI sobre todo el historial (`make secrets-history`).
- Documentada la protección de `main` que exige la SA `apply` (PR obligatorio, aplicada a administradores, checks requeridos).
- README con el alcance, la arquitectura prevista y las decisiones de diseño del template.
- Licencia MIT.
- `Makefile` autodocumentado que corre Terraform y gitleaks dentro de Docker (imágenes fijadas por digest).
- Git hooks versionados en `.githooks/`: `pre-commit` (validate + gitleaks sobre el diff staged) y `pre-push` (gate de Trivy para CRITICAL con fix publicado).
- CI en GitHub Actions con jobs paralelos: `fmt`, `validate`, `license-check` y `trivy-fs` (vulnerabilidades, misconfiguraciones de IaC y secretos). Actions pineadas por commit SHA y `permissions: contents: read`.
- Dependabot para `github-actions`, con updates semanales agrupados.
- `CLAUDE.md` con las reglas no negociables de infraestructura y el flujo de trabajo para agentes.

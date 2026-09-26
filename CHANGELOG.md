# Changelog

Todos los cambios notables de este proyecto se documentan en este archivo.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
y este proyecto adhiere a [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- README con el alcance, la arquitectura prevista y las decisiones de diseño del template.
- Licencia MIT.
- `Makefile` autodocumentado que corre Terraform y gitleaks dentro de Docker (imágenes fijadas por digest).
- Git hooks versionados en `.githooks/`: `pre-commit` (validate + gitleaks sobre el diff staged) y `pre-push` (gate de Trivy para CRITICAL con fix publicado).
- CI en GitHub Actions con jobs paralelos: `fmt`, `validate`, `license-check` y `trivy-fs` (vulnerabilidades, misconfiguraciones de IaC y secretos). Actions pineadas por commit SHA y `permissions: contents: read`.
- Dependabot para `github-actions`, con updates semanales agrupados.
- `CLAUDE.md` con las reglas no negociables de infraestructura y el flujo de trabajo para agentes.

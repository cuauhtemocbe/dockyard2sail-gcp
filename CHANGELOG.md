# Changelog

Todos los cambios notables de este proyecto se documentan en este archivo.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
y este proyecto adhiere a [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- `make trivy` corre Trivy en Docker (imagen `TRIVY_IMAGE` fijada por digest, v0.75.0) con la base de vulnerabilidades cacheada en `~/.cache/trivy`, y acepta `SEVERITY` (por defecto `CRITICAL,HIGH`). El hook `pre-push` ya no invoca el binario: llama a `make trivy SEVERITY=CRITICAL`, así que `git push` funciona sin Trivy instalado y los flags viven solo en el `Makefile` (#6).
- La SA `apply` de bootstrap ya no tiene `roles/iam.serviceAccountUser` sobre el proyecto: lo recibe solo sobre la SA de runtime, con el binding que crea `cloud-run-service` para su nueva variable `deployers` (`envs/dev` pasa la SA `apply`). `iam.serviceAccountAdmin` sigue sobre el proyecto, porque hace falta para crear la SA de runtime. `TF_ADC` pasa `GOOGLE_IMPERSONATE_SERVICE_ACCOUNT` al contenedor.
- Decisión sobre la protección de `main`: `enforce_admins` queda en `true` (sin excepción para el owner). Documentado en `CLAUDE.md`, el README y `terraform/bootstrap/README.md`.
- El `Makefile` anota la versión de Terraform de la imagen fijada (v1.16.4) y que sus imágenes se actualizan a mano.

### Added

- `sonar-project.properties` para el análisis local con SonarQube (`/sonar-check`): analiza `terraform/` y excluye los directorios de datos de Terraform. `.github/` no se analiza: el SonarQube local no trae el analizador de GitHub Actions. `.scannerwork/` queda en `.gitignore` (#26). `.gitleaksignore` exceptúa la línea `sonar.projectKey` (el nombre del repo, no un secreto), que gitleaks marcaba como `generic-api-key`.
- `terraform/envs/dev/README.md`: `apply` en dos pasos para montar secretos, procedimiento manual para subir la imagen y desplegarla con `gcloud run deploy` (sin `--tag`), y los gotchas del entorno. El README raíz, `CLAUDE.md` y la hoja de ruta reflejan los módulos, el entorno y el workflow que ya existen.
- Workflow `plan.yml`: en cada PR que cambia `terraform/**` corre `make plan-ci ENV=dev` con la SA `plan` (WIF, solo lectura, `-lock=false`) y publica el plan en el job summary. Se salta en forks y no es un check requerido. Lee las variables de repositorio `PLAN_SERVICE_ACCOUNT` y `GCP_PROJECT_ID`.
- Raíz `terraform/envs/dev` con estado remoto (prefijo `envs/dev`) y los targets `make plan` y `make apply` (`ENV=dev PROJECT_ID=...`). Dependabot cubre también `envs/dev`.
- Módulo `terraform/modules/cloud-run-service`: SA de runtime sin roles de proyecto y servicio Cloud Run v2 con acceso público opcional. Ignora los cambios de imagen para que un `plan` no revierta lo que despliega `gcloud run deploy`.
- Módulo `terraform/modules/secrets`: crea secretos sin valor y da `roles/secretmanager.secretAccessor` sobre cada uno a la SA de runtime. `envs/dev` lo conecta con las variables `secret_ids` y `secret_env` (montaje en dos pasos). `.gitignore` exceptúa este módulo de la regla `secrets/`.
- Módulo `terraform/modules/artifact-registry`: repositorio Docker con dos políticas de limpieza (conserva las últimas N versiones y borra las sin tag con más de M días).
- Job `lock-check` en CI y target `make lock-check` (parte de `make validate`): falla si un directorio raíz (`bootstrap` o `envs/*`) no tiene `.terraform.lock.hcl` o si el lockfile no corresponde a sus providers (`init -lockfile=readonly`). Los módulos de `terraform/modules/` no llevan lockfile.
- Dependabot para el ecosistema `terraform` en `terraform/bootstrap`, con updates semanales agrupados.
- Módulo `terraform/bootstrap/` (una vez por proyecto): bucket de estado remoto con versionado y retención configurable, pool y provider de Workload Identity Federation para GitHub, SA `plan` de solo lectura (cualquier ref) y SA `apply` de escritura (solo `refs/heads/main`), sin llaves JSON. Incluye su README y los targets `make bootstrap`, `bootstrap-migrate` y `bootstrap-output`.
- `.gitignore` reforzado contra credenciales: variantes de archivos de entorno, llaves y keystores, credenciales de `gcloud`, `gha-creds-*.json` y planes en JSON.
- Workflow `verify-apply-sa`: al mergear a `main` (o manualmente desde `main`) comprueba que la ejecución obtiene la SA `apply` por WIF. Lee el provider y la SA de las variables del repositorio `WIF_PROVIDER` y `APPLY_SERVICE_ACCOUNT`.
- Job `gitleaks` en CI sobre todo el historial (`make secrets-history`).
- Documentada la protección de `main` que exige la SA `apply` (PR obligatorio, aplicada a administradores, checks requeridos).
- README con el alcance, la arquitectura prevista y las decisiones de diseño del template.
- Licencia MIT.
- `Makefile` autodocumentado que corre Terraform y gitleaks dentro de Docker (imágenes fijadas por digest).
- Git hooks versionados en `.githooks/`: `pre-commit` (validate + gitleaks sobre el diff staged) y `pre-push` (gate de Trivy para CRITICAL con fix publicado).
- CI en GitHub Actions con jobs paralelos: `fmt`, `validate`, `license-check` y `trivy-fs` (vulnerabilidades, misconfiguraciones de IaC y secretos). Actions pineadas por commit SHA y `permissions: contents: read`.
- Dependabot para `github-actions`, con updates semanales agrupados.
- `CLAUDE.md` con las reglas no negociables de infraestructura y el flujo de trabajo para agentes.

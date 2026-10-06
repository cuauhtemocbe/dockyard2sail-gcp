# Changelog

Todos los cambios notables de este proyecto se documentan en este archivo.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
y este proyecto adhiere a [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- `bootstrap`: la SA `apply` cambia `roles/secretmanager.admin` por un rol personalizado (`<name_prefix>_apply_secrets`) sin `secretmanager.versions.access` ni `versions.add`: `apply` no tiene lectura directa del valor de los secretos. No es una frontera dura: `secrets.setIamPolicy` y `serviceAccountAdmin` le permiten darse acceso, pero eso pasa por un cambio de IAM auditable. `roles/iam.serviceAccountAdmin` se queda sobre el proyecto, con la decisión y su razón en `terraform/bootstrap/README.md`. `specs/bootstrap-plan.md` refleja los roles finales. Lo aplica el owner a mano con `make bootstrap` (#45).
- `bootstrap`: `github_repository_id` es obligatorio (sin `default`, conserva la validación numérica) y la condición del provider de WIF siempre exige nombre e ID del repositorio. Antes, sin el ID, la confianza dependía solo del nombre `owner/repo`, reutilizable si el repositorio se borra. `terraform.tfvars.example` lo trae descomentado y el README de bootstrap deja de llamarlo opcional. No cambia el plan de un despliegue que ya lo define (#46).
- `ci.yml`: corre en `push` solo a `main` (antes a cualquier rama), así que un commit de un PR genera un run y no dos. Todos los jobs tienen `timeout-minutes: 10`. El job `trivy-fs` (mismo nombre, check requerido) ejecuta `make trivy` en lugar de `trivy-action`: misma imagen fijada por digest (v0.75.0) y mismos flags que en local. Ya no escanea secretos, que cubre `gitleaks` (#49).
- `make trivy` corre Trivy en Docker (imagen `TRIVY_IMAGE` fijada por digest, v0.75.0) con la base de vulnerabilidades cacheada en `~/.cache/trivy`, y acepta `SEVERITY` (por defecto `CRITICAL,HIGH`). El hook `pre-push` ya no invoca el binario: llama a `make trivy SEVERITY=CRITICAL`, así que `git push` funciona sin Trivy instalado y los flags viven solo en el `Makefile` (#6).
- La SA `apply` de bootstrap ya no tiene `roles/iam.serviceAccountUser` sobre el proyecto: lo recibe solo sobre la SA de runtime, con el binding que crea `cloud-run-service` para su nueva variable `deployers` (`envs/dev` pasa la SA `apply`). `iam.serviceAccountAdmin` sigue sobre el proyecto, porque hace falta para crear la SA de runtime. `TF_ADC` pasa `GOOGLE_IMPERSONATE_SERVICE_ACCOUNT` al contenedor.
- Decisión sobre la protección de `main`: `enforce_admins` queda en `true` (sin excepción para el owner). Documentado en `CLAUDE.md`, el README y `terraform/bootstrap/README.md`.
- README, `CLAUDE.md` y `terraform/envs/dev/README.md`: el `apply` de `dev` desde CI es el camino normal y `make apply` local la excepción. Se documenta que CI ve solo lo versionado (`terraform.tfvars` no). El texto "build + push + deploy" del README pasa a "`terraform apply` al hacer merge; la imagen se despliega desde el repo de la aplicación" (#34).
- El `Makefile` anota la versión de Terraform de la imagen fijada (v1.16.4) y que sus imágenes se actualizan a mano.
- `envs/dev`: `secret_ids` y `secret_env` se definen en los `default` de `variables.tf`, no en `terraform.tfvars`. Con `terraform.tfvars` (no versionado), el siguiente `deploy` destruía el secreto y sus versiones y quitaba la variable del servicio, porque CI aplica los `default`. El montaje de un secreto pasa a ser dos PRs (crear y cargar el valor; montar), el README advierte que quitar un id destruye el secreto, y `terraform.tfvars.example` ya no documenta estas variables. Los `default` siguen siendo `[]` y `{}`: `dev` no tiene secretos (#43).
- README: el diagrama de "Arquitectura prevista" ya no muestra a GitHub Actions de este repo haciendo `docker push` ni creando una revisión de Cloud Run; esas dos flechas salen del repo de la aplicación (`dockyard2sail-py`), y este repo solo hace `terraform apply`. El texto bajo el diagrama aclara el reparto (#40).

### Fixed

- README: la sección de CI decía que cada job de `ci.yml` ejecuta el target de `make` del mismo nombre; solo es cierto para `lock-check` y `license-check`. Se lista la correspondencia real (`fmt` → `fmt-check`, `validate` → `validate-tf`, `trivy-fs` → `trivy`, `gitleaks` → `secrets-history`) (#48).
- `cloud-run-service`: `name` acepta de 4 a 22 caracteres (antes 24). El id de la SA de runtime es `<name>-runtime` y GCP limita los ids a 30: un nombre de 23 o 24 caracteres pasaba `validate` y el `plan`, y fallaba al crear la SA durante el `apply`. `tests/name.tftest.hcl` (`terraform test` con `mock_provider`) comprueba que 22 caracteres pasan y 23 fallan (#42).
- `plan.yml`: el paso "Terraform plan (dev)" usa `shell: bash`. Sin él, GitHub corre `bash -e {0}` sin `pipefail`, y en `make plan-ci ... 2>&1 | tee plan.txt` el código de salida era el de `tee` (0): un plan fallido dejaba el job y el check en verde. Igual que ya hacía `deploy.yml` (#41).

### Added

- `plan.yml`: el job `plan-bootstrap` muestra en el job summary el `plan` de `terraform/bootstrap` (SA `plan`, `-lock=false`) en los PRs que tocan `terraform/bootstrap/**`, el `Makefile` o el propio workflow. Un PR que solo toca `envs/` o `modules/` lo omite. Nuevo target `make plan-bootstrap-ci`, que genera `backend.tf` desde `backend.tf.example` y pasa por `-var` la región y el repositorio (con su ID), porque `terraform.tfvars` no se versiona (#48).
- Workflow `drift.yml` y target `make drift-ci`: cada lunes (y con `workflow_dispatch`) corre `plan -detailed-exitcode` de `envs/dev` con la SA `plan`. Sin cambios sale en verde; drift (código 2) y error (código 1) salen en rojo, con el plan en el job summary (#48).
- `cloud-run-service`: variable `max_instances` (entero >= 1, o `null` para no fijarlo; por defecto `null`). Limita la escala, no el gasto. `envs/dev` la fija en 3 (el servicio real tenía 20), porque el servicio es público y sin tope escala hasta el valor por defecto de Cloud Run (100 por revisión según su documentación). `min_instance_count` pasa `null` cuando `min_instances = 0`. `tests/max_instances.tftest.hcl` comprueba la validación y el bloque `scaling` (#44).
- Workflow `deploy.yml` y target `make apply-ci`: al hacer merge a `main` con cambios en `terraform/**`, el `Makefile` o el propio workflow (o con `workflow_dispatch`), aplica `envs/dev` con la SA `apply` por WIF. Un solo job hace `plan -out` y `apply` de ese plan, y publica ambos en el job summary. `concurrency` por entorno sin cancelar. Verificado de extremo a extremo con el cambio de la descripción del repositorio de Artifact Registry (0 added, 1 changed, 0 destroyed) y `make plan ENV=dev` sin cambios después. El build y el push de la imagen no se hacen aquí: viven en `dockyard2sail-py` (#29).
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

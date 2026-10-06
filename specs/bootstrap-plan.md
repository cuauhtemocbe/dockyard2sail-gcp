# Implementation Plan: Módulo bootstrap

**Spec**: [specs/bootstrap.md](./bootstrap.md)  
**Issue**: [#7](https://github.com/cuauhtemocbe/dockyard2sail-gcp/issues/7)  
**Created**: 2026-09-25  
**Status**: approved

## Components

Cada componente corresponde a una tarea de la sección Tasks.

| Componente | Qué hace | Tarea | Esfuerzo |
|------------|----------|-------|----------|
| Esqueleto | Versiones, provider, variables y APIs. | T1 | S |
| Bucket de estado | Guarda el estado de Terraform con versionado. | T2 | S |
| Ejecución y migración | Targets de `make` para aplicar con estado local y migrarlo al bucket. | T3 | M |
| WIF | Pool y provider OIDC de GitHub. | T4 | M |
| SA `plan` | Cuenta de solo lectura para los PRs. | T5 | M |
| SA `apply` | Cuenta de escritura, solo desde `main`. | T6 | M |
| Documentación | README del módulo. | T7 | S |
| Cierre | Lockfile, changelog y README raíz. | T8 | XS |

### Permisos de las service accounts

Cada rol lleva un comentario en el código que explica para qué se necesita.

| SA | Rol | Alcance |
|----|-----|---------|
| `plan` | `roles/run.viewer`, `roles/artifactregistry.reader`, `roles/secretmanager.viewer`, `roles/iam.securityReviewer`, `roles/serviceusage.serviceUsageConsumer`, `roles/iam.workloadIdentityPoolViewer` | Proyecto |
| `plan` | `roles/storage.objectViewer`, `roles/storage.legacyBucketReader` | Solo el bucket de estado |
| `apply` | `roles/run.admin`, `roles/artifactregistry.admin`, `roles/iam.serviceAccountAdmin`, `roles/serviceusage.serviceUsageConsumer` | Proyecto |
| `apply` | Rol personalizado `<name_prefix>_apply_secrets`: `secretmanager.secrets.create/delete/get/list/update/getIamPolicy/setIamPolicy` y `versions.get/list`, sin `versions.access` | Proyecto |
| `apply` | `roles/storage.objectAdmin` | Solo el bucket de estado |

Cuatro decisiones de diseño detrás de esa tabla:

- **`plan` corre con `-lock=false` y sin permiso de escritura.** El backend de GCS bloquea el estado escribiendo un objeto `.tflock` en el bucket. Un `plan` con bloqueo necesitaría escribir en el bucket de estado. Como `plan` no modifica infraestructura, no se le da esa escritura.
- **`apply` no recibe `roles/resourcemanager.projectIamAdmin`.** Con ese rol podría asignarse `roles/owner` a sí misma. Los módulos siguientes deben dar permisos sobre cada recurso (el secreto, el repositorio de Artifact Registry, el servicio de Cloud Run) y no sobre todo el proyecto.
- **`apply` no tiene `roles/secretmanager.admin`.** Incluye `secretmanager.versions.access`, y la SA podría leer directamente el valor de todos los secretos, que el módulo `secrets` nunca lee. Un rol personalizado deja solo los permisos que Terraform usa (#45). No es una frontera dura: `secrets.setIamPolicy` y `iam.serviceAccounts.setIamPolicy` permiten que `apply` se dé acceso, aunque eso pasa por un cambio de IAM auditable. SonarQube lo marca como `terraform:S6408` (escalada de privilegios en un rol personalizado); se aceptó el 2026-10-06 en SonarQube porque el módulo `secrets` exige el permiso y el riesgo es el descrito aquí (#62).
- **El permiso para usar `apply` se define con un atributo compuesto.** El provider de WIF mapea `repo_ref = repositorio@ref`. Un permiso de WIF solo puede filtrar por un atributo, y con este el binding de `apply` exige repositorio y rama a la vez, sin condiciones IAM adicionales.

## Dependencies

### Build Order

1. T1 (esqueleto): todo lo demás lo usa.
2. T2 (bucket) y T4 (WIF): no dependen entre sí; ambos dependen de T1.
3. T3 (ejecución y migración): necesita el bucket de T2.
4. T5 (SA `plan`) y T6 (SA `apply`): necesitan el bucket de T2 y el provider de T4.
5. T7 (README del módulo): documenta lo que hicieron T3 a T6.
6. T8 (cierre): al final, cuando todo está verificado.

### External Dependencies

- Un proyecto de GCP `dev` con facturación. Sin él, la verificación llega solo hasta `make validate`, `make trivy` y un `plan` parcial.
- Una persona con permisos de administrador en ese proyecto y con `gcloud auth application-default login` hecho en su computadora.
- Un repositorio de GitHub con Actions habilitado y una rama descartable para la prueba de WIF.
- Docker, que el `Makefile` ya requiere.

## Risks & Assumptions

### Risks

| Riesgo | Mitigación |
|--------|------------|
| En un proyecto nuevo, `cloudresourcemanager` y `serviceusage` pueden no estar activas, y Terraform necesita ambas para habilitar el resto. | Se documenta como prerrequisito en el README del módulo. Si el primer `apply` falla por esa causa, se documenta el paso mínimo para activarlas. |
| Un binding de IAM puede fallar con "service account does not exist" segundos después de crear la SA. Es un comportamiento conocido de GCP que aún no se ha reproducido en este módulo. | Reintentar el `apply`, que es idempotente. Solo si se repite siempre se agrega una espera con `time_sleep`. |
| El evento `pull_request_target` corre en el contexto de la rama base. Su `ref` sería `refs/heads/main` y obtendría la SA `apply`. | El README del módulo prohíbe usar `pull_request_target` con WIF. La regla se aplica al escribir los workflows, que son el siguiente ítem de la hoja de ruta. |
| `apply` tiene `roles/iam.serviceAccountAdmin` sobre todo el proyecto. | Se acepta (#45) porque `cloud-run-service` necesita crear la SA de runtime y su binding, y no se pudo confirmar una condición de IAM por prefijo para este rol. Riesgo latente: puede darse `serviceAccountUser` o `serviceAccountTokenCreator` sobre otras SAs. Se revisa al agregar una SA con más permisos que `apply`. `roles/iam.serviceAccountUser` ya no está en el proyecto: `cloud-run-service` lo da sobre su SA de runtime (ver el changelog de `specs/bootstrap.md`). |
| Las credenciales de `gcloud auth application-default login` incluyen un token de renovación de larga vida en la computadora de quien ejecuta. No está en el repo ni en los secrets de GitHub, así que no rompe las reglas del proyecto. | El README recomienda revocarlas al terminar el bootstrap. |
| Trivy podría marcar el bucket por no usar Cloud KMS. No está verificado. | Cloud KMS está fuera de alcance. Si el hallazgo es CRITICAL o HIGH, se documenta la excepción con fecha de revisión, como pide `CLAUDE.md`. |

### Assumptions

Cada una se comprueba en la tarea indicada.

- ~~Los cuatro roles de solo lectura iniciales alcanzan para un `plan` completo.~~ **Falso, comprobado en T5 con un workflow real (2026-09-26).** Faltaban tres, todos de solo lectura: `serviceusage.serviceUsageConsumer` (con `user_project_override`, cada llamada exige `serviceusage.services.use`), `iam.workloadIdentityPoolViewer` (`securityReviewer` no incluye `iam.workloadIdentityPools.get`) y `storage.legacyBucketReader` sobre el bucket (`objectViewer` no incluye `storage.buckets.get`). Con ellos el `plan` corre sin errores. Un rol recién asignado tarda alrededor de un minuto en propagarse: un 403 inmediato no siempre es un rol faltante.
- El provider necesita `user_project_override = true` y `billing_project` cuando se autentica con credenciales de usuario. Se comprueba en T1.
- El nombre `<project_id>-tfstate` no está tomado en otro proyecto. Se comprobó en T2: el bucket se creó. `name_prefix` no cambia el nombre del bucket, así que si estuviera tomado habría que modificar el módulo.

## Milestones

- [x] **M1**: `make validate` y `make trivy` pasan sobre `terraform/bootstrap/` (T1, T2, T4, T5, T6).
- [x] **M2**: `make bootstrap` crea todo en el proyecto `dev` y un segundo `plan` da 0 cambios (T3).
- [x] **M3**: `make bootstrap-migrate` deja el estado en el bucket con versiones recuperables (T3).
- [x] **M4**: desde un PR de prueba se obtiene la SA `plan` y falla al usar la SA `apply`; desde `main` se obtiene `apply` (T5, T6).
  - **Hecho (2026-09-26)**: desde el PR de prueba #8 (`refs/pull/8/merge`) la SA `plan` funcionó y la SA `apply` falló con `PERMISSION_DENIED` (`iam.serviceAccounts.getAccessToken`). El PR se cerró sin mergear.
  - **Hecho (2026-09-27)**: el workflow `verify-apply-sa` corrió sobre `main` (ejecución 36293992691) y el token obtenido era de `dockyard2sail-apply@`. El workflow se eliminó después (#50): hoy esta mitad de la prueba la cubre `deploy.yml`, que se autentica con la SA `apply` en cada merge a `main`.
  - **Ojo**: `google-github-actions/auth` sin `token_format` solo escribe el archivo de credenciales y no llama a GCP, así que no sirve para probar una denegación. La prueba usó `token_format: access_token`.
- [x] **M5**: lockfile versionado, CHANGELOG y README actualizados, CI verde y checklist de "Antes de mergear" completo (T7, T8). Verificado el 2026-09-27: CI en verde en el PR #9 y en `main` (`c9d50be`), `make validate` y `make trivy` sin hallazgos.

## Tasks

**Slicing strategy**: Mixed. La base (T1) bloquea todo lo demás, así que va primero. Después, cada slice es un flujo completo que se puede verificar en `dev`, ordenado por riesgo: primero el estado remoto (es el paso con más trabajo operativo: credenciales dentro de Docker y migración), luego `plan` desde un PR y al final `apply` restringido a `main` (el de mayor superficie de seguridad).

### Foundation (Build First)

- [x] **T1**: Esqueleto del módulo
  - **Acceptance**: `terraform/bootstrap/` con versiones fijadas con `~>`, provider con `user_project_override = true` y `billing_project`, variables (`github_repository_id` obligatoria) y APIs habilitadas con `disable_on_destroy = false`. Si falta `project_id`, `github_repository` o `github_repository_id`, el `plan` falla con un mensaje claro.
  - **Files**: `terraform/bootstrap/versions.tf`, `variables.tf`, `apis.tf`, `terraform.tfvars.example`
  - **Tests**: `make validate`, `make trivy` y un `plan` sin `project_id` que debe fallar.
  - **Effort**: S

### Slice 1: Estado remoto

- [x] **T2**: Bucket de estado
  - **Acceptance**: bucket con versionado, acceso uniforme, acceso público prohibido, `force_destroy = false`, `prevent_destroy` y retención configurable (90 días por defecto). Output `state_bucket_name`.
  - **Files**: `terraform/bootstrap/state_bucket.tf`, `outputs.tf`
  - **Tests**: `make validate`, `make trivy` y revisar en el `plan` cada atributo de seguridad.
  - **Effort**: S
- [x] **T3**: Ejecución con credenciales y migración de estado
  - **Acceptance**: una variante de `TF` en el `Makefile` monta las credenciales de `gcloud` en solo lectura. `make bootstrap PROJECT_ID=...` corre `init` y `apply` con estado local. `make bootstrap-migrate PROJECT_ID=...` genera `backend.tf` desde `backend.tf.example` y corre `init -migrate-state`. `backend.tf` y el estado local están en `.gitignore`.
  - **Files**: `Makefile`, `.gitignore`, `terraform/bootstrap/backend.tf.example`
  - **Tests**: en `dev`, `apply` y un segundo `plan` con 0 cambios; `migrate` y `terraform state list` con backend remoto; el objeto del estado tiene al menos 2 versiones después de un segundo cambio. `make validate` sigue pasando sin `backend.tf`.
  - **Effort**: M

### Slice 2: `plan` desde un PR

- [x] **T4**: Workload Identity Federation
  - **Acceptance**: pool y provider OIDC que solo aceptan el repositorio configurado y su ID (`github_repository_id`). Atributos mapeados: `repository`, `ref`, `repo_ref` y `repository_id`. Output `workload_identity_provider` con el nombre completo.
  - **Files**: `terraform/bootstrap/wif.tf`, `outputs.tf`
  - **Tests**: `make validate` y `make trivy`; en el `plan`, la condición del provider contiene siempre el repositorio y su ID; sin `github_repository_id` el `plan` falla por variable requerida, y con un valor no numérico falla por la validación.
  - **Effort**: M
- [x] **T5**: SA `plan`
  - **Acceptance**: SA con los roles de lectura de la tabla de permisos y `objectViewer` y `legacyBucketReader` solo sobre el bucket. Cualquier ref del repositorio autorizado puede usarla. Output con su correo.
  - **Files**: `terraform/bootstrap/service_accounts.tf` (parte `plan`), `outputs.tf`
  - **Tests**: `make trivy`; en `dev`, un workflow de prueba en una rama descartable, lanzado desde un PR, se autentica y corre `terraform plan -lock=false` sobre bootstrap con backend remoto, sin errores de permisos.
  - **Effort**: M

### Slice 3: `apply` solo desde `main`

- [x] **T6**: SA `apply`
  - **Acceptance**: SA con los roles de la tabla de permisos (ni `owner`, ni `editor`, ni `projectIamAdmin`) y un permiso de uso que exige `attribute.repo_ref/<owner>/<repo>@refs/heads/main`. Output con su correo.
  - **Files**: `terraform/bootstrap/service_accounts.tf` (parte `apply`), `outputs.tf`
  - **Tests**: en `dev`, con el workflow de prueba, desde `main` se obtiene `apply` y desde un PR falla con `PERMISSION_DENIED`. Una búsqueda de `google_service_account_key`, `roles/owner`, `roles/editor` y `projectIamAdmin` en el código no devuelve resultados.
  - **Effort**: M

### Closure

- [x] **T7**: README del módulo
  - **Acceptance**: `terraform/bootstrap/README.md` con prerrequisitos (proyecto con facturación, APIs base, credenciales de `gcloud`), ejecución única, migración de estado, cómo usar los outputs en un workflow, la prohibición de `pull_request_target` con WIF y la recomendación de revocar las credenciales al terminar.
  - **Files**: `terraform/bootstrap/README.md`
  - **Tests**: seguir el README desde cero en un proyecto limpio, o compararlo contra lo que se hizo en T3. Los enlaces funcionan.
  - **Effort**: S
- [x] **T8**: Lockfile, changelog y README raíz
  - **Acceptance**: `.terraform.lock.hcl` versionado; entrada en `CHANGELOG.md` bajo `[Unreleased]`; ítem de la hoja de ruta marcado y secciones "planeado" ajustadas solo en lo que ya existe; `status: completed` en el spec (estuvo en `in-progress` hasta cerrar M4).
  - **Files**: `terraform/bootstrap/.terraform.lock.hcl`, `CHANGELOG.md`, `README.md`, `specs/bootstrap.md`
  - **Tests**: `make validate`, `make trivy` y el CI (`fmt`, `validate`, `license-check`, `trivy-fs`) en verde.
  - **Effort**: XS

## Effort Estimate

**Total Estimated Days**: 2-3 días. Es una estimación mía, sin medir, y supone tener un proyecto de GCP `dev` disponible.

| Phase | Effort |
|-------|--------|
| Foundation (T1) | 0.25 días |
| Features (T2, T4, T5, T6) | 1 día |
| Integration (T3, T7) | 0.75 días |
| Testing & Polish (verificación real, T8) | 0.5-1 día |

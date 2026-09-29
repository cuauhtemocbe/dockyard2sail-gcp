# Implementation Plan: Despliegue en dev

**Spec**: [despliegue-dev.md](./despliegue-dev.md)  
**Issue**: #14  
**Created**: 2026-09-27  
**Status**: approved

## Decisión que necesito de ti

Una decisión, con default. Si no dices nada, se aplica el default.

| Tema | Default | Alternativa | Por qué el default |
|------|---------|-------------|--------------------|
| Quién es dueño de la imagen del servicio | El módulo pone el placeholder al crear el servicio y después ignora la imagen (`lifecycle.ignore_changes`). La imagen real se actualiza con `gcloud run deploy` y, más adelante, con el workflow de `deploy`. | Que Terraform siempre fuerce la variable `image`. | El `plan` de un pull request (PR) no sabe qué imagen está desplegada. Sin `ignore_changes`, todo PR mostraría "volver al placeholder" y ese ruido esconde los cambios reales. |

## Tasks

**Slicing strategy**: Mixed. El esqueleto de `envs/dev` bloquea todo lo demás, así que va primero como fundación. Después vienen cortes verticales que se demuestran solos, ordenados por riesgo: el servicio primero por el IAM, y el ajuste de roles al final porque depende de lo que descubra el `plan` en PR.

El detalle de cada tarea (qué se acepta, archivos, pruebas) vive en su issue, para no mantenerlo en dos lugares.

| Tarea | Qué entrega | Issue | Esfuerzo | Depende de | Hito |
|-------|-------------|-------|----------|------------|------|
| T1 | Esqueleto de `envs/dev`, targets `plan`/`apply`, Dependabot | #15 | S | nada | M1 |
| T2 | `cloud-run-service` con imagen placeholder | #16 | M | T1 | M2 |
| T3 | `artifact-registry` y procedimiento manual de imagen | #17 | S | T1, T2 | M3 |
| T4 | `secrets` y montaje en dos pasos | #18 | S | T1, T2 | M3 |
| T5 | Workflow `plan.yml` | #19 | M | T1 | M4 |
| T6 | Ajuste de roles en `bootstrap` | #20 | M | T5 | M5 |
| T7 | Documentación y cierre | #21 | S | T1 a T6 | |

Estimación total: 5 a 8 días de trabajo.

### Entrega en dos PRs

| PR | Tareas | Motivo |
|----|--------|--------|
| 1 | T1 a T4 | Módulos y entorno. Se aplican en local, sin depender del workflow. |
| 2 | T5 a T7 | El `plan` del PR de prueba necesita que los recursos del PR 1 ya existan en el estado. |

Cada PR espera tu confirmación antes del push, como pide `CLAUDE.md`.

## Milestones

- [x] **M1**: `make plan ENV=dev` inicializa el backend remoto y da 0 cambios; `make validate` sigue en verde después.
- [ ] **M2**: el servicio con el placeholder responde HTTP 200 con acceso público y 403 sin él.
- [ ] **M3**: el repositorio tiene su política de limpieza; un secreto de prueba llega al servicio y otro sin acceso falla.
- [ ] **M4**: un PR de prueba muestra el `plan` en su summary y `apply` con la SA `plan` da `PERMISSION_DENIED`.
- [ ] **M5**: roles de `bootstrap` ajustados, `plan` de PR sin 403 y `apply` de `envs/dev` como SA `apply` sin errores.

## Diseño de cada pieza

Solo lo que el spec no fija.

- **`envs/dev`**: `backend "gcs"` con solo `prefix = "envs/dev"`; el bucket llega con `-backend-config="bucket=$(PROJECT_ID)-tfstate"`. Así el archivo versionado no lleva el ID de un proyecto concreto y `make validate` sigue usando `init -backend=false`. Variables: `project_id` (la pasa `make`), `region` (default `us-central1`) e `image` (default placeholder).
- **`lock-check`**: deja de exigir lockfile en `terraform/modules/`. `validate-tf` sigue validando los módulos, y su `init` genera ahí un lockfile local que `.gitignore` excluye.
- **`cloud-run-service`**: entradas `name`, `region`, `image`, `allow_unauthenticated` (default `false`; activa `invoker_iam_disabled` del servicio), `min_instances` (default `0`, va en `scaling.min_instance_count`), `secret_env` (variable de entorno → id de secreto, default vacío; el módulo fija `version = "latest"`), `deletion_protection` (default `true`; `dev` lo pone en `false` para poder destruir) y `deployers` (correos que pueden usar la SA de runtime; se agrega en T6, default vacío). Ignora cambios de imagen y de `client`/`client_version`, que reescribe `gcloud run deploy`.
- **`artifact-registry`**: dos políticas de limpieza. `KEEP` con `most_recent_versions.keep_count = N` (cuenta versiones con o sin tag, porque `keep_count` no filtra por tag ni se combina con condiciones en la misma política) y `DELETE` de versiones sin tag con `older_than` M días. `KEEP` gana si una versión cumple las dos. La limpieza tarda cerca de un día en aplicarse; `cleanup_policy_dry_run` (default `false`) permite probar sin borrar.
- **`secrets`**: recibe el correo de la SA de runtime y una lista de ids. La dependencia circular con `cloud-run-service` es de módulo, no de recurso, y Terraform trabaja por recurso; `validate` lo comprueba. Si lo rechaza, `envs/dev` crea los `google_secret_manager_secret_iam_member` y `secrets` solo crea los secretos.
- **`plan.yml`**: usa `token_format: access_token` (como `verify-apply-sa.yml`) y pasa el token con `GOOGLE_OAUTH_ACCESS_TOKEN`, así el contenedor de Docker no necesita el archivo de credenciales de la Action. El proyecto llega por la variable de repositorio `GCP_PROJECT_ID`, sin `tfvars` reales en CI. Se salta en PRs desde forks (no reciben `id-token`). El `Makefile` acepta las credenciales de `gcloud` (ADC) o un token.
- **Roles de `bootstrap`**: `serviceAccountUser` se quita del proyecto y se da solo sobre la SA de runtime, con un binding que crea `cloud-run-service` para los correos de `deployers` (aquí, la SA `apply`). Es el patrón que documenta Google; no se usa una condición de Identity and Access Management (IAM) sobre `resource.name`, porque no se pudo confirmar que funcione con service accounts. `serviceAccountAdmin` sigue sobre el proyecto: hace falta para crear la SA de runtime y su binding. Los roles de lectura que falten a la SA `plan` los revela un `plan` real (en bootstrap faltaron 3).

## Risks & Assumptions

| Riesgo | Mitigación |
|--------|------------|
| Cloud Run no despliega una revisión que monta un secreto sin versiones o sin acceso: lo comprueba al desplegar. | `secret_env` empieza vacío: el primer `apply` crea los secretos, se carga el valor con `gcloud` y un segundo `apply` los monta. Va en el README de `envs/dev`. |
| La SA `plan` puede carecer de lectura sobre los recursos nuevos. | El `plan` del PR de prueba lo revela y T6 agrega los roles. Un rol nuevo tarda cerca de un minuto en propagarse: un 403 inmediato no siempre es un rol faltante. |
| `terraform init` con backend remoto deja `.terraform/` y rompe `make validate` (pasó con bootstrap). | `TF_VALIDATE` ya usa su propio `TF_DATA_DIR`. Se comprueba que `make validate` pasa después de `make plan ENV=dev`. |
| Ningún workflow de este spec usa la SA `apply`, así que su acotamiento quedaría sin prueba. `roles/owner` no incluye `iam.serviceAccounts.getAccessToken`, así que la persona administradora no puede suplantarla sin un rol extra. | En T6, dar `roles/iam.serviceAccountTokenCreator` sobre la SA `apply` a esa persona con `gcloud`, aplicar `envs/dev` suplantándola (`GOOGLE_IMPERSONATE_SERVICE_ACCOUNT`) y revocar el rol al terminar. Ese rol permite un `apply` fuera de `main`, así que es temporal y el PR de T6 documenta cuándo se dio y cuándo se revocó (`CLAUDE.md` pide documentar lo hecho a mano). |
| Trivy puede marcar `allow_unauthenticated` o la falta de llave de cifrado propia. | Si es CRITICAL o HIGH, excepción documentada con fecha de revisión, como pide `CLAUDE.md`. |
| `gcloud run deploy --tag` genera drift en Terraform. | El procedimiento manual despliega sin `--tag`. |

Supuestos, con la tarea donde se comprueba:

- El provider `google` soporta `google_cloud_run_v2_service` y `cleanup_policies` (T1, con `validate`).
- Un `plan` de `envs/dev` sin recursos da "No changes" con el estado remoto vacío (T1).
- El servicio agente de Cloud Run descarga imágenes del repositorio del mismo proyecto sin rol extra (T3, con la imagen real). La documentación de Google lo confirma.
- `roles/artifactregistry.reader` alcanza para leer el repositorio en un `plan` (T5). La documentación no lista sus permisos; lo revelará el `plan` real.

## Dependencias externas

- `dockyard2sail-dev` con bootstrap aplicado y una persona administradora con `gcloud auth application-default login`.
- Variables de repositorio nuevas `PLAN_SERVICE_ACCOUNT` y `GCP_PROJECT_ID`. Crearlas cambia el repositorio: se pide confirmación antes.
- Una imagen de `dockyard2sail-py` construible en local, para probar el procedimiento manual.

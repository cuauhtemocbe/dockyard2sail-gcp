# Bootstrap

Prepara un proyecto de GCP para que el resto del repo se opere desde CI, sin llaves JSON. Se ejecuta **una vez por proyecto**, con `terraform apply` desde tu computadora: es el único código del repo que no se aplica desde CI.

Crea:

| Recurso | Para qué |
|---------|----------|
| Bucket `<project_id>-tfstate` | Estado remoto de Terraform, con versionado y retención configurable. |
| Pool y provider de Workload Identity Federation (WIF) | GitHub Actions se autentica con su token OIDC, sin credenciales guardadas. |
| SA `dockyard2sail-plan` | Solo lectura. La puede usar cualquier ref del repositorio, incluidos los PRs. |
| SA `dockyard2sail-apply` | Escritura. Solo la puede usar una ejecución sobre `refs/heads/main`. |
| 9 APIs del proyecto | Las que necesitan este módulo y los siguientes. |

Los roles de cada SA y por qué se eligieron están en [`specs/bootstrap-plan.md`](../../specs/bootstrap-plan.md#permisos-de-las-service-accounts).

## Prerrequisitos

1. **Un proyecto de GCP con facturación habilitada**, y tu usuario con permisos de administrador (`roles/owner`) sobre él.
2. **`gcloud` y Docker** instalados. Terraform corre dentro de Docker vía `make`.
3. **Dos APIs activas manualmente.** Terraform las necesita para habilitar las demás, así que no pueden salir del propio módulo:
   ```bash
   gcloud services enable cloudresourcemanager.googleapis.com serviceusage.googleapis.com --project <project_id>
   ```
4. **Credenciales de aplicación (ADC) de tu usuario:**
   ```bash
   gcloud auth application-default login
   ```
5. **Tus valores.** Copia el ejemplo y complétalo. `terraform.tfvars` no se versiona.
   ```bash
   cp terraform/bootstrap/terraform.tfvars.example terraform/bootstrap/terraform.tfvars
   ```
   Pon el ID numérico del repositorio en `github_repository_id` (`gh api repos/<owner>/<repo> --jq .id`). Es opcional, pero recomendado: el nombre de un repositorio borrado lo puede reutilizar otra persona, el ID no.

## Ejecución única

```bash
make bootstrap PROJECT_ID=<project_id>
```

Corre `init` y `apply`, y `apply` pide confirmación. **Córrelo desde una terminal normal**: el prefijo `!` de Claude Code no tiene TTY y `apply` no puede pedirla.

Revisa el `plan` antes de aplicar. Al terminar, un segundo `plan` debe dar `No changes`.

## Migrar el estado al bucket

El primer `apply` deja el estado en un archivo local, y el bucket de estado es uno de los recursos que ese estado describe. Se migra al bucket que se acaba de crear:

```bash
make bootstrap-migrate PROJECT_ID=<project_id>
```

Genera `backend.tf` (ignorado por git) desde `backend.tf.example` y migra el estado con `init -migrate-state -force-copy`. Después el archivo `terraform.tfstate` local ya no se usa y se puede borrar.

`make validate-tf` usa un directorio de datos aparte (`.terraform-validate`), así que validar no exige credenciales aunque el backend ya esté inicializado.

## Usar los outputs en un workflow

```bash
make bootstrap-output
```

| Output | Va en |
|--------|-------|
| `workload_identity_provider` | `workload_identity_provider` de `google-github-actions/auth` |
| `plan_service_account_email` | `service_account` en los workflows de PR |
| `apply_service_account_email` | `service_account` en el workflow que corre al hacer merge a `main` |
| `state_bucket_name` | `bucket` del backend de cada entorno |

Guarda `workload_identity_provider` y el correo de la SA como variables del repositorio (`gh variable set`), no como secrets: no son secretas, y así el repo no lleva el número de proyecto. [`verify-apply-sa.yml`](../../.github/workflows/verify-apply-sa.yml) las lee como `WIF_PROVIDER` y `APPLY_SERVICE_ACCOUNT`.

Un workflow que se autentica necesita `permissions: id-token: write` (en el job, no en todo el workflow) y `contents: read`. Fija la action por commit SHA, como pide `CLAUDE.md`.

## Reglas al escribir los workflows

- **Nunca uses `pull_request_target` con WIF.** Ese evento corre en el contexto de la rama base: su `ref` sería `refs/heads/main` y obtendría la SA `apply` con código de un PR ajeno.
- **Los PRs solo hacen `plan`**, con la SA `plan` y `-lock=false`. La SA `plan` no puede escribir en el bucket, así que no puede crear el bloqueo del estado.
- **`apply` solo corre al hacer merge a `main`.**

## Protección de `main`

La SA `apply` se obtiene desde `refs/heads/main`, así que quien pueda empujar directo a `main` obtiene escritura sobre el proyecto. La protección de la rama es parte de la seguridad de este módulo. Vive en GitHub, no en Terraform, y hay que configurarla al crear el repositorio (Settings → Branches → `main`):

- **Pull request obligatorio**, con 0 aprobaciones requeridas: con un solo autor, exigir 1 te bloquearía tus propios PRs.
- **Aplicar también a administradores** (`enforce_admins: true`), o tu cuenta se salta el resto de reglas. Se decidió activarlo, no dejarlo como excepción: con el `apply` ocurriendo al hacer merge a `main`, saltarse los checks tendría más peso que en un repo de código común.
- **Checks requeridos, con la rama al día (`strict`):** `fmt`, `validate`, `lock-check`, `license-check`, `trivy-fs` y `gitleaks`.
- **Sin force-push ni borrado de la rama.**

## Cosas que conviene saber

- **Un rol recién asignado tarda cerca de un minuto en propagarse.** Un `403` inmediato después de un `apply` no siempre es un rol faltante: espera y reintenta.
- **Un binding puede fallar con "service account does not exist"** segundos después de crear la SA. El `apply` es idempotente: reintenta.
- **`name_prefix` cambia el nombre de las SAs y del pool, pero no el del bucket**, que siempre es `<project_id>-tfstate`.
- **`apply` tiene `roles/iam.serviceAccountAdmin` sobre todo el proyecto**, porque `cloud-run-service` necesita crear la SA de runtime y su binding. No tiene `roles/iam.serviceAccountUser` sobre el proyecto: lo recibe solo sobre la SA de runtime de cada servicio, por el binding que crea `cloud-run-service` para sus `deployers`. Al desplegar un entorno por primera vez, aplica `envs/<env>` antes de quitar ese rol a una SA `apply` que ya lo tuviera.
- **`apply` no tiene `roles/resourcemanager.projectIamAdmin`**, a propósito: con él podría asignarse `roles/owner`. Los módulos siguientes dan permisos sobre cada recurso, no sobre el proyecto.

## Al terminar

Revoca las credenciales de tu computadora. Incluyen un token de renovación de larga vida:

```bash
gcloud auth application-default revoke
```

Desde ese momento el proyecto se opera desde CI con las SAs de este módulo.

# dockyard2sail-gcp

![Estado](https://img.shields.io/badge/estado-en%20construcci%C3%B3n-orange)
![Terraform](https://img.shields.io/badge/Terraform-IaC-7B42BC?logo=terraform&logoColor=white)
![Google Cloud](https://img.shields.io/badge/Google%20Cloud-Cloud%20Run-4285F4?logo=googlecloud&logoColor=white)
![Licencia](https://img.shields.io/badge/license-MIT-green)

Template de infraestructura como código para desplegar una API en **Google Cloud Run** con Terraform, sin llaves de servicio y con CI/CD desde GitHub Actions. Es el hermano de infraestructura de [`dockyard2sail-py`](https://github.com/cuauhtemocbe/dockyard2sail-py) y [`dockyard2sail-ts`](https://github.com/cuauhtemocbe/dockyard2sail-ts): esos dos resuelven "cómo arranco el código", este resuelve "cómo lo llevo a producción en GCP".

> **Estado: en construcción.** Existen el módulo [`terraform/bootstrap/`](terraform/bootstrap/README.md) (estado remoto, Workload Identity Federation y service accounts de CI), los módulos `cloud-run-service`, `artifact-registry` y `secrets`, el entorno [`terraform/envs/dev`](terraform/envs/dev/README.md) y los workflows `plan.yml` (plan en cada PR) y `deploy.yml` (`terraform apply` de `dev` al hacer merge a `main`), todos verificados en un proyecto real. El resto (entorno `prod`, `budget-alert`) sigue en diseño. Las secciones marcadas como *planeado* se irán convirtiendo en realidad y este documento se actualizará con ellas.

## Problema

Desplegar un contenedor en GCP por primera vez suele terminar en clics en la consola, una llave JSON de service account pegada en los secrets de GitHub y un entorno que nadie sabe reconstruir. Este template propone el camino opuesto: todo declarado en Terraform, ninguna credencial de larga vida y un entorno reproducible con un solo `terraform apply`.

## Alcance

**Incluye** (existen el estado remoto, Workload Identity Federation, las service accounts de CI, los módulos, el entorno `dev` y el pipeline `plan`/`apply`; el entorno `prod` y el presupuesto con alerta son planeados):

- **Cloud Run** como destino del contenedor, con servicio, revisiones y tráfico definidos en Terraform.
- **Artifact Registry** para las imágenes, con política de limpieza de versiones antiguas.
- **Secret Manager** para la configuración sensible, montada en el servicio como variables de entorno.
- **Workload Identity Federation** para que GitHub Actions se autentique en GCP sin llaves JSON.
- **Service accounts de mínimo privilegio**, separadas para el despliegue (CI) y para la ejecución (runtime).
- **Estado remoto** de Terraform en Cloud Storage, con versionado activado.
- **Dos entornos** (`dev` y `prod`) que reutilizan los mismos módulos.
- **Presupuesto con alerta** para que un error de configuración no se convierta en una factura.
- **Pipeline de GitHub Actions**: `terraform fmt`/`validate`/`plan` en cada PR, y `terraform apply` al hacer merge a `main`; la imagen se despliega desde el repo de la aplicación.

**No incluye (por ahora):**

- Redes privadas (VPC, Serverless VPC Access) ni bases de datos gestionadas: se agregarán como módulos opcionales si el template lo pide.
- Multi-región ni balanceador global.
- Código de aplicación propio: el ejemplo de despliegue usa la imagen de `dockyard2sail-py`.

## Arquitectura prevista

```mermaid
flowchart LR
    dev([Desarrollador]) -->|PR / merge| gh[GitHub Actions<br/>este repo]
    app[Repo de la aplicación<br/>dockyard2sail-py<br/>fuera de este repo]

    subgraph gcp["Proyecto de GCP"]
        wif[Workload Identity<br/>Federation]
        ar[(Artifact Registry)]
        run[Cloud Run]
        sm[Secret Manager]
        gcs[(Cloud Storage<br/>estado de Terraform)]
    end

    gh -->|token OIDC| wif
    wif -->|impersona SA de despliegue| gh
    gh -->|terraform apply| gcs
    gh -->|terraform apply:<br/>crea y configura los recursos| gcp
    app -->|docker push| ar
    app -->|gcloud run deploy| run
    ar -->|imagen| run
    sm -->|secretos en runtime| run
    user([Usuario]) -->|HTTPS| run
```

La autenticación no guarda ningún secreto en GitHub: el workflow presenta un token OIDC efímero, Workload Identity Federation lo valida contra el repositorio autorizado y entrega credenciales de corta vida para impersonar la service account de despliegue.

Los workflows de este repo solo corren `terraform plan` (en PRs) y `terraform apply` (al hacer merge a `main`): no construyen ni suben la imagen. Eso lo hace el repo de la aplicación, que sube la imagen a Artifact Registry y despliega con `gcloud run deploy`. Terraform ignora la imagen del servicio para que un `plan` no la revierta.

## Estructura prevista

Lo marcado como planeado todavía no existe.

```
.
├── terraform/
│   ├── bootstrap/          # Se corre una vez: bucket de estado, WIF, service accounts de CI
│   ├── modules/
│   │   ├── cloud-run-service/
│   │   ├── artifact-registry/
│   │   ├── secrets/
│   │   └── budget-alert/   # planeado
│   └── envs/
│       ├── dev/
│       └── prod/           # planeado
├── .github/workflows/      # plan en PR y apply en main (existen)
├── docs/                   # decisiones (ADRs) y guía de arranque
├── Makefile                # fmt, validate, plan, apply por entorno
└── README.md
```

## Decisiones de diseño

| Decisión | Alternativa descartada | Por qué |
|----------|------------------------|---------|
| Workload Identity Federation | Llave JSON de service account en secrets de GitHub | Una llave filtrada da acceso indefinido; un token OIDC expira en minutos y solo sirve para un repo y una rama concretos. |
| Cloud Run | GKE, Compute Engine | Para una API contenedorizada no hace falta administrar nodos, y escala a cero cuando no hay tráfico. |
| Terraform | Consola, `gcloud` en scripts | El entorno se puede reconstruir, revisar en un PR y comparar con `plan` antes de aplicarlo. |
| Módulos + carpetas por entorno | Workspaces de Terraform | Un `dev` y un `prod` que pueden divergir de forma explícita y visible en el diff, sin depender de una variable de workspace. |
| Service accounts separadas (CI vs runtime) | Una sola cuenta con permisos amplios | Si la API se compromete, no puede modificar infraestructura. |

Cada decisión con matices se documentará como ADR en `docs/`.

## Costos

Pensado para caber en el nivel gratuito de Google Cloud en un proyecto de bajo tráfico. Cloud Run incluye un cupo mensual gratuito de solicitudes, y Artifact Registry, Secret Manager y Cloud Storage cobran poco o nada a esta escala. Los límites exactos cambian con el tiempo: consulta [cloud.google.com/free](https://cloud.google.com/free) antes de desplegar. El módulo `budget-alert`, todavía planeado, existirá para avisar si algo se sale del plan.

## Requisitos previos

Para `terraform/bootstrap/` (los prerrequisitos completos están en [su README](terraform/bootstrap/README.md)):

- Una cuenta de Google Cloud con facturación habilitada (el nivel gratuito la exige).
- Un proyecto de GCP por entorno.
- Docker y `gcloud` instalados. Terraform corre dentro de Docker vía `make`, no se instala.
- Un repositorio de GitHub con Actions habilitado.

## Cómo usarlo

Los tres pasos ya funcionan.

```bash
# 1. Crear el estado remoto y la federación de identidad (una sola vez)
#    Procedimiento completo: terraform/bootstrap/README.md
make bootstrap PROJECT_ID=mi-proyecto-dev
make bootstrap-migrate PROJECT_ID=mi-proyecto-dev

# 2. Planear un entorno desde tu computadora. Montar secretos y subir la imagen: terraform/envs/dev/README.md
make plan ENV=dev PROJECT_ID=mi-proyecto-dev

# 3. Aplicar: abre un PR (plan.yml muestra el plan) y haz merge a main.
#    deploy.yml corre `terraform apply` de dev con la SA apply. `make apply` local es la excepción.
make apply ENV=dev PROJECT_ID=mi-proyecto-dev   # solo si CI no puede
```

## Hoja de ruta

- [x] Módulo `bootstrap` (estado remoto + Workload Identity Federation).
- [x] Módulo `cloud-run-service` con el ejemplo de `dockyard2sail-py`
- [x] Módulos `artifact-registry` y `secrets`
- [x] Workflow de `plan` en PR
- [x] Workflow de `deploy` en `main` (`terraform apply` de `dev`; la imagen se despliega desde el repo de la aplicación)
- [x] Entorno `dev`
- [ ] Entorno `prod`
- [ ] Módulo `budget-alert`
- [x] Escaneo de la infraestructura con Trivy (misconfiguraciones de IaC) en CI
- [ ] Guía de arranque y ADRs en `docs/`

## Desarrollo

El tooling y la validación cubren `terraform/bootstrap/`, `terraform/envs/` y `terraform/modules/`. Todo corre dentro de Docker vía `make` (`make help` lista los targets):

```bash
make validate       # fmt-check + terraform validate + lock-check + license-check
make secrets-scan   # gitleaks sobre el diff staged
make secrets-history # gitleaks sobre todo el historial de git
make trivy          # vulnerabilidades y misconfiguraciones de IaC, con Trivy en Docker
make install-hooks  # habilitar los git hooks (una vez por clon)
```

- **Hooks** (`.githooks/`, habilitados con `make install-hooks`): el `pre-commit` corre `make validate` y un escaneo de secretos con [gitleaks](https://github.com/gitleaks/gitleaks) sobre el diff staged; el `pre-push` corre `make trivy SEVERITY=CRITICAL` y bloquea solo si hay un hallazgo CRITICAL con fix publicado. Trivy corre en Docker con la imagen fijada por digest en el `Makefile`, así que no hace falta instalarlo; la base de vulnerabilidades se cachea en `~/.cache/trivy`.
- **CI** (`.github/workflows/ci.yml`): jobs paralelos `fmt`, `validate`, `lock-check`, `license-check`, `trivy-fs` y `gitleaks` (este último sobre todo el historial). Las Actions de terceros están pineadas por commit SHA y el workflow declara `permissions: contents: read`.
- **`lock-check`**: falla si un directorio raíz (`bootstrap` o `envs/*`) no tiene `.terraform.lock.hcl` o si el lockfile no corresponde a los providers declarados. Los módulos de `terraform/modules/` no llevan lockfile: Terraform solo usa el de la raíz. Este template no construye imágenes, así que no hay job de build.
- **Dependabot** abre PRs semanales agrupados para las Actions y para los providers de `terraform/bootstrap` y `terraform/envs/dev`.
- **Imágenes de herramientas fijadas por digest** en el `Makefile` (con su versión de Terraform anotada). Se actualizan a mano: Dependabot no las ve ahí.
- **`main` protegida también para el owner** (`enforce_admins`): un push directo equivaldría a un `apply` sin revisión. Detalle en [`terraform/bootstrap/README.md`](./terraform/bootstrap/README.md#protección-de-main).

Las reglas para agentes y el checklist previo a un merge están en [`CLAUDE.md`](./CLAUDE.md). El historial de cambios, en [`CHANGELOG.md`](./CHANGELOG.md). Los estándares que sigue este repo viven en `meta-projects/docs/development-standards.md`.

## Licencia

[MIT](./LICENSE)

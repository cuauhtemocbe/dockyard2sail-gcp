# dockyard2sail-gcp

![Estado](https://img.shields.io/badge/estado-en%20dise%C3%B1o-orange)
![Terraform](https://img.shields.io/badge/Terraform-IaC-7B42BC?logo=terraform&logoColor=white)
![Google Cloud](https://img.shields.io/badge/Google%20Cloud-Cloud%20Run-4285F4?logo=googlecloud&logoColor=white)
![Licencia](https://img.shields.io/badge/license-MIT-green)

Template de infraestructura como código para desplegar una API en **Google Cloud Run** con Terraform, sin llaves de servicio y con CI/CD desde GitHub Actions. Es el hermano de infraestructura de [`dockyard2sail-py`](https://github.com/cuauhtemocbe/dockyard2sail-py) y [`dockyard2sail-ts`](https://github.com/cuauhtemocbe/dockyard2sail-ts): esos dos resuelven "cómo arranco el código", este resuelve "cómo lo llevo a producción en GCP".

> **Estado: en diseño.** Este README describe el alcance y las decisiones previstas. Aún no hay código de Terraform ni workflows; las secciones marcadas como *planeado* se irán convirtiendo en realidad y este documento se actualizará con ellas.

## Problema

Desplegar un contenedor en GCP por primera vez suele terminar en clics en la consola, una llave JSON de service account pegada en los secrets de GitHub y un entorno que nadie sabe reconstruir. Este template propone el camino opuesto: todo declarado en Terraform, ninguna credencial de larga vida y un entorno reproducible con un solo `terraform apply`.

## Alcance

**Incluye (planeado):**

- **Cloud Run** como destino del contenedor, con servicio, revisiones y tráfico definidos en Terraform.
- **Artifact Registry** para las imágenes, con política de limpieza de versiones antiguas.
- **Secret Manager** para la configuración sensible, montada en el servicio como variables de entorno.
- **Workload Identity Federation** para que GitHub Actions se autentique en GCP sin llaves JSON.
- **Service accounts de mínimo privilegio**, separadas para el despliegue (CI) y para la ejecución (runtime).
- **Estado remoto** de Terraform en Cloud Storage, con versionado activado.
- **Dos entornos** (`dev` y `prod`) que reutilizan los mismos módulos.
- **Presupuesto con alerta** para que un error de configuración no se convierta en una factura.
- **Pipeline de GitHub Actions**: `terraform fmt`/`validate`/`plan` en cada PR, y build + push + deploy al hacer merge a `main`.

**No incluye (por ahora):**

- Redes privadas (VPC, Serverless VPC Access) ni bases de datos gestionadas: se agregarán como módulos opcionales si el template lo pide.
- Multi-región ni balanceador global.
- Código de aplicación propio: el ejemplo de despliegue usa la imagen de `dockyard2sail-py`.

## Arquitectura prevista

```mermaid
flowchart LR
    dev([Desarrollador]) -->|PR / merge| gh[GitHub Actions]

    subgraph gcp["Proyecto de GCP"]
        wif[Workload Identity<br/>Federation]
        ar[(Artifact Registry)]
        run[Cloud Run]
        sm[Secret Manager]
        gcs[(Cloud Storage<br/>estado de Terraform)]
    end

    gh -->|token OIDC| wif
    wif -->|impersona SA de despliegue| gh
    gh -->|docker push| ar
    gh -->|terraform apply| gcs
    gh -->|nueva revisión| run
    ar -->|imagen| run
    sm -->|secretos en runtime| run
    user([Usuario]) -->|HTTPS| run
```

La autenticación no guarda ningún secreto en GitHub: el workflow presenta un token OIDC efímero, Workload Identity Federation lo valida contra el repositorio autorizado y entrega credenciales de corta vida para impersonar la service account de despliegue.

## Estructura prevista

```
.
├── terraform/
│   ├── bootstrap/          # Se corre una vez: bucket de estado, WIF, service accounts de CI
│   ├── modules/
│   │   ├── cloud-run-service/
│   │   ├── artifact-registry/
│   │   ├── secrets/
│   │   └── budget-alert/
│   └── envs/
│       ├── dev/
│       └── prod/
├── .github/workflows/      # plan en PR, deploy en main
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

Pensado para caber en el nivel gratuito de Google Cloud en un proyecto de bajo tráfico. Cloud Run incluye un cupo mensual gratuito de solicitudes, y Artifact Registry, Secret Manager y Cloud Storage cobran poco o nada a esta escala. Los límites exactos cambian con el tiempo: consulta [cloud.google.com/free](https://cloud.google.com/free) antes de desplegar. El módulo `budget-alert` existe justamente para avisar si algo se sale del plan.

## Requisitos previos (planeado)

- Una cuenta de Google Cloud con facturación habilitada (el nivel gratuito la exige).
- Un proyecto de GCP por entorno.
- Terraform 1.x y `gcloud` instalados, o el contenedor de desarrollo que traerá el repo.
- Un repositorio de GitHub con Actions habilitado.

## Cómo usarlo (planeado)

```bash
# 1. Crear el estado remoto y la federación de identidad (una sola vez)
make bootstrap PROJECT_ID=mi-proyecto-dev

# 2. Planear y aplicar un entorno
make plan  ENV=dev
make apply ENV=dev

# 3. A partir de aquí, cada merge a main despliega vía GitHub Actions
```

## Hoja de ruta

- [ ] Módulo `bootstrap` (estado remoto + Workload Identity Federation)
- [ ] Módulo `cloud-run-service` con el ejemplo de `dockyard2sail-py`
- [ ] Módulos `artifact-registry` y `secrets`
- [ ] Workflow de `plan` en PR y `deploy` en `main`
- [ ] Entornos `dev` y `prod`
- [ ] Módulo `budget-alert`
- [ ] Escaneo de la infraestructura con Trivy (misconfiguraciones de IaC) en CI
- [ ] Guía de arranque y ADRs en `docs/`

## Licencia

[MIT](./LICENSE)

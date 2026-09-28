---
title: Despliegue en dev
status: approved
created: 2026-09-27
updated: 2026-09-27
issue: "#14"
---

# Despliegue en dev

## Objective

Tener un servicio de Cloud Run funcionando en `dockyard2sail-dev`, declarado en Terraform con tres módulos reutilizables y un entorno `terraform/envs/dev`. Cada pull request (PR) que toque Terraform muestra su `plan` sin poder modificar nada. Es el primer entorno real y valida los módulos que `prod` reutilizará.

## Context

`terraform/bootstrap/` ya entrega el bucket de estado, el provider de Workload Identity Federation (WIF) y las service accounts (SA) `plan` y `apply` (ver [`bootstrap.md`](./bootstrap.md)). Falta lo que corre encima: módulos, entornos y el workflow de `plan`. Este spec cubre cuatro ítems de la hoja de ruta del README.

Reglas heredadas de bootstrap:

- La SA `apply` no tiene `roles/resourcemanager.projectIamAdmin`: los permisos se dan sobre cada recurso, no sobre el proyecto.
- La SA `apply` tiene `iam.serviceAccountAdmin` e `iam.serviceAccountUser` sobre todo el proyecto "hasta que exista `cloud-run-service`". Este spec los acota (por ejemplo, `serviceAccountUser` solo sobre la SA de runtime) o explica por qué no se puede.
- Los workflows no usan `pull_request_target` con WIF: ese evento obtendría la SA `apply` desde un PR.
- `plan` corre con `-lock=false` porque la SA `plan` no puede escribir en el bucket de estado.

### Decisiones tomadas el 2026-09-27

| Tema | Decisión | Razón |
|------|----------|-------|
| Imagen del primer despliegue | `image` apunta por defecto a la imagen pública `us-docker.pkg.dev/cloudrun/container/hello` (placeholder). Subir la imagen de `dockyard2sail-py` es un paso manual documentado. | Cloud Run necesita una imagen que exista y el repositorio nace vacío. |
| Primer `apply` de `envs/dev` | Lo hace una persona administradora desde su computadora (`make apply ENV=dev`). | El `apply` desde CI pertenece al spec de `deploy`. |
| Acceso público | `allow_unauthenticated = false` por defecto en el módulo; `envs/dev` lo pone en `true`. Se implementa con `invoker_iam_disabled` (desactiva la comprobación del invocador), no con `roles/run.invoker` para `allUsers`. | Mínimo privilegio en el módulo, pero un servicio cerrado no se verifica con `curl`. Google recomienda `invoker_iam_disabled`, y `allUsers` no se puede otorgar si la organización restringe el dominio de los permisos. |
| Valores de los secretos | `secrets` crea el secreto y quién lo lee; el valor se carga con `gcloud`. | Un valor en Terraform termina en el estado y en git. |
| Salida del `plan` en el PR | Job summary (el resumen que GitHub muestra en la ejecución), no comentario. | Un comentario exige `pull-requests: write`. |
| Lockfile | `.terraform.lock.hcl` solo en directorios raíz (`bootstrap` y `envs/*`); los módulos de `terraform/modules/` no llevan. `lock-check` se ajusta a esa regla. | Terraform usa únicamente el lockfile de la raíz: uno en un módulo hijo no tiene efecto y solo agrega ruido en el repo y en Dependabot. |
| Check requerido | El job `plan` no es requerido en la protección de `main`. | Con filtro de rutas, un PR sin cambios de Terraform quedaría esperando un check que nunca llega. |

## Requirements

### Functional Requirements

**Módulos**

- [ ] `artifact-registry`: repositorio Docker con limpieza automática en dos políticas. Una conserva las últimas N versiones, con o sin tag (`KEEP`). La otra borra las versiones sin tag con más de M días (`DELETE`). N y M son variables. Si una versión cumple las dos, se conserva.
- [ ] `secrets`: crea secretos sin valor y da `roles/secretmanager.secretAccessor` sobre cada uno a la SA de runtime. No crea versiones.
- [ ] `cloud-run-service`: crea la SA de runtime (sin ningún rol de proyecto) y el servicio. Monta los secretos como variables de entorno, siempre con la versión `latest`. Desactiva la comprobación del invocador solo si `allow_unauthenticated` es `true`. Usa `min_instances = 0` por defecto.

**Entorno y comandos**

- [ ] `envs/dev` compone los tres módulos, con su estado en el bucket de bootstrap (prefijo `envs/dev`), `terraform.tfvars.example` y `.terraform.lock.hcl`.
- [ ] `make plan ENV=dev` y `make apply ENV=dev`, con Terraform en Docker (el README ya los anuncia).

**Pipeline**

- [ ] `plan.yml`: en cada PR que cambie `terraform/**`, se autentica con la SA `plan` por WIF, corre `terraform plan -lock=false` sobre `envs/dev` y escribe el resultado en el job summary.

**Documentación**

- [ ] Procedimiento manual para subir la imagen de `dockyard2sail-py` y actualizar el servicio con `gcloud run deploy` sin `--tag` (desplegar con tag provoca drift en Terraform).

### Non-Functional Requirements

| Área | Requisito |
|------|-----------|
| Seguridad | Ningún módulo crea `google_service_account_key` ni asigna `roles/owner`, `roles/editor` o `roles/resourcemanager.projectIamAdmin`. |
| Seguridad | `plan.yml` declara `permissions:` mínimo (`id-token: write` solo en el job que se autentica), usa el evento `pull_request` y pinea cada Action de terceros por commit SHA (el hash del commit) con el tag en un comentario. |
| Seguridad | Ningún valor de secreto aparece en el código, en el estado ni en el `plan`. |
| Calidad | `make validate` y `make trivy` sin hallazgos CRITICAL/HIGH. |
| Reproducibilidad | Providers con restricción `~>` y un `.terraform.lock.hcl` en cada directorio raíz (`bootstrap` y `envs/*`), sin lockfile en `terraform/modules/`. `make lock-check` lo exige solo en las raíces y pasa. |
| Idempotencia | Un segundo `plan` justo después del `apply` da 0 cambios. |
| Costo | Con `min_instances = 0` y sin tráfico, solo cuesta Artifact Registry por encima de 0,5 GB gratis (0,10 USD/GB al mes) y Secret Manager por encima de 6 versiones activas (0,06 USD por versión). Se revisa en la consola de facturación una semana después del `apply`, sin automatizar. |
| Rendimiento | El job `plan` termina en menos de 5 minutos con la caché de Docker vacía. |

## Architecture

### Components

```
terraform/
├── modules/
│   ├── artifact-registry/   # repositorio Docker + política de limpieza
│   ├── secrets/             # secretos vacíos + acceso de la SA de runtime
│   └── cloud-run-service/   # SA de runtime + servicio + invocación pública opcional
└── envs/
    └── dev/                 # compone los tres módulos; backend gcs, prefijo envs/dev
.github/workflows/plan.yml   # plan en PR con la SA plan
Makefile                     # targets plan y apply por ENV
```

Los módulos se pasan datos por outputs: la URL del repositorio, los ids de los secretos, la URL del servicio y el correo de la SA de runtime. `secrets` y `cloud-run-service` dependen uno del otro (la SA nace en el segundo y los secretos en el primero). El [plan](./despliegue-dev-plan.md) explica cómo se resuelve.

### External Dependencies

- Imagen `hashicorp/terraform` fijada por digest en el `Makefile`, y provider `hashicorp/google` con `~>`.
- `google-github-actions/auth`, la misma Action y el mismo commit SHA que usa `verify-apply-sa.yml`.
- Variables de repositorio `WIF_PROVIDER` y `APPLY_SERVICE_ACCOUNT` (existen) y `PLAN_SERVICE_ACCOUNT` (nueva).

## User Stories

- Como mantenedor, quiero declarar un servicio de Cloud Run con tres módulos, para reutilizarlos en `prod` sin copiar código.
- Como revisor de un PR, quiero ver el `plan` de `dev` en el propio PR, para saber qué cambiaría antes de aprobar.
- Como mantenedor, quiero que la SA de runtime solo lea los secretos del servicio, para que una API comprometida no vea los de otros.
- Como mantenedor, quiero que el estado de `dev` viva en el bucket de bootstrap, para que dos personas no pisen el mismo `apply`.

## Testing Strategy

En infraestructura no hay cobertura de código. Todas las pruebas corren contra `dockyard2sail-dev`, salvo las estáticas.

| Nivel | Prueba | Resultado esperado |
|-------|--------|--------------------|
| Unit | `make validate` y `make trivy` sobre módulos y `envs/dev` | Sin errores ni hallazgos CRITICAL/HIGH |
| Integration | `make apply ENV=dev` y luego `make plan ENV=dev` | El segundo `plan` da 0 cambios |
| Integration | `curl` a la URL con `allow_unauthenticated = true` y con `false` | HTTP 200 y HTTP 403 |
| Integration | Secreto de prueba cargado con `gcloud` y montado; otro secreto sin dar acceso | El primero se ve como variable de entorno; con el segundo falla el despliegue, porque Cloud Run comprueba el acceso al desplegar |
| Integration | `terraform state show` del repositorio | Tiene las dos políticas de limpieza (la limpieza tarda cerca de un día en aplicarse, así que no se espera a ver borrados) |
| Integration | `gcloud projects get-iam-policy` | La SA de runtime no aparece con ningún rol de proyecto |
| E2E | PR de prueba que cambia un valor en `envs/dev` | El job `plan` muestra el cambio en el job summary |
| E2E | Rama descartable que intenta `apply` con la SA `plan` | `PERMISSION_DENIED` |

No hay pruebas de rendimiento, salvo el tiempo del job `plan` de la tabla de requisitos no funcionales.

## Boundaries & Constraints

### In Scope

- Los tres módulos, `envs/dev`, los targets `plan` y `apply` y `plan.yml`.
- El lockfile y la entrada de Dependabot de `envs/dev`, y el cambio de `lock-check` para que exija lockfile solo en directorios raíz.
- Ajustes al README, a `CLAUDE.md` y al `CHANGELOG.md`. Los ítems de la hoja de ruta se marcan solo cuando estén verificados en `dockyard2sail-dev`.
- Acotar los roles `iam.serviceAccountAdmin` e `iam.serviceAccountUser` de la SA `apply` (`serviceAccountUser` solo sobre la SA de runtime), o documentar por qué no se puede.

### Out of Scope

- `envs/prod`: el módulo se diseña para reutilizarlo, pero el entorno es otro spec.
- El workflow de `deploy` en `main`, y el build y el push de imágenes desde CI.
- `budget-alert`.
- Dominio propio, VPC, bases de datos, multi-región y balanceador.
- Cargar valores de secretos desde Terraform y comentar el `plan` en el PR.
- Las guías y los ADRs de `docs/`.

### Technical Constraints

- Terraform corre en Docker vía `make`; no se instala en la computadora.
- Los entornos son carpetas, no workspaces.
- Los `*.tfvars` con valores reales no se versionan; solo `terraform.tfvars.example`.
- Región `us-central1`, la del bucket de estado.

## Success Criteria

- [ ] `make apply ENV=dev` crea el repositorio, los secretos, la SA de runtime y el servicio, y un segundo `plan` da 0 cambios.
- [ ] `curl` a la URL del servicio de `dev` devuelve HTTP 200 con la imagen placeholder.
- [ ] Un PR de prueba muestra el `plan` en su job summary, y un `apply` con la SA `plan` falla con `PERMISSION_DENIED`.
- [ ] La SA de runtime lee solo los secretos que se le asignan y no tiene roles de proyecto.
- [ ] `make validate` y `make trivy` sin hallazgos CRITICAL/HIGH, y el CI en verde.
- [ ] La imagen de `dockyard2sail-py` se sube y se despliega siguiendo el procedimiento documentado.

## Implementation Plan

Ver [`despliegue-dev-plan.md`](./despliegue-dev-plan.md).

## Changelog

Sin cambios posteriores a la aprobación.

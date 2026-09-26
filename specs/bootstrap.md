---
title: Módulo bootstrap
status: approved
created: 2026-09-25
updated: 2026-09-26
issue: "#7"
---

# Módulo bootstrap

## Objective

Crear con Terraform, una sola vez por proyecto de GCP, lo que hace falta antes de cualquier otro módulo: el bucket que guarda el estado de Terraform, la federación de identidad de GitHub Actions (Workload Identity Federation, WIF) y dos service accounts (SA) de CI, una para `plan` y otra para `apply`. Sin este módulo, los entornos no tienen dónde guardar su estado y el pipeline no puede autenticarse sin llaves JSON.

## Context

`terraform/bootstrap/` es el primer ítem de la hoja de ruta del README. Hoy el repo no tiene código de Terraform. Los demás módulos dependen de este:

- `terraform/envs/dev` y `envs/prod` declaran su `backend "gcs"` sobre el bucket que crea bootstrap.
- Los workflows de GitHub Actions usan el provider de WIF y las SA para correr `plan` en cada PR y `apply` en cada merge a `main`.
- El primer `.terraform.lock.hcl` del repo sale de este módulo. Con él se puede agregar el `lock-check` que `CLAUDE.md` dejó pendiente.

Lo ejecuta una persona con permisos de administrador, desde su computadora, una vez por proyecto (el README prevé un proyecto por entorno). Es el único código del repo que no se aplica desde CI.

### Decisiones tomadas el 2026-09-25

| Tema | Decisión | Razón |
|------|----------|-------|
| Estado del propio bootstrap | El primer `apply` usa estado local; después `init -migrate-state` lo mueve al bucket que el módulo acaba de crear. | El bucket que guarda el estado lo crea este mismo módulo, así que no puede existir antes del primer `apply`. Migrar deja el estado versionado y recuperable. |
| Confianza de WIF | Dos SA. `plan` la puede usar cualquier ref del repositorio y solo lee. `apply` solo se puede usar desde `refs/heads/main` y escribe. | Un PR se autentica con `refs/pull/N/merge`, no con `main`. Con una sola SA habría que elegir entre bloquear el `plan` en PRs o darle escritura a cualquier PR. |
| SA de runtime (la que ejecuta la app) | La crea el módulo `cloud-run-service`, no bootstrap. | Bootstrap crea solo lo necesario antes del primer `plan`. Los permisos de runtime son por entorno y cambian con el servicio. |

## Requirements

### Functional Requirements

**Bucket de estado**

- [ ] Crea un bucket de Cloud Storage con versionado, acceso uniforme a nivel de bucket y acceso público prohibido. El versionado permite recuperar un estado dañado.
- [ ] Borra las versiones no vigentes con más de N días (variable, 90 por defecto), para que el bucket no crezca sin límite.

**Federación de identidad (WIF)**

- [ ] Crea un pool y un provider OIDC para GitHub (emisor `https://token.actions.githubusercontent.com`). El provider solo acepta tokens del repositorio indicado en `github_repository`.
- [ ] Si se define `github_repository_id` (el ID numérico del repositorio), el provider también lo exige. El nombre de un repositorio borrado puede reutilizarlo otra persona; el ID no. Es opcional y recomendado.

**Service accounts**

- [ ] SA `plan`: solo lectura sobre el proyecto y sobre el bucket. La puede usar cualquier ref del repositorio autorizado.
- [ ] SA `apply`: escritura sobre la infraestructura del template y sobre el bucket. Solo se puede usar desde la rama `main` del repositorio autorizado.

**Entradas, salidas y uso**

- [ ] Habilita las APIs de GCP que necesitan bootstrap y los módulos siguientes (`iam`, `iamcredentials`, `sts`, `cloudresourcemanager`, `serviceusage`, `storage`, `run`, `artifactregistry`, `secretmanager`).
- [ ] Todas las entradas son variables: `project_id`, `region`, `github_repository`, `github_repository_id`, `state_version_retention_days` y un prefijo de nombres. Se entrega un `terraform.tfvars.example`.
- [ ] Expone como outputs el nombre del bucket, el nombre completo del provider de WIF y el correo de cada SA.
- [ ] `make bootstrap PROJECT_ID=...` aplica con estado local y `make bootstrap-migrate PROJECT_ID=...` migra el estado al bucket. El procedimiento completo queda en el README del módulo.

### Non-Functional Requirements

- [ ] Seguridad: el código no crea llaves JSON (`google_service_account_key`).
- [ ] Seguridad: ninguna SA tiene `roles/owner` ni `roles/editor`. Cada rol asignado aparece en el código con un comentario que dice para qué se necesita.
- [ ] Seguridad: el permiso para usar la SA `apply` exige repositorio y rama `main`. Se verifica leyendo el `plan` y con una prueba desde un PR, que debe fallar.
- [ ] Calidad: `make validate` y `make trivy` sin hallazgos CRITICAL/HIGH.
- [ ] Reproducibilidad: providers con restricción `~>` y `.terraform.lock.hcl` versionado.
- [ ] Idempotencia: un segundo `terraform plan` justo después del `apply` da 0 cambios.
- [ ] Costo: ningún recurso con costo fijo mensual (sin Cloud KMS, VPC ni IP reservada).

## Architecture

### Components

Todo el código vive en `terraform/bootstrap/`:

| Archivo | Qué contiene |
|---------|--------------|
| `versions.tf` | Versión de Terraform y del provider `google`. |
| `variables.tf` | Las entradas del módulo. |
| `apis.tf` | Las APIs habilitadas. |
| `state_bucket.tf` | El bucket de estado. |
| `wif.tf` | El pool y el provider de WIF. |
| `service_accounts.tf` | Las SA `plan` y `apply`, sus roles y quién puede usarlas. |
| `outputs.tf` | Bucket, provider de WIF y correos de las SA. |
| `terraform.tfvars.example` | Valores de ejemplo, sin datos reales. |
| `backend.tf.example` | Plantilla del backend remoto que se usa al migrar el estado. |
| `README.md` | Prerrequisitos, ejecución única y migración. |

Cómo se autentica el pipeline una vez creado el módulo:

```
GitHub Actions ──token OIDC──▶ provider de WIF (valida el repositorio)
   ├─ cualquier ref del repo ──▶ usa la SA plan   (solo lectura)
   └─ refs/heads/main        ──▶ usa la SA apply  (escritura)
```

### Data Model

Bootstrap no guarda datos propios. Los recursos que crea están en la tabla de archivos de arriba.

### External Dependencies

- Terraform: la imagen `hashicorp/terraform` fijada por digest en el `Makefile`.
- Provider `hashicorp/google`, con restricción `~>` y la versión vigente al implementar.
- GitHub como emisor de tokens OIDC.
- Un proyecto de GCP con facturación y una persona con permisos de administrador para la ejecución única.

## User Stories

- Como mantenedor del template, quiero correr un comando por proyecto y tener listos el estado remoto y la identidad de CI, para no usar la consola.
- Como pipeline de CI en un PR, quiero autenticarme con permisos de solo lectura, para correr `terraform plan` sin poder modificar nada.
- Como pipeline de CI en `main`, quiero usar una SA con permisos de escritura, para correr `terraform apply` después del merge.
- Como mantenedor, quiero que un fork o una rama ajena nunca obtenga permisos de escritura, para que el acceso al repositorio no se convierta en acceso a la infraestructura.

## Testing Strategy

En infraestructura no hay cobertura de código. La verificación tiene tres niveles.

### Unit Tests

Verificación estática sobre `terraform/bootstrap/`: `make validate` y `make trivy`.

### Integration Tests

Contra un proyecto de GCP `dev` real:

- `make bootstrap` seguido de un segundo `plan` que debe dar 0 cambios.
- `make bootstrap-migrate`: el estado queda en el bucket, `terraform state list` funciona y el objeto tiene al menos 2 versiones después de un segundo cambio.

### E2E Tests

Un workflow de prueba en una rama descartable:

- Desde un PR obtiene la SA `plan`. Intentar usar la SA `apply` falla con `PERMISSION_DENIED`.
- Desde `main` obtiene la SA `apply`.

Las pruebas de rendimiento no aplican a este módulo.

## Boundaries & Constraints

### In Scope

- El módulo `terraform/bootstrap/` y su README.
- Los targets `bootstrap` y `bootstrap-migrate` del `Makefile`.
- El primer `.terraform.lock.hcl`.
- La entrada en `CHANGELOG.md` bajo `[Unreleased]`. El ítem del README se marca solo cuando el módulo esté verificado en un proyecto real.

### Out of Scope

- Los módulos `cloud-run-service`, `artifact-registry`, `secrets` y `budget-alert`, y los entornos `dev` y `prod`.
- La SA de runtime.
- Los workflows de `plan` y `deploy`. Son el siguiente ítem de la hoja de ruta; este módulo solo produce los outputs que van a usar.
- Crear el proyecto de GCP y su facturación. Es un prerrequisito manual que se documenta.
- VPC, Cloud KMS (cifrado del bucket con llave propia) y multi-región.

### Technical Constraints

- Terraform corre en Docker vía `make`; no se instala en la computadora.
- Los entornos son carpetas, no workspaces. Bootstrap se parametriza por `project_id`.
- Los `*.tfvars` con valores reales no se versionan; solo `terraform.tfvars.example`.
- Nunca se commitea `*.tfstate`. El estado local del primer `apply` está en `.gitignore` y se elimina después de migrar.
- Las dependencias de terceros se fijan por SHA o digest, como en el resto del repo.

## Success Criteria

- [ ] `make validate` y `make trivy` pasan sobre `terraform/bootstrap/` sin hallazgos CRITICAL/HIGH.
- [ ] `make bootstrap PROJECT_ID=<proyecto-dev>` deja el proyecto listo en una ejecución, sin pasos en la consola.
- [ ] Después de migrar, el estado está en el bucket y el objeto tiene al menos 2 versiones tras un segundo `apply` con cambios.
- [ ] Un segundo `terraform plan` después del `apply` da 0 cambios.
- [ ] Desde un PR de prueba, WIF entrega la SA `plan` y falla al usar la SA `apply`. Desde `main` entrega la SA `apply`.
- [ ] No existe ninguna llave JSON ni `roles/owner` ni `roles/editor` en el código ni en el IAM resultante.
- [ ] `.terraform.lock.hcl` está versionado y el CI pasa (`fmt`, `validate`, `license-check`, `trivy-fs`).

## Implementation Plan

Ver [`specs/bootstrap-plan.md`](./bootstrap-plan.md).

## Changelog

<!-- Only used once this spec has shipped (status reached `completed`) and gets touched again. Before editing Requirements/Architecture above, append a dated entry here using delta markers, so the audit trail survives the in-place rewrite. Leave empty until the first post-completion change. -->

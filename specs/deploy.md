---
title: Workflow de deploy en main
status: approved
created: 2026-10-02
updated: 2026-10-02
issue: ""
---

# Workflow de deploy en main

## Objective

Que cada merge a `main` que cambie Terraform aplique `envs/dev` desde GitHub Actions con la service account (SA) `apply`, sin que nadie corra `make apply` a mano ni exista una credencial de larga vida. Cierra el ciclo "PR → `plan` → merge → `apply`" que `CLAUDE.md` describe y que hoy está a medias: el `plan` existe, el `apply` no.

## Context

`plan.yml` ya muestra el `plan` de `dev` en cada PR con la SA `plan` (solo lectura). `verify-apply-sa.yml` ya probó que una ejecución sobre `refs/heads/main` obtiene la SA `apply` por Workload Identity Federation (WIF). Falta el workflow que usa esa SA para aplicar. Hoy el `apply` lo hace una persona desde su computadora (decisión del spec [`despliegue-dev`](./despliegue-dev.md), que lo dejó para este).

### Decisiones tomadas el 2026-10-02

| Tema | Decisión | Razón |
|------|----------|-------|
| Alcance | Solo `terraform apply` de `envs/dev`. El build y el push de la imagen quedan fuera. | Este repo no tiene código de aplicación ni `Dockerfile`: la imagen sale de `dockyard2sail-py`. Construirla aquí exigiría un checkout entre repos y darle a la SA `apply` permisos que hoy no necesita. El README (línea "build + push + deploy") se corrige para decirlo. |
| Disparo | Automático tras el merge, sin aprobación manual. | La compuerta ya es el PR: `main` exige checks y aplica `enforce_admins`. Un Environment con reviewers añadiría una segunda aprobación a un entorno de pruebas. Se reconsidera para `prod`. |
| Plan y apply | Un solo job: `plan -out` y luego `apply` de ese plan. | Se aplica exactamente lo que el job mostró, no un segundo cálculo. |

## Requirements

### Functional Requirements

- [ ] `deploy.yml` corre en `push` a `main` cuando cambian `terraform/**`, el `Makefile` o el propio workflow, y también con `workflow_dispatch`.
- [ ] El job se autentica como la SA `apply` por WIF con las variables de repositorio que ya existen (`WIF_PROVIDER`, `APPLY_SERVICE_ACCOUNT`, `GCP_PROJECT_ID`). No se crea ninguna variable ni secreto nuevo.
- [ ] Un target `make apply-ci ENV=dev PROJECT_ID=...` corre `init`, `plan -out` y `apply` del plan guardado, con Terraform en Docker y el token en `GOOGLE_OAUTH_ACCESS_TOKEN` (como `plan-ci`). Recibe `ENV`, para que `prod` lo reutilice.
- [ ] El job publica en el job summary el plan y el resultado del `apply`.
- [ ] Un `concurrency` con grupo por entorno y `cancel-in-progress: false` evita dos `apply` a la vez y no corta uno a medias.
- [ ] Si el `apply` falla, el workflow falla y el estado queda como Terraform lo dejó (sin reintentos automáticos).

**Documentación**

- [ ] README: el ítem "Workflow de `deploy` en `main`" de la hoja de ruta se marca al verificarlo, y el texto "build + push + deploy" se corrige a "`terraform apply` al hacer merge; la imagen se despliega desde el repo de la aplicación".
- [ ] `terraform/envs/dev/README.md`: `apply` desde CI como camino normal y `make apply` local como excepción. Se documenta que CI ve solo lo versionado (ver restricciones).
- [ ] `CLAUDE.md`, `CHANGELOG.md` (`[Unreleased]`) y la sección de estado reflejan que el workflow existe.

### Non-Functional Requirements

| Área | Requisito |
|------|-----------|
| Seguridad | `permissions: contents: read` a nivel de workflow y `id-token: write` solo en el job que se autentica. Evento `push` y `workflow_dispatch`, nunca `pull_request_target`. |
| Seguridad | Cada Action de terceros va pineada por commit SHA con el tag en un comentario, y `google-github-actions/auth` usa el mismo SHA que `plan.yml`. |
| Seguridad | Sin llaves JSON ni `create_credentials_file`. El token de acceso no se imprime ni se escribe en el summary. |
| Seguridad | Una ejecución de `deploy.yml` desde una rama distinta de `main` no obtiene la SA `apply` (la restricción la impone WIF, no el workflow). |
| Calidad | `make validate` y `make trivy` sin hallazgos CRITICAL/HIGH, y el CI en verde. |
| Idempotencia | Tras un `deploy` exitoso, `make plan ENV=dev` da 0 cambios. |
| Rendimiento | Un `deploy` sin cambios de infraestructura termina en menos de 5 minutos con la caché de Docker vacía. |

## Architecture

### Components

```
.github/workflows/deploy.yml   # push a main → auth como SA apply → make apply-ci
Makefile                       # target nuevo: apply-ci (init + plan -out + apply del plan)
```

Flujo: PR (`plan.yml`, SA `plan`) → revisión → merge → `deploy.yml` (SA `apply`, solo desde `refs/heads/main`) → estado en el bucket `<proyecto>-tfstate`.

### External Dependencies

- `google-github-actions/auth` y `actions/checkout`, los mismos commits SHA que `plan.yml`.
- Imagen `hashicorp/terraform` fijada por digest en el `Makefile`.
- Variables de repositorio `WIF_PROVIDER`, `APPLY_SERVICE_ACCOUNT` y `GCP_PROJECT_ID` (existen).

## User Stories

- Como mantenedor, quiero que el merge de un PR de Terraform aplique `dev` solo, para que el estado real coincida con `main` sin pasos manuales.
- Como revisor, quiero que lo que se aplica sea el plan que el job mostró, para no aprobar una cosa y desplegar otra.
- Como mantenedor, quiero que solo `main` pueda aplicar, para que un PR o una rama no toquen infraestructura.

## Testing Strategy

Todas las pruebas corren contra `dockyard2sail-dev`, salvo las estáticas.

| Nivel | Prueba | Resultado esperado |
|-------|--------|--------------------|
| Unit | `make validate` y `make trivy` | Sin errores ni hallazgos CRITICAL/HIGH |
| Integration | Merge del PR que añade `deploy.yml` (su propio cambio lo dispara) | El job termina en verde. Si el plan no tiene cambios, el `apply` informa 0 cambios |
| E2E | PR posterior con un cambio inocuo y visible en `envs/dev` (la descripción del repositorio de Artifact Registry, que se actualiza en sitio) | `plan.yml` lo muestra en el PR, y tras el merge `deploy.yml` lo aplica y lo muestra en el summary |
| Integration | `make plan ENV=dev` después del E2E | 0 cambios |
| Integration | `gh workflow run deploy.yml --ref <rama distinta de main>` | Falla en el paso de autenticación, sin obtener la SA `apply` |

No hay pruebas de cobertura de código: no hay código de aplicación.

## Boundaries & Constraints

### In Scope

- `deploy.yml` y el target `apply-ci`.
- Ajustes al README, `CLAUDE.md`, `terraform/envs/dev/README.md` y `CHANGELOG.md`.

### Out of Scope

- Build y push de la imagen, y `gcloud run deploy`: viven en `dockyard2sail-py`.
- `envs/prod` y su compuerta de aprobación: `apply-ci` ya recibe `ENV`, pero el entorno es otro spec.
- `budget-alert`.
- Detección de drift programada y notificaciones fuera de las que GitHub ya envía cuando un workflow falla.
- Retirar `verify-apply-sa.yml`: se decide cuando `deploy.yml` esté verificado.
- Cambiar los roles de la SA `apply` salvo que la prueba de integración muestre un permiso faltante (ver riesgo en el plan).

### Technical Constraints

- Terraform corre en Docker vía `make`; el workflow no instala Terraform.
- CI solo ve lo versionado: `terraform.tfvars` no se versiona, así que un valor que `dev` necesite en CI debe ser el `default` de la variable o venir de `TF_VAR_*`. Con `terraform.tfvars` local distinto de los defaults, el primer `deploy` revertiría esa diferencia.
- La SA `apply` solo se obtiene desde `refs/heads/main` (atributo `repo_ref` del provider de WIF).
- `main` exige los checks `fmt`, `validate`, `lock-check`, `license-check`, `trivy-fs` y `gitleaks`. `deploy.yml` corre después del merge, así que no es un check requerido.

## Success Criteria

- [ ] Tras el merge de un cambio en `terraform/envs/dev`, `deploy.yml` aplica el cambio sin intervención y el summary muestra el plan y el resultado.
- [ ] `make plan ENV=dev` después de un `deploy` da 0 cambios.
- [ ] Un `workflow_dispatch` sobre una rama distinta de `main` falla al autenticarse.
- [ ] `deploy.yml` cumple los requisitos de seguridad (permisos mínimos, SHA pineados, sin llaves) y `make validate`, `make trivy` y el CI pasan.
- [ ] El README marca el workflow como existente solo después de esa verificación, y su texto ya no promete build ni push de imagen desde este repo.

## Implementation Plan

Ver [`deploy-plan.md`](./deploy-plan.md).

## Changelog

Sin cambios posteriores a la aprobación.

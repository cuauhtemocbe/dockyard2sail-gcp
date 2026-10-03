# Implementation Plan: Workflow de deploy en main

**Spec**: [deploy.md](./deploy.md)  
**Issue**: #29 (T1 a T5: #30 a #34)  
**Created**: 2026-10-02
**Status**: approved

## Components

### 1. Target `apply-ci` del `Makefile`
- **Purpose**: `init`, `plan -out` y `apply` del plan guardado, con Terraform en Docker y el token en `GOOGLE_OAUTH_ACCESS_TOKEN` (variante `TF_TOKEN`, como `plan-ci`). A diferencia de `plan-ci`, toma el bloqueo de estado: la SA `apply` sí puede escribir en el bucket.
- **Files**: `Makefile`
- **Effort**: S

### 2. Workflow `deploy.yml`
- **Purpose**: `push` a `main` (rutas `terraform/**`, `Makefile` y el propio workflow) y `workflow_dispatch`. Se autentica como la SA `apply`, corre `make apply-ci`, publica plan y resultado en el job summary. `concurrency` por entorno sin cancelar.
- **Files**: `.github/workflows/deploy.yml`
- **Effort**: M

### 3. Documentación
- **Purpose**: README (hoja de ruta y texto "build + push + deploy"), `terraform/envs/dev/README.md`, `CLAUDE.md` y `CHANGELOG.md`.
- **Files**: `README.md`, `terraform/envs/dev/README.md`, `CLAUDE.md`, `CHANGELOG.md`
- **Effort**: S

## Dependencies

### Build Order
1. Target `apply-ci` (lo usa el workflow).
2. `deploy.yml`.
3. Verificación en `main` (no se puede hacer antes: la SA `apply` solo se obtiene desde `main`).
4. Documentación, al final: el README marca el workflow como existente solo con la verificación hecha.

### External Dependencies

- Variables de repositorio `WIF_PROVIDER`, `APPLY_SERVICE_ACCOUNT` y `GCP_PROJECT_ID`: ya existen.
- `gh` autenticado, para lanzar `workflow_dispatch` en la prueba negativa.

## Risks & Assumptions

### Risks

| Riesgo | Mitigación |
|--------|------------|
| El primer `apply` desde CI falla por un permiso que la SA `apply` no tiene (nunca ha aplicado `envs/dev`; solo ha obtenido el token). | Es la prueba de integración. Si falla, el error nombra el permiso y se corrige en `bootstrap` en un PR aparte, sin ampliar roles por adelantado. |
| El PR de `deploy.yml` se dispara a sí mismo al mergear con un `apply` real. | Es inocuo si `main` y el estado coinciden: el plan debe dar 0 cambios. Se corre `make plan ENV=dev` antes de mergear para saberlo. Si da cambios, se resuelven antes. |
| `terraform.tfvars` local distinto de los defaults: CI aplicaría los defaults. | Hoy no tiene valores activos. Se confirma en el mismo `make plan` previo y se documenta la regla. |
| Entre el `plan` del PR y el merge puede entrar otro cambio. | El job vuelve a planear y aplica ese plan, no el del PR. El summary lo muestra. |
| Un fallo a medias deja `dev` parcialmente aplicado. | Terraform conserva lo creado en el estado, el workflow falla y el siguiente merge o `workflow_dispatch` reintenta. Sin reintentos automáticos. |

### Assumptions

- El atributo `repo_ref = repositorio@refs/heads/main` del provider de WIF acepta ejecuciones por `push` y por `workflow_dispatch` lanzado sobre `main`. `verify-apply-sa.yml` ya probó el primer caso.
- `main` protegida con `enforce_admins` impide que el `push` a `main` ocurra sin PR, así que el disparo es siempre un merge revisado.

## Milestones

- [ ] M1: `make validate` y `make trivy` pasan con `apply-ci` y `deploy.yml`.
- [ ] M2: el merge del PR 1 dispara `deploy.yml` y termina en verde con 0 cambios.
- [ ] M3: la prueba negativa (`workflow_dispatch` desde otra rama) falla al autenticarse.
- [ ] M4: un cambio real en `envs/dev` se aplica tras el merge y `make plan ENV=dev` da 0 cambios.
- [ ] M5: documentación y hoja de ruta actualizadas con lo verificado.

## Tasks

**Slicing strategy**: Mixed. El target `apply-ci` es la fundación que el workflow necesita, y los dos van en el mismo PR porque `deploy.yml` sin su target no corre. Lo demás son cortes verticales que se verifican solos, ordenados por riesgo: primero el `apply` real (el permiso que puede faltar), luego la prueba negativa y el cambio de extremo a extremo, y la documentación al final porque depende de que todo esté verificado.

El detalle de cada tarea vive en su issue, para no mantenerlo en dos lugares.

| Tarea | Qué entrega | PR | Esfuerzo | Depende de | Hito |
|-------|-------------|----|----------|------------|------|
| T1 | Target `apply-ci` en el `Makefile` | 1 | S | nada | M1 |
| T2 | `deploy.yml` y su primer `apply` desde `main` (0 cambios) | 1 | M | T1 | M1, M2 |
| T3 | Prueba negativa: `workflow_dispatch` desde una rama distinta de `main` | sin PR | XS | T2 mergeado | M3 |
| T4 | Cambio real en `envs/dev` (descripción del repositorio de Artifact Registry) aplicado por `deploy.yml` | 2 | S | T2 mergeado | M4 |
| T5 | Documentación y cierre del spec | 3 | S | T3, T4 | M5 |

T5 va en un PR aparte porque el README solo se marca al ver el `apply` de T4 en verde.

## Effort Estimate

**Total estimado**: 1 día de trabajo, repartido en 3 PRs. Casi todo el tiempo está en esperar los runs de CI y en la verificación sobre `dockyard2sail-dev`.

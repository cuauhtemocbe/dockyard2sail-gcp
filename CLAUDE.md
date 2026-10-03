# CLAUDE.md

Guía de instrucciones para Claude Code al trabajar en este repositorio.

Stack: Terraform sobre Google Cloud (Cloud Run, Artifact Registry, Secret Manager, Workload Identity Federation), GitHub Actions. Ver `README.md` para el alcance y la arquitectura prevista, y `Makefile` para los comandos.

**Estado:** en construcción. Hoy el repo tiene documentación, tooling, CI, `terraform/bootstrap/`, los módulos `cloud-run-service`, `artifact-registry` y `secrets`, el entorno `terraform/envs/dev` y el workflow `plan.yml` (plan en PR). Todavía no existen el entorno `prod`, `budget-alert` ni el workflow de `deploy` en `main`. No describir como hecho lo que solo está planeado.

---

## Comandos

Todo corre en Docker vía `make` (`make help` los lista). Terraform usa la imagen `hashicorp/terraform` fijada por digest en el `Makefile`.

```bash
make fmt-check      # terraform fmt -check -recursive
make validate-tf    # init -backend=false + validate en cada directorio con .tf
make lock-check     # cada directorio raíz (bootstrap y envs/*) tiene .terraform.lock.hcl sincronizado con sus providers; los módulos no llevan lockfile
make validate       # fmt-check + validate-tf + lock-check + license-check (lo que corre el pre-commit)
make secrets-scan   # gitleaks sobre el diff staged
make secrets-history # gitleaks sobre todo el historial de git (lo que corre el job gitleaks de CI)
make trivy          # Trivy fs en Docker: vulnerabilidades + misconfiguraciones de IaC (SEVERITY=CRITICAL,HIGH por defecto)
make plan ENV=dev PROJECT_ID=...   # terraform plan del entorno (credenciales de gcloud)
make apply ENV=dev PROJECT_ID=...  # terraform apply del entorno; pide confirmación
make install-hooks  # habilitar .githooks/ (una vez por clon)
```

---

## Reglas no negociables

- **Nada de credenciales de larga vida.** Ni llaves JSON de service account, ni tokens en el repo o en los secrets de GitHub. La autenticación de CI es Workload Identity Federation (OIDC).
- **Mínimo privilegio.** Service accounts separadas para CI (despliegue) y runtime (la app). Nunca `roles/owner` ni `roles/editor`.
- **Todo cambio de infraestructura pasa por Terraform.** Nada de clics en la consola; si hubo que hacer algo a mano, se documenta y se lleva a código.
- **Estado remoto en Cloud Storage con versionado.** Nunca se commitea `*.tfstate` (está en `.gitignore`).
- **`.terraform.lock.hcl` sí se versiona**: fija las versiones de los providers.
- **`*.tfvars` con valores reales no se versionan**; se versiona un `*.tfvars.example`.
- **Entornos como carpetas** (`terraform/envs/dev`, `terraform/envs/prod`) sobre módulos compartidos, no workspaces.
- **`terraform apply` nunca se corre desde CI en un PR**: los PRs solo hacen `plan`; el `apply` ocurre al hacer merge a `main`.
- **`main` está protegida también para el owner** (`enforce_admins: true`): no se puede pushear directo ni saltarse los checks requeridos. Es deliberado: la SA `apply` se obtiene desde `main`, así que un push directo equivale a `apply` sin revisión. Si hay que saltarla, se desactiva `enforce_admins` de forma temporal y explícita, y se documenta en el commit o el PR.
- **Actions de terceros pineadas por commit SHA** (con el tag en un comentario) y `permissions:` mínimo explícito por workflow/job.

---

## Flujo de trabajo

### Cambios nuevos

1. Para una feature con varias piezas, usar `/spec-driven-dev` (idea → spec → plan → tareas).
2. Trabajar en una rama (`feat/...`, `chore/...`), nunca directo a `main`.
3. Antes de commitear: `make validate` y `make trivy`.
4. Commitear con Conventional Commits.
5. Esperar confirmación explícita antes de hacer push o abrir el PR.

### Bugfixes

1. Reproducir el problema (un `plan` que falla, un `validate` en rojo).
2. Arreglarlo.
3. Verificar con `make validate`.
4. Documentar la causa en el commit.

---

## Antes de mergear

- [ ] `make validate` pasa.
- [ ] `make trivy` sin hallazgos CRITICAL/HIGH (o excepción documentada con fecha de revisión).
- [ ] El job de CI está en verde (`fmt`, `validate`, `lock-check`, `license-check`, `trivy-fs`, `gitleaks`).
- [ ] `CHANGELOG.md` actualizado bajo `[Unreleased]`.
- [ ] El README refleja lo que realmente existe, no solo lo planeado.

---

## Sobre los estándares de desarrollo

Este repo sigue el estándar personal de `meta-projects/docs/development-standards.md`, adaptado a infraestructura como código:

- **Docker-first**: aplica a las herramientas (Terraform, gitleaks), no a un contenedor de aplicación: aquí no hay imagen de aplicación que construir.
- **Sin `Dockerfile`, `docker-compose.yml`, linter de Python ni cobertura**: no hay código de aplicación. Se reintroducen solo si aparece uno.
- **Sin job de `build` gateado**: no hay imagen de aplicación que construir ni escanear. El `lock-check` sí existe (`make lock-check`).
- **Imágenes de herramientas del `Makefile` fijadas por digest y actualizadas a mano**: Dependabot no las ve, y moverlas a un `Dockerfile` solo para que las lea añadiría una capa sin otro uso.
- **SonarQube**: herramienta personal de desarrollo local, no un gate de CI. `sonar-project.properties` analiza `terraform/`. Los workflows de `.github/` quedan fuera: el SonarQube local no trae el analizador de GitHub Actions (su lenguaje `githubactions` no existe en la instancia). Los revisa Trivy.

Cada una de estas exclusiones es deliberada y debe revisarse cuando cambie el alcance del repo.

---

## Escritura

Todo lo que se redacta para que otra persona lo lea (specs, planes, issues, README, respuestas largas) sigue `meta-projects/.claude/skills/antislop/SKILL.md`. Este repo no tiene copia de ese skill, así que la regla de carga cognitiva queda aquí:

- **Lo que el lector debe decidir o hacer va primero**, antes del contexto.
- **Una idea por párrafo o viñeta**, y cada viñeta lleva su razón, no una etiqueta.
- **Tabla para comparar, prosa para explicar.**
- **Un nombre por cosa**: se define cada sigla la primera vez y no se alterna con sinónimos.
- **No se repite lo que otro documento ya dice, se enlaza.** Un plan no copia el spec.
- **Sin secciones vacías.**

---

## Memoria (Engram)

Guardar decisiones de arquitectura, bugs resueltos y gotchas no obvios con `mem_save`. Tras una compactación de contexto, llamar `mem_context` antes de continuar.

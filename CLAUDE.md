# CLAUDE.md

Guía de instrucciones para Claude Code al trabajar en este repositorio.

Stack: Terraform sobre Google Cloud (Cloud Run, Artifact Registry, Secret Manager, Workload Identity Federation), GitHub Actions. Ver `README.md` para el alcance y la arquitectura prevista, y `Makefile` para los comandos.

**Estado:** en diseño. Hoy el repo solo tiene documentación, tooling y CI; el código de Terraform (`terraform/`) todavía no existe. No describir como hecho lo que solo está planeado.

---

## Comandos

Todo corre en Docker vía `make` (`make help` los lista). Terraform usa la imagen `hashicorp/terraform` fijada por digest en el `Makefile`.

```bash
make fmt-check      # terraform fmt -check -recursive
make validate-tf    # init -backend=false + validate en cada directorio con .tf
make validate       # fmt-check + validate-tf + license-check (lo que corre el pre-commit)
make secrets-scan   # gitleaks sobre el diff staged
make trivy          # Trivy fs: vulnerabilidades + misconfiguraciones de IaC (requiere trivy en el PATH)
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
- [ ] El job de CI está en verde (`fmt`, `validate`, `license-check`, `trivy-fs`).
- [ ] `CHANGELOG.md` actualizado bajo `[Unreleased]`.
- [ ] El README refleja lo que realmente existe, no solo lo planeado.

---

## Sobre los estándares de desarrollo

Este repo sigue el estándar personal de `meta-projects/docs/development-standards.md`, adaptado a infraestructura como código:

- **Docker-first**: aplica a las herramientas (Terraform, gitleaks), no a un contenedor de aplicación: aquí no hay imagen de aplicación que construir.
- **Sin `Dockerfile`, `docker-compose.yml`, linter de Python ni cobertura**: no hay código de aplicación. Se reintroducen solo si aparece uno.
- **Sin `lock-check` ni job de `build` gateado**: el lockfile de providers aparecerá con el primer módulo, y no hay imagen que construir ni escanear.
- **SonarQube**: herramienta personal de desarrollo local, no un gate de CI.

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

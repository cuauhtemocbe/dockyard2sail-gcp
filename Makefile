# Latest hashicorp/terraform as of 2026-09-25, pinned by digest for reproducible runs.
# Bump it deliberately (docker pull hashicorp/terraform:latest, copy the new digest).
TERRAFORM_IMAGE ?= hashicorp/terraform@sha256:985cdc6c1d9b0a65b83377f666efd2f740b47f02ac55be1ced3d18f7d3b0e829
GITLEAKS_IMAGE  ?= zricethezav/gitleaks@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f

# Terraform corre dentro de Docker con el uid del host, para no dejar archivos root en el repo.
TF = docker run --rm -u $$(id -u):$$(id -g) -e HOME=/tmp -v "$(CURDIR):/workspace" -w /workspace $(TERRAFORM_IMAGE)

.DEFAULT_GOAL := help
.PHONY: help fmt fmt-check validate-tf license-check validate secrets-scan trivy install-hooks

fmt: ## Formatear todos los .tf con terraform fmt
	$(TF) fmt -recursive

fmt-check: ## Verificar formato de los .tf sin modificarlos
	$(TF) fmt -check -recursive -diff

validate-tf: ## terraform init -backend=false + validate en cada directorio con .tf (no-op si aún no hay)
	@dirs=$$(find terraform -name '*.tf' -not -path '*/.terraform/*' -exec dirname {} \; 2>/dev/null | sort -u); \
	if [ -z "$$dirs" ]; then echo "validate-tf: aún no hay archivos .tf, nada que validar"; exit 0; fi; \
	for d in $$dirs; do \
		echo "==> $$d"; \
		$(TF) -chdir=$$d init -backend=false -input=false >/dev/null && $(TF) -chdir=$$d validate || exit 1; \
	done

license-check: ## Verificar que exista el archivo LICENSE
	test -f LICENSE

validate: fmt-check validate-tf license-check ## Suite completa de validación (fmt-check + validate + license-check)

secrets-scan: ## Escanear el diff staged con gitleaks (mismo check que el pre-commit)
	docker run --rm -v "$(CURDIR):/repo" -w /repo $(GITLEAKS_IMAGE) protect --staged --redact -v

trivy: ## Escanear vulnerabilidades y misconfiguraciones de IaC con Trivy (requiere trivy en el PATH)
	trivy fs . --scanners vuln,misconfig --severity CRITICAL,HIGH --exit-code 1 --ignore-unfixed

install-hooks: ## Habilitar los git hooks (pre-commit: validate + gitleaks; pre-push: gate de Trivy)
	git config core.hooksPath .githooks
	chmod +x .githooks/*

help: ## Mostrar esta ayuda
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

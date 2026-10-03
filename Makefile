# hashicorp/terraform latest as of 2026-09-25 (Terraform v1.16.4), pinned by digest for reproducible runs.
# Bump it deliberately (docker pull hashicorp/terraform:latest, copy the new digest and update the version above).
# Dependabot does not see these images, so they are bumped by hand.
TERRAFORM_IMAGE ?= hashicorp/terraform@sha256:985cdc6c1d9b0a65b83377f666efd2f740b47f02ac55be1ced3d18f7d3b0e829
GITLEAKS_IMAGE  ?= zricethezav/gitleaks@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f
# aquasec/trivy latest as of 2026-10-02 (Trivy v0.75.0), pinned by digest. Bumped by hand like the others.
TRIVY_IMAGE     ?= aquasec/trivy@sha256:af6acf9a6b85dfe389a1941505c0ce9efef52a4719635e1a962f022a3d855daa

# Terraform corre dentro de Docker con el uid del host, para no dejar archivos root en el repo.
TF = docker run --rm -u $$(id -u):$$(id -g) -e HOME=/tmp -v "$(CURDIR):/workspace" -w /workspace $(TERRAFORM_IMAGE)

# Variante para validate-tf: usa su propio directorio de datos (.terraform-validate) para que un
# backend ya inicializado en .terraform/ (tras bootstrap-migrate) no exija credenciales al validar.
TF_VALIDATE = docker run --rm -u $$(id -u):$$(id -g) -e HOME=/tmp -e TF_DATA_DIR=/workspace/$$d/.terraform-validate -v "$(CURDIR):/workspace" -w /workspace $(TERRAFORM_IMAGE)

# Variante para bootstrap: monta solo el archivo de credenciales de gcloud (application default
# credentials), en solo lectura, y lo expone a Terraform. -it solo si hay terminal: apply pide
# confirmación y necesita una; init -migrate-state -force-copy no. Si GOOGLE_IMPERSONATE_SERVICE_ACCOUNT
# está definida en tu shell, Terraform actúa como esa SA (así se prueba lo que puede hacer `apply`).
GCLOUD_ADC ?= $(HOME)/.config/gcloud/application_default_credentials.json
TF_ADC = docker run --rm $$([ -t 0 ] && echo -it) -u $$(id -u):$$(id -g) -e HOME=/tmp \
	-e GOOGLE_APPLICATION_CREDENTIALS=/gcloud/adc.json -e GOOGLE_IMPERSONATE_SERVICE_ACCOUNT -v "$(GCLOUD_ADC):/gcloud/adc.json:ro" \
	-v "$(CURDIR):/workspace" -w /workspace $(TERRAFORM_IMAGE)
# Variante para CI: toma un token de acceso de la variable de entorno GOOGLE_OAUTH_ACCESS_TOKEN
# (lo emite la SA `plan` por WIF) en vez de un archivo de credenciales.
TF_TOKEN = docker run --rm -u $$(id -u):$$(id -g) -e HOME=/tmp -e GOOGLE_OAUTH_ACCESS_TOKEN \
	-v "$(CURDIR):/workspace" -w /workspace $(TERRAFORM_IMAGE)
BOOTSTRAP_DIR = terraform/bootstrap
# Valores de bootstrap que en local vienen de terraform.tfvars (no versionado) y en CI se pasan por -var.
# GITHUB_REPOSITORY y GITHUB_REPOSITORY_ID los define el workflow; REGION es la de terraform.tfvars.example.
REGION ?= us-central1
ENV_DIR = terraform/envs/$(ENV)

.DEFAULT_GOAL := help
.PHONY: help fmt fmt-check validate-tf lock-check license-check validate secrets-scan secrets-history trivy install-hooks \
	bootstrap bootstrap-migrate bootstrap-output plan plan-ci plan-bootstrap-ci drift-ci apply apply-ci _require-project-id _require-adc _require-env

fmt: ## Formatear todos los .tf con terraform fmt
	$(TF) fmt -recursive

fmt-check: ## Verificar formato de los .tf sin modificarlos
	$(TF) fmt -check -recursive -diff

validate-tf: ## terraform init -backend=false + validate en cada directorio con .tf (no-op si aún no hay)
	@dirs=$$(find terraform -name '*.tf' -not -path '*/.terraform/*' -exec dirname {} \; 2>/dev/null | sort -u); \
	if [ -z "$$dirs" ]; then echo "validate-tf: aún no hay archivos .tf, nada que validar"; exit 0; fi; \
	for d in $$dirs; do \
		echo "==> $$d"; \
		$(TF_VALIDATE) -chdir=$$d init -backend=false -input=false >/dev/null && $(TF_VALIDATE) -chdir=$$d validate || exit 1; \
	done

lock-check: ## Verificar que cada directorio raíz (bootstrap y envs/*) tenga .terraform.lock.hcl sincronizado con sus providers
	@dirs=$$(find terraform -name '*.tf' -not -path '*/.terraform*/*' -not -path 'terraform/modules/*' -exec dirname {} \; 2>/dev/null | sort -u); \
	if [ -z "$$dirs" ]; then echo "lock-check: aún no hay archivos .tf, nada que verificar"; exit 0; fi; \
	for d in $$dirs; do \
		echo "==> $$d"; \
		test -f $$d/.terraform.lock.hcl || { echo "Falta $$d/.terraform.lock.hcl"; exit 1; }; \
		$(TF_VALIDATE) -chdir=$$d init -backend=false -input=false -lockfile=readonly >/dev/null || exit 1; \
	done

license-check: ## Verificar que exista el archivo LICENSE
	test -f LICENSE

validate: fmt-check validate-tf lock-check license-check ## Suite completa de validación (fmt-check + validate + lock-check + license-check)

_require-project-id:
	@test -n "$(PROJECT_ID)" || { echo "Falta PROJECT_ID. Uso: make $(MAKECMDGOALS) PROJECT_ID=<proyecto>"; exit 1; }

_require-adc:
	@test -f "$(GCLOUD_ADC)" || { echo "No existe $(GCLOUD_ADC). Corre: gcloud auth application-default login"; exit 1; }

_require-env:
	@test -n "$(ENV)" || { echo "Falta ENV. Uso: make $(MAKECMDGOALS) ENV=<entorno> PROJECT_ID=<proyecto>"; exit 1; }
	@test -d "$(ENV_DIR)" || { echo "No existe $(ENV_DIR)"; exit 1; }

bootstrap: _require-project-id _require-adc ## Aplicar terraform/bootstrap con estado local (PROJECT_ID=...; el resto de variables va en terraform.tfvars)
	$(TF_ADC) -chdir=$(BOOTSTRAP_DIR) init -input=false
	$(TF_ADC) -chdir=$(BOOTSTRAP_DIR) apply -var project_id=$(PROJECT_ID)

bootstrap-migrate: _require-project-id _require-adc ## Migrar el estado de bootstrap al bucket que creó (PROJECT_ID=...)
	sed 's/<PROJECT_ID>/$(PROJECT_ID)/' $(BOOTSTRAP_DIR)/backend.tf.example > $(BOOTSTRAP_DIR)/backend.tf
	$(TF_ADC) -chdir=$(BOOTSTRAP_DIR) init -migrate-state -force-copy -input=false

bootstrap-output: _require-adc ## Mostrar los outputs de bootstrap (requiere haber migrado el estado al bucket)
	$(TF_ADC) -chdir=$(BOOTSTRAP_DIR) output

plan: _require-env _require-project-id _require-adc ## terraform plan de un entorno (ENV=dev PROJECT_ID=...); el bucket de estado es <PROJECT_ID>-tfstate
	$(TF_ADC) -chdir=$(ENV_DIR) init -input=false -backend-config="bucket=$(PROJECT_ID)-tfstate"
	$(TF_ADC) -chdir=$(ENV_DIR) plan -input=false -var project_id=$(PROJECT_ID)

plan-ci: _require-env _require-project-id ## plan para CI (ENV=dev PROJECT_ID=...): sin lock de estado y con token en GOOGLE_OAUTH_ACCESS_TOKEN
	@test -n "$$GOOGLE_OAUTH_ACCESS_TOKEN" || { echo "Falta GOOGLE_OAUTH_ACCESS_TOKEN"; exit 1; }
	$(TF_TOKEN) -chdir=$(ENV_DIR) init -input=false -backend-config="bucket=$(PROJECT_ID)-tfstate"
	$(TF_TOKEN) -chdir=$(ENV_DIR) plan -input=false -lock=false -no-color -var project_id=$(PROJECT_ID)

plan-bootstrap-ci: _require-project-id ## plan de terraform/bootstrap para CI (PROJECT_ID=... GITHUB_REPOSITORY=owner/repo GITHUB_REPOSITORY_ID=...): genera backend.tf, sin lock de estado
	@test -n "$$GOOGLE_OAUTH_ACCESS_TOKEN" || { echo "Falta GOOGLE_OAUTH_ACCESS_TOKEN"; exit 1; }
	@test -n "$(GITHUB_REPOSITORY)" || { echo "Falta GITHUB_REPOSITORY (owner/repo)"; exit 1; }
	@test -n "$(GITHUB_REPOSITORY_ID)" || { echo "Falta GITHUB_REPOSITORY_ID: sin él el plan mostraría un cambio falso en el provider de WIF"; exit 1; }
	sed 's/<PROJECT_ID>/$(PROJECT_ID)/' $(BOOTSTRAP_DIR)/backend.tf.example > $(BOOTSTRAP_DIR)/backend.tf
	$(TF_TOKEN) -chdir=$(BOOTSTRAP_DIR) init -input=false
	$(TF_TOKEN) -chdir=$(BOOTSTRAP_DIR) plan -input=false -lock=false -no-color -var project_id=$(PROJECT_ID) -var region=$(REGION) \
		-var github_repository=$(GITHUB_REPOSITORY) -var github_repository_id=$(GITHUB_REPOSITORY_ID)

# make devuelve 2 ante cualquier receta fallida, así que no sirve para distinguir drift (2 de terraform) de
# error (1). El código real se imprime en una línea que el workflow lee.
drift-ci: _require-env _require-project-id ## plan -detailed-exitcode para CI (ENV=dev PROJECT_ID=...): imprime terraform-plan-exitcode=N (0 sin cambios, 1 error, 2 drift)
	@test -n "$$GOOGLE_OAUTH_ACCESS_TOKEN" || { echo "Falta GOOGLE_OAUTH_ACCESS_TOKEN"; exit 1; }
	$(TF_TOKEN) -chdir=$(ENV_DIR) init -input=false -backend-config="bucket=$(PROJECT_ID)-tfstate" || { echo "terraform-plan-exitcode=1"; exit 1; }
	$(TF_TOKEN) -chdir=$(ENV_DIR) plan -input=false -lock=false -no-color -detailed-exitcode -var project_id=$(PROJECT_ID); rc=$$?; echo "terraform-plan-exitcode=$$rc"; exit $$rc

apply: _require-env _require-project-id _require-adc ## terraform apply de un entorno (ENV=dev PROJECT_ID=...); pide confirmación
	$(TF_ADC) -chdir=$(ENV_DIR) init -input=false -backend-config="bucket=$(PROJECT_ID)-tfstate"
	$(TF_ADC) -chdir=$(ENV_DIR) apply -var project_id=$(PROJECT_ID)

apply-ci: _require-env _require-project-id ## apply para CI (ENV=dev PROJECT_ID=...): plan -out y apply de ese plan, con token en GOOGLE_OAUTH_ACCESS_TOKEN
	@test -n "$$GOOGLE_OAUTH_ACCESS_TOKEN" || { echo "Falta GOOGLE_OAUTH_ACCESS_TOKEN"; exit 1; }
	$(TF_TOKEN) -chdir=$(ENV_DIR) init -input=false -backend-config="bucket=$(PROJECT_ID)-tfstate"
	$(TF_TOKEN) -chdir=$(ENV_DIR) plan -input=false -lock-timeout=60s -no-color -out=tfplan -var project_id=$(PROJECT_ID)
	@# Un plan guardado no pide confirmación. El archivo puede traer valores sensibles: se borra siempre (tfplan está en .gitignore).
	$(TF_TOKEN) -chdir=$(ENV_DIR) apply -input=false -lock-timeout=60s -no-color tfplan; rc=$$?; rm -f $(ENV_DIR)/tfplan; exit $$rc

secrets-history: ## Escanear todo el historial de git con gitleaks (lo que corre el job de CI)
	docker run --rm -v "$(CURDIR):/repo" -w /repo $(GITLEAKS_IMAGE) detect --redact -v

secrets-scan: ## Escanear el diff staged con gitleaks (mismo check que el pre-commit)
	docker run --rm -v "$(CURDIR):/repo" -w /repo $(GITLEAKS_IMAGE) protect --staged --redact -v

# Trivy corre en Docker con el uid del host. La base de vulnerabilidades se cachea en TRIVY_CACHE
# para no descargarla en cada corrida. El repo se monta en solo lectura. Los flags viven solo aquí:
# el pre-push solo cambia la severidad (make trivy SEVERITY=CRITICAL).
TRIVY_CACHE ?= $(HOME)/.cache/trivy
SEVERITY    ?= CRITICAL,HIGH

trivy: ## Escanear vulnerabilidades y misconfiguraciones de IaC con Trivy en Docker (SEVERITY=CRITICAL,HIGH por defecto)
	@mkdir -p "$(TRIVY_CACHE)"
	docker run --rm -u $$(id -u):$$(id -g) -e HOME=/tmp -v "$(TRIVY_CACHE):/tmp/.cache/trivy" -v "$(CURDIR):/workspace:ro" -w /workspace \
		$(TRIVY_IMAGE) fs . --scanners vuln,misconfig --severity $(SEVERITY) --exit-code 1 --ignore-unfixed

install-hooks: ## Habilitar los git hooks (pre-commit: validate + gitleaks; pre-push: gate de Trivy)
	git config core.hooksPath .githooks
	chmod +x .githooks/*

help: ## Mostrar esta ayuda
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

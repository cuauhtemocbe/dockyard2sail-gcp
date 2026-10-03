# Entorno `dev`

Crea en un proyecto de GCP el repositorio de imágenes, los secretos y el servicio de Cloud Run de `dockyard2sail-py`, con los módulos de `terraform/modules/`. Su estado vive en el bucket que creó [`bootstrap`](../../bootstrap/README.md), con el prefijo `envs/dev`.

## Antes de empezar

- `bootstrap` aplicado y su estado migrado al bucket (`make bootstrap` y `make bootstrap-migrate`).
- Credenciales de `gcloud` en tu computadora: `gcloud auth application-default login`.
- Opcional: copia `terraform.tfvars.example` a `terraform.tfvars` para cambiar `region` o la imagen inicial (nunca `secret_ids` ni `secret_env`: ver "Montar un secreto"). Ese archivo no se versiona. `project_id` no va ahí: lo pasa `make`.

## Planear y aplicar

El camino normal es CI:

1. En un PR que cambie `terraform/**`, `plan.yml` muestra el plan en el job summary, como la SA `plan` (solo lectura).
2. Al hacer merge a `main`, `deploy.yml` corre `make apply-ci`: vuelve a planear y aplica ese plan con la SA `apply` (WIF, solo desde `refs/heads/main`). El job summary muestra el plan y el resultado. Si falla, el workflow falla y no reintenta: el siguiente merge o un `workflow_dispatch` sobre `main` lo reintenta.

`make apply` desde tu computadora es la excepción (por ejemplo, si CI no puede correr):

```bash
make plan  ENV=dev PROJECT_ID=<proyecto>
make apply ENV=dev PROJECT_ID=<proyecto>   # pide confirmación
```

Un `plan` justo después de aplicar debe dar "No changes".

**CI ve solo lo versionado.** `terraform.tfvars` no se versiona, así que `deploy.yml` aplica los `default` de las variables. Si tu `terraform.tfvars` local da un `plan` distinto de los defaults (por ejemplo, con otra `region`), el primer `deploy` revertiría esa diferencia. Todo valor que `dev` necesite en CI debe ser el `default` de la variable o venir de `TF_VAR_*`.

El primer `apply` crea el servicio con una imagen de ejemplo (`image`). Después, Terraform **ignora** la imagen, `client` y `client_version`: la imagen la actualiza `gcloud run deploy`, y así un `plan` no la revierte al ejemplo.

## Montar un secreto (dos PRs)

`secret_ids` y `secret_env` viven en los `default` de [`variables.tf`](variables.tf), no en `terraform.tfvars`: así `plan.yml` y `deploy.yml` ven lo mismo que tú y el PR muestra el secreto que se crea o se quita. Hoy son `[]` y `{}`.

Cloud Run comprueba al desplegar que el secreto tiene al menos una versión y que la SA de runtime puede leerlo. Por eso el montaje va en dos PRs:

1. **PR 1, crear el secreto.** En `variables.tf`, cambia el `default` de `secret_ids` a `["mi-secreto"]`. Al hacer merge, `deploy.yml` crea el secreto vacío y da `roles/secretmanager.secretAccessor` sobre él a la SA de runtime. Después, carga el valor sin pasarlo por el código ni por Terraform:
   ```bash
   printf '%s' "<valor>" | gcloud secrets versions add mi-secreto --project <proyecto> --data-file=-
   ```
2. **PR 2, montarlo.** Cambia el `default` de `secret_env` a `{ MI_VARIABLE = "mi-secreto" }`. Al hacer merge, el servicio recibe la variable con la versión `latest`.

El valor nunca llega al código, al plan ni al estado.

**Quitar un id de `secret_ids` destruye el secreto y todas sus versiones**, y el valor se pierde porque solo existe en Secret Manager. Para quitarlo, primero quita la variable de `secret_env` (PR 1) y después el id de `secret_ids` (PR 2), y revisa el plan del PR antes de mezclar.

## Subir y desplegar la imagen

El repositorio de imágenes es `<region>-docker.pkg.dev/<proyecto>/dockyard2sail`. Desde el repo de la aplicación (por ejemplo, `dockyard2sail-py`):

```bash
gcloud auth configure-docker us-central1-docker.pkg.dev
IMG=us-central1-docker.pkg.dev/<proyecto>/dockyard2sail/dockyard2sail-py:$(git rev-parse --short HEAD)
docker build -t $IMG .
docker push $IMG
gcloud run deploy dockyard2sail-py --image $IMG --region us-central1 --project <proyecto>
```

- **No uses `--tag`** en `gcloud run deploy`: crea un tag de tráfico que Terraform no conoce y aparece como diferencia en el `plan`.
- **Usa un tag distinto por versión** (aquí, el hash corto del commit). El repositorio conserva las últimas 5 versiones (`keep_count`) y borra las sin tag con más de 7 días (`untagged_max_age_days`); la limpieza tarda cerca de un día en aplicarse.
- **Comprueba el despliegue:** `curl <service_url>/health` debe dar 200. La URL aparece al final de `make apply`.

## Cosas que conviene saber

- **`allow_unauthenticated = true` en `dev`**: el servicio acepta llamadas sin credenciales, para poder probarlo con `curl`. Con `false`, solo lo invocan identidades con `roles/run.invoker` y un `curl` sin credenciales da 403.
- **`min_instances` solo baja a 0 con `gcloud`.** El módulo escribe el bloque `scaling` únicamente si `min_instances > 0`, porque el provider no guarda el 0 en el estado. Si subes `min_instances` y luego lo quitas del código, el servicio sigue con instancias encendidas (y cuesta): bájalo con `gcloud run services update <servicio> --min-instances 0`.
- **`max_instances = 3` limita la escala de `dev`, no el gasto.** El servicio es público: sin tope, Cloud Run usa 100 instancias por revisión. Si quitas `max_instances` del código, el módulo deja de escribir `max_instance_count` y el servicio puede conservar el 3 (el provider quizá no lo restablezca): súbelo con `gcloud run services update <servicio> --max-instances 100`, o fíjalo explícitamente en el código.
- **La SA `apply` actúa como la SA de runtime** gracias al binding `serviceAccountUser` que crea el módulo para `deployers` (aquí, `<name_prefix>-apply@<proyecto>`). `name_prefix` debe coincidir con el de `bootstrap`.
- **Orden al quitar roles en `bootstrap`:** aplica primero `envs/dev` (crea el binding) y después `bootstrap`.
- **Para probar lo que puede hacer la SA `apply`**, define `GOOGLE_IMPERSONATE_SERVICE_ACCOUNT=<SA apply>` en tu shell: `make apply` lo pasa al contenedor. Requiere `roles/iam.serviceAccountTokenCreator` sobre esa SA; dalo solo mientras dure la prueba y documéntalo.

# Entorno `dev`

Crea en un proyecto de GCP el repositorio de imágenes, los secretos y el servicio de Cloud Run de `dockyard2sail-py`, con los módulos de `terraform/modules/`. Su estado vive en el bucket que creó [`bootstrap`](../../bootstrap/README.md), con el prefijo `envs/dev`.

## Antes de empezar

- `bootstrap` aplicado y su estado migrado al bucket (`make bootstrap` y `make bootstrap-migrate`).
- Credenciales de `gcloud` en tu computadora: `gcloud auth application-default login`.
- Opcional: copia `terraform.tfvars.example` a `terraform.tfvars` para cambiar `region` o la imagen inicial. Ese archivo no se versiona. `project_id` no va ahí: lo pasa `make`.

## Planear y aplicar

```bash
make plan  ENV=dev PROJECT_ID=<proyecto>
make apply ENV=dev PROJECT_ID=<proyecto>   # pide confirmación
```

Un segundo `plan` justo después de aplicar debe dar "No changes". En un PR que cambie `terraform/**`, el workflow `plan.yml` muestra ese mismo plan en el job summary, como la SA `plan` (solo lectura).

El primer `apply` crea el servicio con una imagen de ejemplo (`image`). Después, Terraform **ignora** la imagen, `client` y `client_version`: la imagen la actualiza `gcloud run deploy`, y así un `plan` no la revierte al ejemplo.

## Montar un secreto (en dos pasos)

Cloud Run comprueba al desplegar que el secreto tiene al menos una versión y que la SA de runtime puede leerlo. Por eso el montaje va en dos `apply`:

1. En `terraform.tfvars`, define `secret_ids = ["mi-secreto"]` y aplica. Crea el secreto vacío y da `roles/secretmanager.secretAccessor` sobre ese secreto a la SA de runtime.
2. Carga el valor, sin pasarlo por el código ni por Terraform:
   ```bash
   printf '%s' "<valor>" | gcloud secrets versions add mi-secreto --project <proyecto> --data-file=-
   ```
3. Agrega `secret_env = { MI_VARIABLE = "mi-secreto" }` y aplica de nuevo. El servicio recibe la variable con la versión `latest`.

El valor nunca llega al código, al plan ni al estado. Para quitar el secreto, borra esas líneas de `terraform.tfvars` y aplica.

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
- **La SA `apply` actúa como la SA de runtime** gracias al binding `serviceAccountUser` que crea el módulo para `deployers` (aquí, `<name_prefix>-apply@<proyecto>`). `name_prefix` debe coincidir con el de `bootstrap`.
- **Orden al quitar roles en `bootstrap`:** aplica primero `envs/dev` (crea el binding) y después `bootstrap`.
- **Para probar lo que puede hacer la SA `apply`**, define `GOOGLE_IMPERSONATE_SERVICE_ACCOUNT=<SA apply>` en tu shell: `make apply` lo pasa al contenedor. Requiere `roles/iam.serviceAccountTokenCreator` sobre esa SA; dalo solo mientras dure la prueba y documéntalo.

variable "project_id" {
  description = "ID del proyecto de GCP de este entorno. Lo pasa `make` con PROJECT_ID."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id debe tener entre 6 y 30 caracteres: minúsculas, números y guiones, empezando con una letra."
  }
}

variable "region" {
  description = "Región de GCP de los recursos. Es la misma del bucket de estado."
  type        = string
  default     = "us-central1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region debe tener el formato de una región de GCP, por ejemplo us-central1."
  }
}

variable "image" {
  description = "Imagen inicial del servicio de Cloud Run. Por defecto, la imagen pública de ejemplo de Google: el repositorio nace vacío y Cloud Run exige una imagen que exista."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "secret_ids" {
  description = "Ids de los secretos que se crean sin valor. Paso 1 del montaje: se aplican, se carga el valor con `gcloud secrets versions add` y solo entonces se montan con secret_env."
  type        = set(string)
  default     = []
}

variable "secret_env" {
  description = "Variables de entorno del servicio que se montan desde Secret Manager: nombre de la variable => id del secreto (debe estar en secret_ids y tener al menos una versión). Paso 2 del montaje."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for id in values(var.secret_env) : contains(var.secret_ids, id)])
    error_message = "Cada valor de secret_env debe ser un id que esté en secret_ids."
  }
}

variable "name_prefix" {
  description = "Prefijo de las service accounts de CI. Debe coincidir con el name_prefix de terraform/bootstrap."
  type        = string
  default     = "dockyard2sail"
}

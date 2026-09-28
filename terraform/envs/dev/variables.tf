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

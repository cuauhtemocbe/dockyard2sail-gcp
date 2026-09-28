variable "project_id" {
  description = "ID del proyecto de GCP donde se crea el repositorio."
  type        = string
}

variable "repository_id" {
  description = "Nombre del repositorio de Artifact Registry."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,62}[a-z0-9]$", var.repository_id))
    error_message = "repository_id debe tener entre 3 y 64 caracteres: minúsculas, números y guiones, empezando con una letra."
  }
}

variable "location" {
  description = "Región del repositorio. Usar la misma del servicio de Cloud Run evita cobros de transferencia."
  type        = string
}

variable "keep_count" {
  description = "Versiones más recientes que se conservan, con o sin tag. Es la política KEEP: gana sobre la de borrado si una versión cumple las dos."
  type        = number
  default     = 5

  validation {
    condition     = var.keep_count >= 1 && floor(var.keep_count) == var.keep_count
    error_message = "keep_count debe ser un entero mayor o igual a 1."
  }
}

variable "untagged_max_age_days" {
  description = "Días después de los cuales se borran las versiones sin tag que no estén entre las últimas keep_count."
  type        = number
  default     = 7

  validation {
    condition     = var.untagged_max_age_days >= 1 && floor(var.untagged_max_age_days) == var.untagged_max_age_days
    error_message = "untagged_max_age_days debe ser un entero mayor o igual a 1."
  }
}

variable "cleanup_policy_dry_run" {
  description = "Si es true, las políticas de limpieza solo registran lo que borrarían, sin borrar nada."
  type        = bool
  default     = false
}

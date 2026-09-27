variable "project_id" {
  description = "ID del proyecto de GCP donde se crea el bootstrap. Un proyecto por entorno."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id debe tener entre 6 y 30 caracteres: minúsculas, números y guiones, empezando con una letra."
  }
}

variable "region" {
  description = "Región de GCP para el bucket de estado y los recursos siguientes."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region debe tener el formato de una región de GCP, por ejemplo us-central1."
  }
}

variable "github_repository" {
  description = "Repositorio autorizado para usar las service accounts, en formato owner/repo."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "github_repository debe tener el formato owner/repo."
  }
}

variable "github_repository_id" {
  description = "ID numérico del repositorio de GitHub. Si se define, el provider de WIF también lo exige. Recomendado: el ID no cambia si el repositorio se borra y otra persona crea uno con el mismo nombre."
  type        = string
  default     = null

  validation {
    condition     = var.github_repository_id == null || can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id debe ser un número, por ejemplo 123456789."
  }
}

variable "state_version_retention_days" {
  description = "Días que el bucket conserva las versiones no vigentes del estado antes de borrarlas."
  type        = number
  default     = 90

  validation {
    condition     = var.state_version_retention_days >= 1 && floor(var.state_version_retention_days) == var.state_version_retention_days
    error_message = "state_version_retention_days debe ser un entero mayor o igual a 1."
  }
}

variable "name_prefix" {
  description = "Prefijo de los nombres de las service accounts y del pool de WIF."
  type        = string
  default     = "dockyard2sail"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,14}$", var.name_prefix))
    error_message = "name_prefix debe tener entre 3 y 15 caracteres: minúsculas, números y guiones, empezando con una letra."
  }
}

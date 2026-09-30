variable "project_id" {
  description = "ID del proyecto de GCP donde se crean los secretos."
  type        = string
}

variable "secret_ids" {
  description = "Ids de los secretos que se crean, sin valor. Los valores se cargan fuera de Terraform (por ejemplo con `gcloud secrets versions add`) para que no queden en el estado."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.secret_ids : can(regex("^[a-zA-Z][a-zA-Z0-9_-]{0,254}$", id))])
    error_message = "Cada id debe empezar con una letra y tener hasta 255 caracteres: letras, números, guiones y guiones bajos."
  }
}

variable "accessor_email" {
  description = "Correo de la SA que puede leer todos los secretos de este módulo (roles/secretmanager.secretAccessor sobre cada secreto, no sobre el proyecto)."
  type        = string
}

variable "project_id" {
  description = "ID del proyecto de GCP donde se crean la SA de runtime y el servicio."
  type        = string
}

variable "name" {
  description = "Nombre del servicio de Cloud Run (entre 4 y 22 caracteres). La SA de runtime se llama \"<name>-runtime\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}[a-z0-9]$", var.name))
    error_message = "name debe tener entre 4 y 22 caracteres: minúsculas, números y guiones, empezando con una letra. El límite deja espacio para el sufijo -runtime en el id de la SA (30 caracteres como máximo)."
  }
}

variable "region" {
  description = "Región de GCP del servicio."
  type        = string
}

variable "image" {
  description = "Imagen inicial del contenedor. El módulo ignora sus cambios posteriores: la imagen desplegada la actualiza `gcloud run deploy`, no Terraform."
  type        = string
}

variable "allow_unauthenticated" {
  description = "Si es true, el servicio acepta invocaciones sin credenciales (activa invoker_iam_disabled). Si es false, solo lo invocan las identidades con roles/run.invoker."
  type        = bool
  default     = false
}

variable "min_instances" {
  description = "Instancias mínimas siempre encendidas. 0 permite escalar a cero y no cuesta nada sin tráfico."
  type        = number
  default     = 0

  validation {
    condition     = var.min_instances >= 0 && floor(var.min_instances) == var.min_instances
    error_message = "min_instances debe ser un entero mayor o igual a 0."
  }
}

variable "max_instances" {
  description = "Máximo de instancias del servicio. Limita la escala (el cómputo en paralelo), no el gasto: no sustituye una alerta de presupuesto. null no lo fija y Cloud Run usa su valor por defecto (100 por revisión)."
  type        = number
  default     = null

  validation {
    condition     = var.max_instances == null || (try(var.max_instances >= 1, false) && try(floor(var.max_instances) == var.max_instances, false))
    error_message = "max_instances debe ser un entero mayor o igual a 1, o null para no limitar."
  }
}

variable "secret_env" {
  description = "Variables de entorno que se montan desde Secret Manager: nombre de la variable => id del secreto. Siempre usa la versión latest. Cloud Run comprueba al desplegar que el secreto tiene versiones y que la SA de runtime puede leerlo."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Si es true, Terraform no destruye el servicio. Un entorno de pruebas lo pone en false para poder destruirlo."
  type        = bool
  default     = true
}

variable "deployers" {
  description = "Correos de las service accounts que pueden actuar como la SA de runtime (roles/iam.serviceAccountUser sobre ella, no sobre el proyecto). Quien despliega o actualiza el servicio lo necesita; en este template, la SA `apply` de bootstrap."
  type        = set(string)
  default     = []
}

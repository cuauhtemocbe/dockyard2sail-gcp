terraform {
  required_version = "~> 1.16"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.4"
    }
  }

  # El bucket no se escribe aquí para que el archivo no lleve el ID de un proyecto concreto:
  # `make plan` y `make apply` lo pasan con -backend-config="bucket=<PROJECT_ID>-tfstate".
  backend "gcs" {
    prefix = "envs/dev"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  # Con credenciales de usuario (ADC), las llamadas necesitan un proyecto al que cobrarse.
  user_project_override = true
  billing_project       = var.project_id
}

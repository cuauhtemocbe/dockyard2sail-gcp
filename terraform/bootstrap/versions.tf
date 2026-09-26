terraform {
  required_version = "~> 1.16"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.4"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  # Con credenciales de usuario (ADC), la habilitación de APIs falla con
  # "requires a quota project" si las llamadas no se cobran a un proyecto.
  user_project_override = true
  billing_project       = var.project_id
}

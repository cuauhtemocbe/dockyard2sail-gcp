output "state_bucket_name" {
  description = "Nombre del bucket donde los entornos guardan su estado de Terraform."
  value       = google_storage_bucket.state.name
}

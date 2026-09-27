output "state_bucket_name" {
  description = "Nombre del bucket donde los entornos guardan su estado de Terraform."
  value       = google_storage_bucket.state.name
}

output "workload_identity_provider" {
  description = "Nombre completo del provider de WIF, para el parámetro workload_identity_provider de google-github-actions/auth."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "secret_ids" {
  description = "Id de cada secreto creado, por id (para montarlos en un servicio)."
  value       = { for id, secret in google_secret_manager_secret.this : id => secret.secret_id }
}

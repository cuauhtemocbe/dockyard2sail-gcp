# Verifica el límite de var.name: "<name>-runtime" debe caber en los 30
# caracteres del id de una SA. Corre con `terraform test` (mock_provider, sin credenciales).

mock_provider "google" {}

variables {
  project_id = "test-project"
  region     = "us-central1"
  image      = "us-docker.pkg.dev/cloudrun/container/hello"
}

run "name_de_22_caracteres_es_valido" {
  command = plan

  variables {
    name = "abcdefghijklmnopqrstuv"
  }

  assert {
    condition     = length(google_service_account.runtime.account_id) == 30
    error_message = "Un name de 22 caracteres debe dar un account_id de 30."
  }
}

run "name_de_23_caracteres_falla" {
  command = plan

  variables {
    name = "abcdefghijklmnopqrstuvw"
  }

  expect_failures = [var.name]
}

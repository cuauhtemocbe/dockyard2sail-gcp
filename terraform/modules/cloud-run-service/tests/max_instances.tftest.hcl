# Verifica la validación de var.max_instances y el bloque scaling.
# Corre con `terraform test` (mock_provider, sin credenciales).

mock_provider "google" {}

variables {
  project_id = "test-project"
  name       = "test-service"
  region     = "us-central1"
  image      = "us-docker.pkg.dev/cloudrun/container/hello"
}

run "max_instances_3_se_escribe_y_min_queda_null" {
  command = plan

  variables {
    max_instances = 3
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].scaling[0].max_instance_count == 3
    error_message = "max_instance_count debe ser 3."
  }

  assert {
    condition     = google_cloud_run_v2_service.this.template[0].scaling[0].min_instance_count == null
    error_message = "min_instance_count debe ser null cuando min_instances = 0."
  }
}

run "sin_max_instances_no_hay_bloque_scaling" {
  command = plan

  assert {
    condition     = length(google_cloud_run_v2_service.this.template[0].scaling) == 0
    error_message = "Sin min ni max no debe escribirse el bloque scaling."
  }
}

run "max_instances_0_falla" {
  command = plan

  variables {
    max_instances = 0
  }

  expect_failures = [var.max_instances]
}

run "max_instances_fraccion_falla" {
  command = plan

  variables {
    max_instances = 2.5
  }

  expect_failures = [var.max_instances]
}

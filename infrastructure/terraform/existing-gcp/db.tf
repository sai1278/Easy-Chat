resource "google_sql_database_instance" "postgres" {
  name             = "${var.environment}-alloydb-postgres"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier = "db-custom-4-16384"
    availability_type = "REGIONAL" // High Availability (HA)

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc_network.id
    }

    backup_configuration {
      enabled    = true
      start_time = "02:00"
    }
  }
}

resource "google_sql_database" "platform_db" {
  name     = "platform_db"
  instance = google_sql_database_instance.postgres.name
}

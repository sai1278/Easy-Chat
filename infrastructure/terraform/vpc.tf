resource "google_compute_network" "vpc_network" {
  name                    = "${var.environment}-platform-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.environment}-platform-subnet"
  ip_cidr_range = "10.100.0.0/20"
  region        = var.region
  network       = google_compute_network.vpc_network.id

  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "10.101.0.0/16"
  }

  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = "10.102.0.0/20"
  }
}

resource "google_compute_global_address" "ingress_ip" {
  name        = "${var.environment}-easychat-ingress-ip"
  description = "Reserved External Static IP address for api.easychat.com production ingress"
}

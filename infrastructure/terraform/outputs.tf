output "gke_cluster_name" {
  description = "The name of the GKE production cluster"
  value       = google_container_cluster.primary.name
}

output "gke_cluster_endpoint" {
  description = "The IP address of the GKE cluster master"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "ingress_static_ip" {
  description = "Reserved External Static IP address for api.easychat.com"
  value       = google_compute_global_address.ingress_ip.address
}

output "vm_name" {
  description = "Name of the VM instance"
  value       = google_compute_instance.vm.name
}

output "vm_zone" {
  description = "Zone of the VM instance"
  value       = google_compute_instance.vm.zone
}

output "external_ip" {
  description = "Static external IP address"
  value       = google_compute_address.static_ip.address
}

output "ssh_command" {
  description = "SSH command via IAP tunnel"
  value       = "gcloud compute ssh ${google_compute_instance.vm.name} --zone=${google_compute_instance.vm.zone} --tunnel-through-iap"
}

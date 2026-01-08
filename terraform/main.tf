terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Static external IP address
resource "google_compute_address" "static_ip" {
  name         = "${var.vm_name}-ip"
  address_type = "EXTERNAL"
  region       = var.region
}

# Persistent disk for data (SQLite, uploads, etc.)
resource "google_compute_disk" "data_disk" {
  name = "${var.vm_name}-data"
  type = "pd-standard"
  size = var.disk_size_gb
  zone = var.zone
}

# VM instance
resource "google_compute_instance" "vm" {
  name         = var.vm_name
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
      size  = 30
      type  = "pd-standard"
    }
  }

  scheduling {
    preemptible                 = true
    automatic_restart           = false
    provisioning_model          = "SPOT"
    instance_termination_action = "STOP"
  }

  attached_disk {
    source      = google_compute_disk.data_disk.self_link
    device_name = "data-disk"
    mode        = "READ_WRITE"
  }

  network_interface {
    network = "default"
    access_config {
      nat_ip = google_compute_address.static_ip.address
    }
  }

  metadata = {
    startup-script = file("${path.module}/startup-script.sh")
  }

  tags = ["web-server", "ssh-server"]

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  service_account {
    scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
    ]
  }

  allow_stopping_for_update = true
}

# Firewall: Allow HTTP/HTTPS from anywhere
resource "google_compute_firewall" "allow_http_https" {
  name    = "${var.vm_name}-allow-http-https"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web-server"]
}

# Firewall: Allow SSH via IAP TCP tunneling only
resource "google_compute_firewall" "allow_ssh_iap" {
  name    = "${var.vm_name}-allow-ssh-iap"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP's IP range - only source allowed for SSH
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["ssh-server"]
}

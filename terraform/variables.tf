variable "admin_cidr" {
  description = "Public IPv4 address of the Ansible control node in /32 CIDR notation."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && endswith(var.admin_cidr, "/32")
    error_message = "admin_cidr must be one public host address in /32 CIDR notation."
  }
}

variable "ssh_public_key_path" {
  description = "Local filesystem path to the public SSH key registered with EC2."
  type        = string

  validation {
    condition     = endswith(var.ssh_public_key_path, ".pub")
    error_message = "ssh_public_key_path must end with .pub."
  }
}

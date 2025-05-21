variable "subscription_id" {
  description = "The subscription ID in which the resources will be created."
  sensitive   = true
}

variable "email" {
  description = "The email of the owner of this stack"
}

variable "base_name" {
  description = "The base name for the resources (will be used for prefix)."
}

variable "region" {
  description = "The region in which the resources will be created (example: swedencentral)."
  default     = "swedencentral"
}

variable "virtual_network_address_prefix" {
  description = "The address space that is used by the virtual network."
  default     = "10.0.0.0/16"
}

variable "aks_subnet_address_prefix" {
  type        = string
  description = "The address space that is used by the AKS subnet."
  default     = "10.0.0.0/18"
}

variable "app_gateway_subnet_address_prefix" {
  type        = string
  description = "The address space that is used by the Application Gateway subnet."
  default     = "10.0.64.0/24"
}

variable "aks_service_cidr" {
  type        = string
  description = "(Optional) The Network Range used by the Kubernetes service."
  default     = "192.168.0.0/20"
}

variable "aks_dns_service_ip" {
  type        = string
  description = "(Optional) IP address within the Kubernetes service address range that will be used by cluster service discovery (kube-dns)."
  default     = "192.168.0.10"
}

variable "adx_sku" {
  description = "Value of the sku for the Azure Data Explorer cluster."
  default     = "Standard_E2d_v4"
}
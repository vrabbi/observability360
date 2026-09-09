variable "subscription_id" {
  description = "The subscription ID in which the resources will be created."
  sensitive   = true
}

variable "base_name" {
  description = "The base name for the resources (will be used for prefix)."
}

variable "email" {
  description = "The email address of the user who will be the owner of the resources."
}

variable "region" {
  description = "The region in which the resources will be created (example: swedencentral)."
  default     = "swedencentral"
}

variable "data_location" {
  description = "The data location for the communication service."
  default     = "Europe"
}

variable "adx_sku" {
  description = "Value of the sku for the Azure Data Explorer cluster."
  default     = "Dev(No SLA)_Standard_D11_v2"
}

variable "github_token" {
  description = "Github PAT for ACR Build tasks to pull the source code of this repo"
}

variable "anomaly_subscriptions" {
  description = "Declared so the shared terraform.tfvars file is accepted. Used only by the infra stack to seed the AnomalySubscriptions ADX table."
  type = list(object({
    anomality   = string
    user        = string
    mail        = string
    threshold   = optional(number, 0.2)
    bin_size    = optional(string, "5m")
    time_window = optional(string, "3h")
  }))
  default = []
}

variable "github_repo_url" {
  default     = "https://github.com/vrabbi/observability360"
  description = "The repo with the source code of this project which is used by ACR to build our images"
}

variable "github_repo_branch" {
  default     = "main"
  description = "The branch of the github repo with the source code of this project which is used by ACR to build our images"
}

variable "obi_capture_request_headers" {
  type = list(string)
  default = [
    "x-tenant-id",
    "x-customer-id",
    "x-org-id",
  ]
  description = <<-EOT
    HTTP request header names (glob patterns allowed) that OBI captures and attaches to spans as
    http.request.header.<name>. They land in the TraceAttributes column of the OTELTraces table in
    ADX and drive the "Unit Economics" dashboard. Every other header, and every request and
    response body, is excluded. Set to [] to disable header capture entirely.
  EOT
}

variable "obi_http_capture_bytes" {
  type        = number
  default     = 8192
  description = <<-EOT
    Bytes of each HTTP request OBI copies out of the kernel (ebpf.buffer_sizes.http). The default
    capture window only covers the request line, so it has to be raised for header capture to see
    the header block. Headers that fall outside this window are not captured. Maximum is 262144.
  EOT
}

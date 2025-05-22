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

variable "pixie_deployment_key" {
  description = "Pixie Deployment Key. can be generated based on the docs here: https://docs.px.dev/reference/admin/deploy-keys/#create-a-deploy-key"
}
variable "github_repo_url" {
  default = "https://github.com/vrabbi/observability360"
  description = "The repo with the source code of this project which is used by ACR to build our images"
}

variable "github_repo_branch" {
  default = "main"
  description = "The branch of the github repo with the source code of this project which is used by ACR to build our images"
}
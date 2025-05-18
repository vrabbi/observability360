resource "azurerm_cognitive_account" "demo" {
  name                = "${var.base_name}-openai"
  location            = azurerm_resource_group.demo.location
  resource_group_name = azurerm_resource_group.demo.name
  kind                = "OpenAI"
  sku_name            = "S0"
}

resource "azurerm_cognitive_deployment" "demo" {
  name                 = "${var.base_name}-gpt-4o"
  cognitive_account_id = azurerm_cognitive_account.demo.id

  model {
    format  = "OpenAI"
    name    = var.openai_model
    version = var.openai_model_version
  }

  sku {
    name     = "GlobalStandard"
    capacity = 450
  }
}
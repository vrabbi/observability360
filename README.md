# OpenTelemetry Demo

This repository contains a demo for deploying OpenTelemetry with Azure Data Explorer for observability. The demo includes setting up infrastructure and application components using Terraform.

## Prerequisites

Before you begin, ensure you have the following installed:

- [Terraform](https://www.terraform.io/downloads.html)
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)

## Deployment Steps

### 1. Clone the Repository

```sh
git clone https://github.com/vladfeigin/observability360.git
cd observability360
```

### 2. Deploy the demo services

Switch directory to the IaC directory using: ``cd IaC``.

Create a file named ``terraform.tfvars`` with the following content:

```
subscription_id = "<your_subscription_id>"
base_name = "<base_name_prefix_for_the_created_resources>" 
email = "<your_email_address>"
```

for base_name use only alphanumeric letters, make sure its no longer than 12 characters.
run az login in order to authenticate and authorize to azure:

```
az login
```

#### 2.1 deploy the infrastructure resources

```sh
cd infra
terraform init
terraform apply -auto-approve -var-file="../terraform.tfvars"
```

wait for the process to finish, it might take a while.


#### 2.2. Deploy the application resources

```sh
cd ../app
terraform init
terraform apply -auto-approve -var-file="../terraform.tfvars"
```

At the end of the Terraform apply command you will receive the following outputs:

```
grafana_loadbalancer_ip = "<grafana_public_ip>"
jaeger_loadbalancer_ip = "<jaeger_public_ip>"
online_store_ui_loadbalancer_ip = "<online_store_ui_public_ip>"
```
### 3. Configure Pixie
Go to the pixie dashboard and configure the OTEL Plugin based on the docs [here](https://docs.px.dev/reference/plugins/plugin-system/#enabling-a-plugin)

the otel collector address is: `otel-collector.opentelemtry.svc.cluster.local:4317`
### 3. Validate functionallity

Navigate to the online store ui and start to play with the application, After that navigate to the grafana instance to see the telemetry visualization (it might take few minutes for the data to arrive).

### 4. Online Store

Online Store Application is a demo that simulates a complete online store. It functions as a target monitored application, providing essential services such as user management, product management, and order processing. This setup enables you to deploy and evaluate observability tools in a realistic environment.

## Online Store Services

The online store is composed of several services:
1. **User Service**  
    Manages online store user accounts.
    Located in the `online_store/user` directory.
2. **Product Service**  
    Located in the `online_store/product` directory.  
    Manages product information and catalog data, ensuring the seamless handling of your inventory details.  
3. **Cart Service**  
    Manages user shopping carts.
    Located in the `online_store/cart` directory.
4. **Order Service**  
    Order processing.
    Located in the `online_store/order` directory.
5. **Online Store UI**
    The online store UI.
    Located in the `online_store/ui` directory.

### 5. Cleaning Up

To destroy the infrastructure and application, run each time in each directory, first the app directory:

```sh
terraform destroy -auto-approve -var-file="../terraform.tfvars"
```

### 6. Contact

For any questions or feedback, please open an issue or contact the maintainers:

Vlad Feigin - vladfeigin@microsoft.com, Omer Feldman - omerfeldman@microsoft.com

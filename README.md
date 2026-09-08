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
### 3. eBPF instrumentation with OBI

Nothing to configure. [OpenTelemetry eBPF Instrumentation](https://opentelemetry.io/docs/zero-code/obi/)
(OBI, the upstream successor of Grafana Beyla) is deployed by Terraform as a DaemonSet in the `obi`
namespace and exports straight to `otel-collector.opentelemetry.svc.cluster.local:4317`, so its
telemetry lands in the same Azure Data Explorer tables as everything else. It provides:

- **Network flow metrics** (`obi.network.flow.bytes`, `obi.network.flow.packets`) for the whole
  cluster, visualized by the *Network Monitoring - OBI* dashboard. A flow between two nodes is
  observed by the OBI agent at each end, so cross node traffic is reported once per observing node.
- **Pod network errors**, kept from the kubelet metrics the collector already scrapes
  (`k8s.pod.network.errors`); OBI has no NIC level error or drop counters.
- **Zero-code application metrics and traces** (HTTP, gRPC, SQL, Redis, Kafka, ...) for the
  `online-store` and `otel-demo` namespaces. OBI detects processes that already export OTLP
  themselves and stays out of their way, so the SDK instrumented services are not double counted.

The instrumented namespaces, the exported metric groups and the network attribute set are all
configured in `IaC/app/obi.tf`.

### 4. Validate functionallity

Navigate to the online store ui and start to play with the application, After that navigate to the grafana instance to see the telemetry visualization (it might take few minutes for the data to arrive).

### 5. Online Store

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

### 6. Cleaning Up

To destroy the infrastructure and application, run each time in each directory, first the app directory:

```sh
terraform destroy -auto-approve -var-file="../terraform.tfvars"
```

### 7. Contact

For any questions or feedback, please open an issue or contact the maintainers:

Vlad Feigin - vladfeigin@microsoft.com, Omer Feldman - omerfeldman@microsoft.com

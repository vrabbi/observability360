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

anomaly_subscriptions = [
  {
    anomality = "accounting"
    user      = "Haggai"
    mail      = "haggaiz@terasky.com"
    # threshold, bin_size, and time_window default to 0.2 / 5m / 3h
  },
]
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
  cluster. A flow between two nodes is observed by the OBI agent at each end, so cross node
  traffic is reported once per observing node.
- **TCP health statistics** (`obi.stat.tcp.rtt`, `obi.stat.tcp.retransmits`,
  `obi.stat.tcp.failed.connections`) for the whole cluster. `stats_tcp_io` is deliberately left
  off: it fires on every send and receive, unlike the others which fire on close, failure or
  retransmit. Pod network *errors* come from the kubelet metrics the collector already scrapes
  (`k8s.pod.network.errors`); OBI has no NIC level error or drop counters.
- **Service graph metrics** (`traces_service_graph_request_*`), a call graph derived from the
  traffic on the wire. OBI counts an edge at the server end, or at the client end when the server
  itself is not instrumented.
- **Zero-code application metrics and traces** (HTTP, gRPC, SQL, Redis, Kafka, ...) for the
  `online-store` and `otel-demo` namespaces. OBI detects processes that already export OTLP
  themselves and stays out of their way, so the SDK instrumented services are not double counted.
- **HTTP request headers on server spans**, for services OBI instruments. See
  [Unit economics](#unit-economics) below.

Dashboards: *Network Monitoring - OBI* and *Service Map - OBI* in the `kubernetes_service` folder.
The instrumented namespaces, the exported metric groups and the attribute sets are all configured
in `IaC/app/obi.tf`.

#### Unit economics

Every request the online store serves is attributed to a tenant, so infrastructure cost can be
split across tenants, customers or product areas. The *Unit Economics - request attribution*
dashboard groups requests, service seconds and payload bytes by that tenant.

Pick a tenant in the online store UI sidebar ("Acting as tenant"), click around, and the split
moves. The tenant travels in an HTTP header (`x-tenant-id` by default) that the UI attaches to
every call; each service reads it off the incoming request and puts it back on every request it
makes onwards, so a whole call chain is attributed to the tenant that started it. The demo tenants
are set by the `DEMO_TENANTS` environment variable and the header name by `TENANT_HEADER`, both in
`online_store/otel/tenant.py`.

**Two paths produce the attribution, and the dashboard reads either one.**

1. **Services you instrument** set the tenant themselves, as the `tenant.id` span attribute. In this
   repository that is done centrally in `online_store/otel/tenant.py`, wired into every service by
   `configure_telemetry`, so no individual service or call site had to change.
2. **Services nobody instrumented** are covered by OBI, which copies chosen request headers onto the
   spans it generates, as `http.request.header.<name>`.

The second path exists because OBI is the only option when you cannot change the code. It is *not*
what fires for the online store: OBI deliberately skips processes it detects are already exporting
OTLP, so that it never emits a second copy of their telemetry, and every service here exports OTLP.
Header capture is configured and ready for workloads that are not instrumented; to see it drive the
online store instead, set `discovery.exclude_otel_instrumented_services: false` in `IaC/app/obi.tf`
and accept the duplicate spans that follow.

Which headers OBI captures is set by the `obi_capture_request_headers` Terraform variable (default
`x-tenant-id`, `x-customer-id`, `x-org-id`). Its capture policy excludes everything by default, so
no other header and no request or response body is ever read. Set the variable to `[]` to turn the
feature off.

Caveats worth knowing before relying on this:

- **Traces only.** The tenant lands on spans, not on metrics, so attribution costs one ADX row per
  request. Budget for that, or sample.
- **Service seconds, not currency.** The dashboard's allocation key is summed span duration. Turning
  that into money still needs a rate per service-second that you supply.
- **Coverage.** Anything reaching a service without a tenant shows up as `(unattributed)`; the
  *Attribution coverage* stat shows what fraction of load actually carries one.
- **OBI capture window.** For path 2, OBI only sees the first `obi_http_capture_bytes` (default
  8 KiB) of each request, so a header pushed past that point by large cookies is missed.
- **OBI and TLS.** For path 2, OBI reads plaintext plus TLS for Go and OpenSSL based processes.
  Traffic encrypted by another library is only visible at the network level.

### 4. Cleaning Up

To destroy the infrastructure and application, run each time in each directory, first the app directory:

```sh
terraform destroy -auto-approve -var-file="../terraform.tfvars"
```

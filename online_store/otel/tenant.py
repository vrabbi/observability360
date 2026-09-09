"""Request attribution for the online store demo.

Every served request is tagged with an org, a tenant and a customer so the
"Unit Economics" Grafana dashboard can split load and cost on any of those
dimensions. Two independent paths produce the same attribution and the dashboard
reads either one:

1. Services instrumented with the OpenTelemetry SDK (every online store service)
   set the attributes themselves: ``org.id``, ``tenant.id``, ``customer.id``.
2. Services nobody instrumented are covered by OpenTelemetry eBPF
   Instrumentation, which copies the request headers onto the spans it generates
   as ``http.request.header.<name>``.

Both paths are needed because OBI deliberately skips processes that already
export OTLP, to avoid emitting a second copy of their telemetry. That makes path
1 the one that actually fires for the services in this repository.

The values travel between services in HTTP headers. The UI picks the org and
tenant and the acting user (customer), and each service reads them off the
incoming request and puts them back on every request it makes onwards, so a
whole call chain stays attributed to the same org / tenant / customer.
"""
from __future__ import annotations

import os
from contextvars import ContextVar

import requests
from opentelemetry import trace

# Header names have to match the entries in the obi_capture_request_headers
# Terraform variable for the OBI path to see them.
ORG_HEADER = os.environ.get("ORG_HEADER", "x-org-id").lower()
TENANT_HEADER = os.environ.get("TENANT_HEADER", "x-tenant-id").lower()
CUSTOMER_HEADER = os.environ.get("CUSTOMER_HEADER", "x-customer-id").lower()

ORG_ATTRIBUTE = "org.id"
TENANT_ATTRIBUTE = "tenant.id"
CUSTOMER_ATTRIBUTE = "customer.id"

_DEFAULT_ORGS = {
    "northwind": ["acme-corp", "globex"],
    "contoso": ["initech", "umbrella"],
}


def _parse_demo_orgs(raw: str) -> dict[str, list[str]]:
    """Parse ``org:tenant|tenant,org:tenant`` into an org → tenants map."""
    orgs: dict[str, list[str]] = {}
    for part in raw.split(","):
        part = part.strip()
        if not part or ":" not in part:
            continue
        org, tenants = part.split(":", 1)
        org = org.strip()
        tenant_list = [t.strip() for t in tenants.split("|") if t.strip()]
        if org and tenant_list:
            orgs[org] = tenant_list
    return orgs


def _load_demo_orgs() -> dict[str, list[str]]:
    raw_orgs = os.environ.get("DEMO_ORGS", "").strip()
    if raw_orgs:
        parsed = _parse_demo_orgs(raw_orgs)
        if parsed:
            return parsed
    raw_tenants = os.environ.get("DEMO_TENANTS", "").strip()
    if raw_tenants:
        tenants = [t.strip() for t in raw_tenants.split(",") if t.strip()]
        if tenants:
            return {"default": tenants}
    return {org: list(tenants) for org, tenants in _DEFAULT_ORGS.items()}


DEMO_ORGS = _load_demo_orgs()
DEMO_TENANTS = [tenant for tenants in DEMO_ORGS.values() for tenant in tenants]

_current_org: ContextVar[str] = ContextVar("current_org", default="")
_current_tenant: ContextVar[str] = ContextVar("current_tenant", default="")
_current_customer: ContextVar[str] = ContextVar("current_customer", default="")
_requests_patched = False


def current_org() -> str:
    return _current_org.get()


def current_tenant() -> str:
    """The tenant the request being handled belongs to, or an empty string."""
    return _current_tenant.get()


def current_customer() -> str:
    """The acting user id (customer), or an empty string."""
    return _current_customer.get()


def set_current_org(org: str) -> None:
    _current_org.set(org or "")


def set_current_tenant(tenant: str) -> None:
    _current_tenant.set(tenant or "")


def set_current_customer(customer: str) -> None:
    _current_customer.set("" if customer is None else str(customer))


def tenants_for_org(org: str) -> list[str]:
    return list(DEMO_ORGS.get(org) or [])


def _set_header(headers: dict, name: str, value: str) -> None:
    if value and not any(k.lower() == name for k in headers):
        headers[name] = value


def attribution_headers(headers: dict | None = None) -> dict:
    """Adds org / tenant / customer headers, leaving any existing values alone."""
    headers = dict(headers or {})
    _set_header(headers, ORG_HEADER, current_org())
    _set_header(headers, TENANT_HEADER, current_tenant())
    _set_header(headers, CUSTOMER_HEADER, current_customer())
    return headers


def tenant_headers(headers: dict | None = None) -> dict:
    """Back-compat alias for :func:`attribution_headers`."""
    return attribution_headers(headers)


def install_requests_propagation() -> None:
    """Makes every outgoing `requests` call carry the current attribution headers.

    Patching the session is what keeps this demo honest: the headers reach the
    next service whether or not the call site remembered to pass them, the same
    way a service mesh or an HTTP client wrapper would do it in a real deployment.
    """
    global _requests_patched
    if _requests_patched:
        return

    original_request = requests.Session.request

    def request_with_attribution(self, method, url, **kwargs):
        kwargs["headers"] = attribution_headers(kwargs.get("headers"))
        return original_request(self, method, url, **kwargs)

    requests.Session.request = request_with_attribution
    _requests_patched = True


def _header_from_scope(scope, header_name: str) -> str:
    for name, value in scope.get("headers") or []:
        if name.decode("latin-1").lower() == header_name:
            return value.decode("latin-1")
    return ""


def _apply_to_span(span, org: str, tenant: str, customer: str) -> None:
    if span is None or not span.is_recording():
        return
    if org:
        span.set_attribute(ORG_ATTRIBUTE, org)
    if tenant:
        span.set_attribute(TENANT_ATTRIBUTE, tenant)
    if customer:
        span.set_attribute(CUSTOMER_ATTRIBUTE, customer)


def server_request_hook(span, scope, *_ignored) -> None:
    """Called by the FastAPI instrumentation once the server span exists.

    Using the hook rather than our own middleware keeps this independent of
    middleware ordering, and it runs in the request's own context, so the
    ContextVars are visible both to the endpoint and to any call it makes onwards.
    """
    if not isinstance(scope, dict) or scope.get("type") != "http":
        return
    org = _header_from_scope(scope, ORG_HEADER)
    tenant = _header_from_scope(scope, TENANT_HEADER)
    customer = _header_from_scope(scope, CUSTOMER_HEADER)
    set_current_org(org)
    set_current_tenant(tenant)
    set_current_customer(customer)
    _apply_to_span(span, org, tenant, customer)


def annotate_current_span(
    tenant: str | None = None,
    org: str | None = None,
    customer: str | None = None,
) -> None:
    """Tags the active span with the current attribution, for code outside FastAPI."""
    org = current_org() if org is None else org
    tenant = current_tenant() if tenant is None else tenant
    customer = current_customer() if customer is None else customer
    _apply_to_span(trace.get_current_span(), org, tenant, customer)

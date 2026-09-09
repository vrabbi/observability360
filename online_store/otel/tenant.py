"""Tenant attribution for the online store demo.

Every served request is attributed to a tenant so the "Unit Economics" Grafana
dashboard can split load and cost across them. Two independent paths produce the
same attribution and the dashboard reads either one:

1. Services instrumented with the OpenTelemetry SDK (every online store service)
   set the tenant themselves, as the ``tenant.id`` span attribute.
2. Services nobody instrumented are covered by OpenTelemetry eBPF
   Instrumentation, which copies the request header onto the spans it generates
   as ``http.request.header.<name>``.

Both paths are needed because OBI deliberately skips processes that already
export OTLP, to avoid emitting a second copy of their telemetry. That makes path
1 the one that actually fires for the services in this repository.

The tenant travels between services in an HTTP header. The UI picks it, and each
service reads it off the incoming request and puts it back on every request it
makes onwards, so a whole call chain is attributed to the tenant that started it.
"""
from __future__ import annotations

import os
from contextvars import ContextVar

import requests
from opentelemetry import trace

# Name of the header carrying the tenant. It has to match one of the entries in
# the obi_capture_request_headers Terraform variable for the OBI path to see it.
TENANT_HEADER = os.environ.get("TENANT_HEADER", "x-tenant-id").lower()

# Span attribute the SDK instrumented services set. There is no OpenTelemetry
# semantic convention for a tenant, so this is a local name.
TENANT_ATTRIBUTE = "tenant.id"

DEMO_TENANTS = [
    t.strip() for t in os.environ.get(
        "DEMO_TENANTS", "acme-corp,globex,initech,umbrella").split(",") if t.strip()
]

_current_tenant: ContextVar[str] = ContextVar("current_tenant", default="")
_requests_patched = False


def current_tenant() -> str:
    """The tenant the request being handled belongs to, or an empty string."""
    return _current_tenant.get()


def set_current_tenant(tenant: str) -> None:
    _current_tenant.set(tenant or "")


def tenant_headers(headers: dict | None = None) -> dict:
    """Adds the tenant header to a header dict, leaving an existing value alone."""
    headers = dict(headers or {})
    tenant = current_tenant()
    if tenant and not any(k.lower() == TENANT_HEADER for k in headers):
        headers[TENANT_HEADER] = tenant
    return headers


def install_requests_propagation() -> None:
    """Makes every outgoing `requests` call carry the current tenant header.

    Patching the session is what keeps this demo honest: the header reaches the
    next service whether or not the call site remembered to pass it, the same way
    a service mesh or an HTTP client wrapper would do it in a real deployment.
    """
    global _requests_patched
    if _requests_patched:
        return

    original_request = requests.Session.request

    def request_with_tenant(self, method, url, **kwargs):
        kwargs["headers"] = tenant_headers(kwargs.get("headers"))
        return original_request(self, method, url, **kwargs)

    requests.Session.request = request_with_tenant
    _requests_patched = True


def _tenant_from_scope(scope) -> str:
    for name, value in scope.get("headers") or []:
        if name.decode("latin-1").lower() == TENANT_HEADER:
            return value.decode("latin-1")
    return ""


def server_request_hook(span, scope, *_ignored) -> None:
    """Called by the FastAPI instrumentation once the server span exists.

    Using the hook rather than our own middleware keeps this independent of
    middleware ordering, and it runs in the request's own context, so the
    ContextVar is visible both to the endpoint and to any call it makes onwards.
    """
    if not isinstance(scope, dict) or scope.get("type") != "http":
        return
    tenant = _tenant_from_scope(scope)
    set_current_tenant(tenant)
    if tenant and span is not None and span.is_recording():
        span.set_attribute(TENANT_ATTRIBUTE, tenant)


def annotate_current_span(tenant: str | None = None) -> None:
    """Tags the active span with the tenant, for code outside a FastAPI request."""
    tenant = tenant if tenant is not None else current_tenant()
    if not tenant:
        return
    span = trace.get_current_span()
    if span is not None and span.is_recording():
        span.set_attribute(TENANT_ATTRIBUTE, tenant)

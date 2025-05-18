FROM python:3.13-slim-bookworm

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app

COPY pyproject.toml uv.lock ./

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project

COPY black/black_agent.py ./black_agent.py
COPY otel otel

EXPOSE 8000

CMD ["uv", "run", "black_agent.py", "--host", "0.0.0.0", "--port", "8000"]

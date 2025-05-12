# mcp_sse/black/Dockerfile
FROM python:3.13-slim-bookworm

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app

COPY pyproject.toml uv.lock ./

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project

COPY white/white_agent.py ./white_agent.py

EXPOSE 8000

CMD ["uv", "run", "white_agent.py", "--host", "0.0.0.0", "--port", "8000"]
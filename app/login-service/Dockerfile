# syntax=docker/dockerfile:1
# Pin by tag here; the CI/hardening phase re-pins to an immutable image DIGEST.
FROM python:3.12-slim

# Security default: run as a non-root user everywhere (matches the Pod Security
# "restricted" profile the charts enforce later).
RUN useradd --create-home --uid 10001 appuser
WORKDIR /app
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
USER appuser
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]

FROM python:3.13-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY runtime_adapter.py .

# Local data directory for file storage when S3 is not configured
RUN mkdir -p /app/data
VOLUME ["/app/data"]

EXPOSE 5001

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5001/api/health')" || exit 1

CMD ["uvicorn", "runtime_adapter:app", "--host", "0.0.0.0", "--port", "5001"]
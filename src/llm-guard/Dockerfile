FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TRANSFORMERS_CACHE=/root/.cache/huggingface \
    HF_HOME=/root/.cache/huggingface

# System deps (optional but useful)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates && rm -rf /var/lib/apt/lists/*

# Install llm-guard + runtime deps (CPU ONNX)
# llm-guard officially supports Python >=3.10,<3.13 on PyPI
# (We stick to 3.11 here for compatibility)
RUN pip install --no-cache-dir \
    "fastapi>=0.110.0" "uvicorn[standard]>=0.27.0" \
    "llm-guard>=0.3.0" "optimum[onnxruntime]" \
    "transformers>=4.40.0" "accelerate>=0.29.0" "huggingface-hub>=0.23.0" \
    "spacy-pkuseg" "onnxruntime"

RUN python -m spacy download en_core_web_sm


WORKDIR /app
COPY app.py /app/app.py

EXPOSE 4321
# Single worker to keep in-memory Vault mapping consistent for demo
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "4321", "--workers", "1"]
# ==============================================================================
# 对料 (Duiliao) - All-in-One Multi-Stage Production Dockerfile
# Stage 1: Build React 19 Frontend (Vite + TailwindCSS)
# Stage 2: Python 3.12 FastAPI Runtime (Serving API + Frontend SPA)
# ==============================================================================

# ------------------------------------------------------------------------------
# Stage 1: Frontend Builder
# ------------------------------------------------------------------------------
FROM node:22-alpine AS frontend-builder

WORKDIR /app/frontend

# Layer caching for npm dependencies
COPY frontend/package.json frontend/package-lock.json* ./
RUN npm install

# Build arguments for frontend configuration
ARG VITE_API_BASE_URL="/api/v1"
ARG VITE_APP_SIGNING_SECRET=""
ARG VITE_APP_ID="web"

ENV VITE_API_BASE_URL=${VITE_API_BASE_URL} \
    VITE_APP_SIGNING_SECRET=${VITE_APP_SIGNING_SECRET} \
    VITE_APP_ID=${VITE_APP_ID}

# Copy frontend source code and compile SPA bundle
COPY frontend/ ./
RUN npm run build


# ------------------------------------------------------------------------------
# Stage 2: Backend & SPA Combined Runtime
# ------------------------------------------------------------------------------
FROM python:3.12-slim AS runtime

WORKDIR /app

# Install minimal system dependencies & configure Asia/Shanghai timezone
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

ENV TZ=Asia/Shanghai \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    APP_ENV=production \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install Python backend dependencies
COPY backend/requirements.txt ./backend/requirements.txt
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r ./backend/requirements.txt && \
    playwright install --with-deps chromium && \
    rm -rf /var/lib/apt/lists/*

# Copy backend source code
COPY backend/ ./backend/

# Copy compiled frontend assets from Stage 1 into /app/frontend/dist
COPY --from=frontend-builder /app/frontend/dist ./frontend/dist

# Switch to backend directory so `app.main:app` module imports cleanly
WORKDIR /app/backend

# Create runtime directories for collector sources and output data
RUN mkdir -p /app/backend/collector/sources /app/backend/collector/data

EXPOSE 8000

# Container healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Start Uvicorn ASGI server
# Note: Single worker ensures AES-GCM session store consistency in memory
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]

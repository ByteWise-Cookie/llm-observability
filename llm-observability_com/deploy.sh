#!/bin/bash
# deploy.sh - Build and deploy to Google Cloud Run
# Loads configuration from .env.local (NOT committed)

set -Eeuo pipefail

echo "================================================"
echo "LLM Observability System - Cloud Run Deployment"
echo "================================================"
echo ""

# ---------- Pre-flight checks ----------

command -v gcloud >/dev/null 2>&1 || {
  echo "❌ ERROR: gcloud CLI not found. Install Google Cloud SDK first."
  exit 1
}

if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
  echo "❌ ERROR: gcloud is not authenticated"
  echo "Run: gcloud auth login"
  exit 1
fi

# ---------- Environment file ----------

if [ ! -f .env.local ]; then
  echo "❌ ERROR: .env.local not found"
  echo ""
  echo "Create .env.local with:"
  echo "  GCP_PROJECT_ID=your-project-id"
  echo "  GCP_LOCATION=us-central1"
  echo "  MODEL_NAME=gemini-2.5-flash"
  echo "  DATADOG_API_KEY=your-api-key"
  echo "  DATADOG_APP_KEY=your-app-key"
  echo "  DATADOG_SITE=us5.datadoghq.com"
  echo "  ENVIRONMENT=production"
  echo "  SERVICE_NAME=llm-observability-service"
  echo ""
  exit 1
fi

echo "📋 Loading configuration from .env.local..."
set -a
source .env.local
set +a

# ---------- Validation ----------

REQUIRED_VARS=(
  "GCP_PROJECT_ID"
  "DATADOG_API_KEY"
  "DATADOG_APP_KEY"
)

MISSING=()
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var:-}" ]; then
    MISSING+=("$var")
  fi
done

if [ "${#MISSING[@]}" -ne 0 ]; then
  echo "❌ ERROR: Missing required variables:"
  printf '  - %s\n' "${MISSING[@]}"
  exit 1
fi

# ---------- Defaults ----------

GCP_LOCATION="${GCP_LOCATION:-us-central1}"
MODEL_NAME="${MODEL_NAME:-gemini-2.5-flash}"
DATADOG_SITE="${DATADOG_SITE:-us5.datadoghq.com}"
ENVIRONMENT="${ENVIRONMENT:-production}"
SERVICE_NAME="${SERVICE_NAME:-llm-observability-service}"
MEMORY="${MEMORY:-1Gi}"
CPU="${CPU:-1}"
TIMEOUT="${TIMEOUT:-300}"

echo "✓ Configuration loaded"
echo ""
echo "Deployment settings:"
echo "  Project ID : $GCP_PROJECT_ID"
echo "  Region    : $GCP_LOCATION"
echo "  Service   : $SERVICE_NAME"
echo "  Model     : $MODEL_NAME"
echo "  Datadog   : $DATADOG_SITE"
echo "  Env       : $ENVIRONMENT"
echo ""

# ---------- GCP setup ----------

echo "🔧 Setting gcloud project..."
gcloud config set project "$GCP_PROJECT_ID" >/dev/null
echo ""

IMAGE_URL="gcr.io/$GCP_PROJECT_ID/$SERVICE_NAME"

# ---------- Build ----------

echo "🏗️  Building container image..."
echo "  (This may take a few minutes)"
echo ""

gcloud builds submit \
  --tag "$IMAGE_URL" \
  --quiet

echo "✓ Image built: $IMAGE_URL"
echo ""

# ---------- Deploy ----------

echo "🚀 Deploying to Cloud Run..."
echo ""

gcloud run deploy "$SERVICE_NAME" \
  --image "$IMAGE_URL" \
  --platform managed \
  --region "$GCP_LOCATION" \
  --allow-unauthenticated \
  --memory "$MEMORY" \
  --cpu "$CPU" \
  --timeout "$TIMEOUT" \
  --set-env-vars "\
GCP_PROJECT_ID=$GCP_PROJECT_ID,\
GCP_LOCATION=$GCP_LOCATION,\
MODEL_NAME=$MODEL_NAME,\
DATADOG_API_KEY=$DATADOG_API_KEY,\
DATADOG_APP_KEY=$DATADOG_APP_KEY,\
DATADOG_SITE=$DATADOG_SITE,\
ENVIRONMENT=$ENVIRONMENT,\
SERVICE_NAME=$SERVICE_NAME" \
  --quiet

echo ""
echo "✓ Deployment complete"
echo ""

# ---------- Post-deploy ----------

SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
  --region "$GCP_LOCATION" \
  --format 'value(status.url)')

echo "================================================"
echo "✅ Deployment Successful"
echo "================================================"
echo ""
echo "Service URL: $SERVICE_URL"
echo ""

echo "🧪 Testing health endpoint..."
if curl -fsS "$SERVICE_URL/health" | grep -qi "healthy"; then
  echo "✓ Health check passed"
else
  echo "⚠️  Health check failed (service may still be starting)"
fi

echo ""
echo "Next steps:"
echo ""
echo "1) Test chat endpoint:"
echo "   curl -X POST $SERVICE_URL/chat \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"prompt\":\"What is 2+2?\"}'"
echo ""
echo "2) Check Datadog metrics (~90s delay):"
echo "   https://$DATADOG_SITE/metric/explorer"
echo "   Metric: llm.request.latency_ms"
echo ""
echo "3) View Cloud Run logs:"
echo "   gcloud run services logs read $SERVICE_NAME --region $GCP_LOCATION"
echo ""
echo "================================================"

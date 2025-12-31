#!/bin/bash
# setup.sh - Complete Google Cloud project setup for LLM Observability
# Run this ONCE before deploy.sh

set -Eeuo pipefail

echo "================================================"
echo "LLM Observability System - Initial Setup"
echo "================================================"
echo ""
echo "This script will:"
echo "  1. Create/configure Google Cloud project"
echo "  2. Enable required APIs"
echo "  3. Set up IAM permissions"
echo "  4. Create .env.local configuration file"
echo "  5. Verify Datadog connectivity"
echo ""
read -p "Press ENTER to continue or Ctrl+C to abort..."
echo ""

# ---------- Pre-flight checks ----------

command -v gcloud >/dev/null 2>&1 || {
  echo "❌ ERROR: gcloud CLI not found"
  echo ""
  echo "Install Google Cloud SDK:"
  echo "  macOS:   brew install --cask google-cloud-sdk"
  echo "  Linux:   curl https://sdk.cloud.google.com | bash"
  echo "  Windows: https://cloud.google.com/sdk/docs/install"
  echo ""
  exit 1
}

command -v python3 >/dev/null 2>&1 || {
  echo "❌ ERROR: python3 not found. Install Python 3.11+ first."
  exit 1
}

echo "✓ Prerequisites found"
echo ""

# ---------- Google Cloud authentication ----------

echo "🔐 Checking Google Cloud authentication..."

if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
  echo "❌ Not authenticated with gcloud"
  echo ""
  echo "Authenticating now..."
  gcloud auth login
  gcloud auth application-default login
fi

ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
echo "✓ Authenticated as: $ACTIVE_ACCOUNT"
echo ""

# ---------- Project selection ----------

echo "📋 Google Cloud Project Setup"
echo ""
echo "Options:"
echo "  1) Create a new project"
echo "  2) Use an existing project"
echo ""
read -p "Enter choice (1 or 2): " PROJECT_CHOICE

if [ "$PROJECT_CHOICE" = "1" ]; then
  # Create new project
  echo ""
  read -p "Enter project name (e.g., llm-observability): " PROJECT_NAME
  
  # Generate unique project ID
  TIMESTAMP=$(date +%s)
  PROJECT_ID="${PROJECT_NAME}-${TIMESTAMP}"
  
  echo ""
  echo "Creating project: $PROJECT_ID"
  
  gcloud projects create "$PROJECT_ID" --name="$PROJECT_NAME" || {
    echo "❌ Failed to create project"
    exit 1
  }
  
  echo "✓ Project created: $PROJECT_ID"
  
elif [ "$PROJECT_CHOICE" = "2" ]; then
  # Use existing project
  echo ""
  echo "Available projects:"
  gcloud projects list --format="table(projectId,name)"
  echo ""
  read -p "Enter project ID: " PROJECT_ID
  
  # Verify project exists
  if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
    echo "❌ Project not found: $PROJECT_ID"
    exit 1
  fi
  
  echo "✓ Using project: $PROJECT_ID"
  
else
  echo "❌ Invalid choice"
  exit 1
fi

echo ""
gcloud config set project "$PROJECT_ID"

# ---------- Billing check ----------

echo "💳 Checking billing status..."

BILLING_ENABLED=$(gcloud beta billing projects describe "$PROJECT_ID" --format="value(billingEnabled)" 2>/dev/null || echo "false")

if [ "$BILLING_ENABLED" = "false" ]; then
  echo "⚠️  Billing is NOT enabled for this project"
  echo ""
  echo "To enable billing:"
  echo "  1. Go to: https://console.cloud.google.com/billing/linkedaccount?project=$PROJECT_ID"
  echo "  2. Link a billing account"
  echo "  3. Re-run this script"
  echo ""
  read -p "Press ENTER to continue anyway (may fail later) or Ctrl+C to abort..."
else
  echo "✓ Billing enabled"
fi

echo ""

# ---------- Enable APIs ----------

echo "🔌 Enabling required APIs..."
echo "  (This takes 30-60 seconds)"
echo ""

REQUIRED_APIS=(
  "run.googleapis.com"
  "cloudbuild.googleapis.com"
  "aiplatform.googleapis.com"
  "artifactregistry.googleapis.com"
  "generativelanguage.googleapis.com"
)

for api in "${REQUIRED_APIS[@]}"; do
  echo "  Enabling $api..."
  gcloud services enable "$api" --quiet
done

echo ""
echo "✓ APIs enabled. Waiting 30s for propagation..."
sleep 30
echo ""

# ---------- Verify Vertex AI access ----------

echo "🧪 Testing Vertex AI access..."

cat > /tmp/test_vertex.py << 'EOF'
import sys
import os
try:
    import vertexai
    from vertexai.generative_models import GenerativeModel
    
    project_id = sys.argv[1]
    vertexai.init(project=project_id, location="us-central1")
    model = GenerativeModel("gemini-2.5-flash")
    
    response = model.generate_content("Say hello")
    print("✓ Vertex AI access confirmed")
    sys.exit(0)
except Exception as e:
    print(f"⚠️  Vertex AI test failed: {e}")
    print("   This may resolve after a few minutes")
    sys.exit(0)
EOF

python3 -c "import vertexai" 2>/dev/null || pip3 install --quiet google-cloud-aiplatform

python3 /tmp/test_vertex.py "$PROJECT_ID" || true
rm /tmp/test_vertex.py

echo ""

# ---------- Datadog setup ----------

echo "📊 Datadog Configuration"
echo ""
echo "You need:"
echo "  1. API Key (from Organization Settings → API Keys)"
echo "  2. Application Key (from Organization Settings → Application Keys)"
echo ""
echo "If you don't have a Datadog account:"
echo "  Sign up: https://www.datadoghq.com/free-trial/"
echo ""
read -p "Press ENTER when ready to continue..."
echo ""

read -p "Enter Datadog API Key: " DATADOG_API_KEY
read -p "Enter Datadog Application Key: " DATADOG_APP_KEY
echo ""

echo "Datadog region options:"
echo "  1) US1 (app.datadoghq.com)"
echo "  2) US3 (us3.datadoghq.com)"
echo "  3) US5 (us5.datadoghq.com)"
echo "  4) EU1 (datadoghq.eu)"
echo ""
read -p "Enter choice (1-4): " DD_REGION_CHOICE

case "$DD_REGION_CHOICE" in
  1) DATADOG_SITE="datadoghq.com" ;;
  2) DATADOG_SITE="us3.datadoghq.com" ;;
  3) DATADOG_SITE="us5.datadoghq.com" ;;
  4) DATADOG_SITE="datadoghq.eu" ;;
  *) 
    echo "❌ Invalid choice, defaulting to US5"
    DATADOG_SITE="us5.datadoghq.com"
    ;;
esac

echo "✓ Using Datadog site: $DATADOG_SITE"
echo ""

# ---------- Test Datadog connectivity ----------

echo "🧪 Testing Datadog API..."

cat > /tmp/test_dd.py << 'EOF'
import sys
try:
    from datadog_api_client import ApiClient, Configuration
    from datadog_api_client.v2.api.metrics_api import MetricsApi
    from datadog_api_client.v2.model.metric_payload import MetricPayload
    from datadog_api_client.v2.model.metric_series import MetricSeries
    from datadog_api_client.v2.model.metric_point import MetricPoint
    from datadog_api_client.v2.model.metric_intake_type import MetricIntakeType
    import time
    
    api_key = sys.argv[1]
    app_key = sys.argv[2]
    site = sys.argv[3]
    
    config = Configuration()
    config.api_key["apiKeyAuth"] = api_key
    config.api_key["appKeyAuth"] = app_key
    config.server_variables = {"site": site}
    
    with ApiClient(config) as api_client:
        api = MetricsApi(api_client)
        series = [MetricSeries(
            metric="llm.setup.test",
            type=MetricIntakeType.UNSPECIFIED,
            points=[MetricPoint(timestamp=int(time.time()), value=1.0)],
            tags=["source:setup_script"]
        )]
        api.submit_metrics(body=MetricPayload(series=series))
        print("✓ Datadog API connection successful")
        sys.exit(0)
except Exception as e:
    print(f"❌ Datadog test failed: {e}")
    print("   Check your API keys and try again")
    sys.exit(1)
EOF

python3 -c "from datadog_api_client import ApiClient" 2>/dev/null || pip3 install --quiet datadog-api-client

if python3 /tmp/test_dd.py "$DATADOG_API_KEY" "$DATADOG_APP_KEY" "$DATADOG_SITE"; then
  echo ""
else
  echo ""
  echo "⚠️  Datadog connection failed. Double-check your keys."
  echo ""
  read -p "Continue anyway? (y/n): " CONTINUE
  if [ "$CONTINUE" != "y" ]; then
    exit 1
  fi
fi

rm /tmp/test_dd.py

# ---------- Additional configuration ----------

echo "⚙️  Additional Settings"
echo ""

read -p "GCP region [us-central1]: " GCP_LOCATION
GCP_LOCATION="${GCP_LOCATION:-us-central1}"

read -p "Model name [gemini-2.5-flash]: " MODEL_NAME
MODEL_NAME="${MODEL_NAME:-gemini-2.5-flash}"

read -p "Service name [llm-observability-service]: " SERVICE_NAME
SERVICE_NAME="${SERVICE_NAME:-llm-observability-service}"

read -p "Environment [production]: " ENVIRONMENT
ENVIRONMENT="${ENVIRONMENT:-production}"

echo ""

# ---------- Create .env.local ----------

echo "📝 Creating .env.local configuration file..."

cat > .env.local << EOF
# LLM Observability System - Configuration
# Generated by setup.sh on $(date)
# DO NOT COMMIT THIS FILE

# Google Cloud
GCP_PROJECT_ID=$PROJECT_ID
GCP_LOCATION=$GCP_LOCATION
MODEL_NAME=$MODEL_NAME

# Datadog
DATADOG_API_KEY=$DATADOG_API_KEY
DATADOG_APP_KEY=$DATADOG_APP_KEY
DATADOG_SITE=$DATADOG_SITE

# Service
ENVIRONMENT=$ENVIRONMENT
SERVICE_NAME=$SERVICE_NAME

# Optional (uncomment to override defaults)
# MEMORY=1Gi
# CPU=1
# TIMEOUT=300
EOF

chmod 600 .env.local

echo "✓ Configuration saved to .env.local"
echo ""

# ---------- Add to .gitignore ----------

if [ -f .gitignore ]; then
  if ! grep -q ".env.local" .gitignore; then
    echo ".env.local" >> .gitignore
    echo "✓ Added .env.local to .gitignore"
  fi
else
  echo ".env.local" > .gitignore
  echo "✓ Created .gitignore with .env.local"
fi

echo ""

# ---------- Summary ----------

echo "================================================"
echo "✅ Setup Complete"
echo "================================================"
echo ""
echo "Configuration Summary:"
echo "  Project ID    : $PROJECT_ID"
echo "  Region        : $GCP_LOCATION"
echo "  Model         : $MODEL_NAME"
echo "  Service       : $SERVICE_NAME"
echo "  Datadog Site  : $DATADOG_SITE"
echo "  Environment   : $ENVIRONMENT"
echo ""
echo "Next Steps:"
echo ""
echo "1) Install Python dependencies:"
echo "   python3 -m venv venv"
echo "   source venv/bin/activate"
echo "   pip install -r requirements.txt"
echo ""
echo "2) Deploy the service:"
echo "   ./deploy.sh"
echo ""
echo "3) After deployment, send test requests:"
echo "   curl -X POST https://YOUR-SERVICE-URL/chat \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"prompt\":\"What is AI?\"}'"
echo ""
echo "4) Check Datadog metrics (~90s after first request):"
echo "   https://$DATADOG_SITE/metric/explorer"
echo "   Search for: llm.request.latency_ms"
echo ""
echo "================================================"
echo ""
echo "⚠️  IMPORTANT:"
echo "  - .env.local contains secrets, never commit it"
echo "  - Set a budget alert in Google Cloud Console"
echo "  - Review Datadog free tier limits"
echo ""
echo "For troubleshooting:"
echo "  https://github.com/your-repo/blob/main/README.md"
echo ""

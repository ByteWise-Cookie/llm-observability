#!/bin/bash

# Configuration
PROJECT_ID="coral-ethos-482409-a1"
SERVICE_NAME="llm-observability-service"
REGION="us-central1"
DATADOG_API_KEY="8c191b1c94a97a600e6202f5ddcdc175"
DATADOG_APP_KEY="0dc4ef3f405cd5ff05d38300173a6f4bf259643b"

# Build and push container
echo "Building container..."
gcloud builds submit --tag gcr.io/$PROJECT_ID/$SERVICE_NAME

# Deploy to Cloud Run
echo "Deploying to Cloud Run..."
gcloud run deploy $SERVICE_NAME \
  --image gcr.io/$PROJECT_ID/$SERVICE_NAME \
  --platform managed \
  --region $REGION \
  --allow-unauthenticated \
  --set-env-vars "GCP_PROJECT_ID=$PROJECT_ID,GCP_LOCATION=$REGION,MODEL_NAME=gemini-2.5-flash,DATADOG_API_KEY=$DATADOG_API_KEY,DATADOG_APP_KEY=$DATADOG_APP_KEY,ENVIRONMENT=production" \
  --memory 1Gi \
  --cpu 1 \
  --timeout 300

echo "Deployment complete!"
echo "Service URL:"
gcloud run services describe $SERVICE_NAME --region $REGION --format 'value(status.url)'

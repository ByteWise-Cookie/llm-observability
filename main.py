import os
import time
import uuid
import hashlib
import re
from flask import Flask, request, jsonify
from google.cloud import aiplatform
from vertexai.generative_models import GenerativeModel
import vertexai
from datadog_api_client import ApiClient, Configuration
from datadog_api_client.v2.api.metrics_api import MetricsApi
from datadog_api_client.v2.model.metric_intake_type import MetricIntakeType
from datadog_api_client.v2.model.metric_payload import MetricPayload
from datadog_api_client.v2.model.metric_point import MetricPoint
from datadog_api_client.v2.model.metric_resource import MetricResource
from datadog_api_client.v2.model.metric_series import MetricSeries
from datadog_api_client.v1.api.logs_api import LogsApi
from datadog_api_client.v1.model.http_log import HTTPLog
from datadog_api_client.v1.model.http_log_item import HTTPLogItem

app = Flask(__name__)

# Configuration
PROJECT_ID = os.getenv("GCP_PROJECT_ID")
LOCATION = os.getenv("GCP_LOCATION", "us-central1")
MODEL_NAME = os.getenv("MODEL_NAME", "gemini-2.5-flash")
DATADOG_API_KEY = os.getenv("DATADOG_API_KEY")
DATADOG_APP_KEY = os.getenv("DATADOG_APP_KEY")
SERVICE_NAME = "llm-observability-service"
ENVIRONMENT = os.getenv("ENVIRONMENT", "dev")

# Initialize Vertex AI
vertexai.init(project=PROJECT_ID, location=LOCATION)
model = GenerativeModel(MODEL_NAME)

# Datadog configuration
dd_configuration = Configuration()
dd_configuration.api_key["apiKeyAuth"] = DATADOG_API_KEY
dd_configuration.api_key["appKeyAuth"] = DATADOG_APP_KEY
dd_configuration.server_variables = {"site": "us5.datadoghq.com"}

def hash_prompt(prompt: str) -> str:
    """Create SHA256 hash of prompt for privacy-safe logging"""
    return hashlib.sha256(prompt.encode()).hexdigest()[:16]


def calculate_hallucination_risk(response_text: str, prompt: str, confidence: float) -> float:
    """
    Calculate hallucination risk score (0.0 - 1.0) using heuristics.
    Higher = more risk
    """
    risk_score = 0.0
    
    # Factor 1: Low confidence (40% weight)
    confidence_risk = 1.0 - confidence
    risk_score += confidence_risk * 0.4
    
    # Factor 2: Hedging language (30% weight)
    hedging_words = ['might', 'possibly', 'perhaps', 'maybe', 'i think', 
                     'could be', 'it seems', 'likely', 'probably']
    text_lower = response_text.lower()
    hedging_count = sum(1 for word in hedging_words if word in text_lower)
    hedging_risk = min(hedging_count / 5.0, 1.0)  # Cap at 1.0
    risk_score += hedging_risk * 0.3
    
    # Factor 3: Excessive verbosity (30% weight)
    response_length = len(response_text.split())
    prompt_length = len(prompt.split())
    verbosity_ratio = response_length / max(prompt_length, 1)
    verbosity_risk = min(verbosity_ratio / 50.0, 1.0)  # Cap at 50x ratio
    risk_score += verbosity_risk * 0.3
    
    return min(risk_score, 1.0)


def get_self_confidence(model_instance, original_prompt: str, original_response: str) -> float:
    """
    Ask the model to rate its confidence in the answer it gave.
    Returns score between 0.0 and 1.0
    """
    confidence_prompt = f"""You previously answered this question:
Question: {original_prompt}
Your answer: {original_response}

On a scale from 0.0 to 1.0, how confident are you that your answer is accurate and complete?
Respond with ONLY a number between 0.0 and 1.0, nothing else."""
    
    try:
        response = model_instance.generate_content(confidence_prompt)
        confidence_text = response.text.strip()
        # Extract number from response
        match = re.search(r'0?\.\d+|1\.0|0|1', confidence_text)
        if match:
            return float(match.group())
        return 0.5  # Default if parsing fails
    except Exception as e:
        print(f"Error getting self-confidence: {e}")
        return 0.5


def send_metrics_to_datadog(metrics_data: dict):
    """Send custom metrics to Datadog"""
    try:
        with ApiClient(dd_configuration) as api_client:
            api_instance = MetricsApi(api_client)
            
            timestamp = int(time.time())
            tags = [
                f"model_name:{metrics_data['model_name']}",
                f"service:{SERVICE_NAME}",
                f"env:{ENVIRONMENT}"
            ]
            
            series = []
            
            # Create metric series for each metric
            for metric_name, value in [
                ("llm.request.latency_ms", metrics_data["latency_ms"]),
                ("llm.self_confidence", metrics_data["self_confidence"]),
                ("llm.hallucination_risk", metrics_data["hallucination_risk"]),
                ("llm.answer_length", metrics_data["answer_length"]),
                ("llm.token.count", metrics_data.get("token_count", 0))
            ]:
                series.append(
                    MetricSeries(
                        metric=metric_name,
                        type=MetricIntakeType.UNSPECIFIED,
                        points=[
                            MetricPoint(
                                timestamp=timestamp,
                                value=value,
                            )
                        ],
                        resources=[
                            MetricResource(
                                name=SERVICE_NAME,
                                type="service",
                            )
                        ],
                        tags=tags,
                    )
                )
            
            payload = MetricPayload(series=series)
            api_instance.submit_metrics(body=payload)
            
    except Exception as e:
        print(f"Error sending metrics to Datadog: {e}")



def send_logs_to_datadog(log_data):
    """Send structured logs to Datadog"""
    try:
        with ApiClient(dd_configuration) as api_client:
            api_instance = LogsApi(api_client)
            
            # Convert all numeric values to strings for Datadog logs API
            log_data_str = {}
            for key, value in log_data.items():
                if isinstance(value, (int, float)):
                    log_data_str[key] = str(value)
                else:
                    log_data_str[key] = value
            
            body = HTTPLog([
                HTTPLogItem(
                    ddsource="llm-observability",
                    ddtags=f"env:{ENVIRONMENT},service:{SERVICE_NAME}",
                    hostname=SERVICE_NAME,
                    message=f"LLM request completed: request_id={log_data.get('request_id', 'unknown')}",
                    service=SERVICE_NAME,
                    **log_data_str  # Use string-converted version
                ),
            ])
            
            api_instance.submit_log(body=body)
            
    except Exception as e:
        print(f"Error sending logs to Datadog: {e}")


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({"status": "healthy"}), 200


@app.route('/chat', methods=['POST'])
def chat():
    """Main chat endpoint with full observability"""
    request_id = str(uuid.uuid4())
    start_time = time.time()
    
    try:
        # Parse request
        data = request.get_json()
        prompt = data.get('prompt', '')
        
        if not prompt:
            return jsonify({"error": "prompt is required"}), 400
        
        # Call Gemini
        llm_start = time.time()
        response = model.generate_content(prompt)
        llm_end = time.time()
        
        response_text = response.text
        
        # Get self-confidence score
        confidence_score = get_self_confidence(model, prompt, response_text)
        
        # Calculate hallucination risk
        hallucination_risk = calculate_hallucination_risk(
            response_text, prompt, confidence_score
        )
        
        # Calculate metrics
        latency_ms = (llm_end - llm_start) * 1000
        answer_length = len(response_text.split())
        token_count = response.usage_metadata.total_token_count if hasattr(response, 'usage_metadata') else 0
        
        # Prepare telemetry data
        metrics_data = {
            "model_name": MODEL_NAME,
            "latency_ms": latency_ms,
            "self_confidence": confidence_score,
            "hallucination_risk": hallucination_risk,
            "answer_length": answer_length,
            "token_count": token_count
        }
        
        log_data = {
            "request_id": request_id,
            "prompt_hash": hash_prompt(prompt),
            "model_name": MODEL_NAME,
            "latency_ms": latency_ms,
            "hallucination_risk": hallucination_risk,
            "self_confidence": confidence_score,
            "answer_length": answer_length,
            "status": "success"
        }
        
        # Send telemetry (non-blocking)
        send_metrics_to_datadog(metrics_data)
        send_logs_to_datadog(log_data)
        
        # Return response
        end_time = time.time()
        return jsonify({
            "request_id": request_id,
            "response": response_text,
            "metadata": {
                "latency_ms": round((end_time - start_time) * 1000, 2),
                "confidence": round(confidence_score, 3),
                "hallucination_risk": round(hallucination_risk, 3),
                "model": MODEL_NAME
            }
        }), 200
        
    except Exception as e:
        # Log error
        error_time = time.time()
        error_data = {
            "request_id": request_id,
            "error": str(e),
            "latency_ms": (error_time - start_time) * 1000,
            "status": "error"
        }
        send_logs_to_datadog(error_data)
        
        # Send error metric
        try:
            with ApiClient(dd_configuration) as api_client:
                api_instance = MetricsApi(api_client)
                series = [
                    MetricSeries(
                        metric="llm.error.count",
                        type=MetricIntakeType.UNSPECIFIED,
                        points=[MetricPoint(timestamp=int(time.time()), value=1.0)],
                        tags=[f"service:{SERVICE_NAME}", f"env:{ENVIRONMENT}"]
                    )
                ]
                api_instance.submit_metrics(body=MetricPayload(series=series))
        except:
            pass
        
        return jsonify({"error": str(e), "request_id": request_id}), 500


if __name__ == '__main__':
    port = int(os.getenv('PORT', 8080))
    app.run(host='0.0.0.0', port=port)

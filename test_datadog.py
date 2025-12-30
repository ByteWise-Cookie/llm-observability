from datadog_api_client import ApiClient, Configuration
from datadog_api_client.v2.api.metrics_api import MetricsApi
from datadog_api_client.v2.model.metric_payload import MetricPayload
from datadog_api_client.v2.model.metric_series import MetricSeries
from datadog_api_client.v2.model.metric_point import MetricPoint
from datadog_api_client.v2.model.metric_intake_type import MetricIntakeType
import os
import time

config = Configuration()
config.api_key["apiKeyAuth"] = os.getenv("DATADOG_API_KEY")
config.api_key["appKeyAuth"] = os.getenv("DATADOG_APP_KEY")

with ApiClient(config) as api_client:
    api = MetricsApi(api_client)
    
    series = [MetricSeries(
        metric="test.connectivity",
        type=MetricIntakeType.UNSPECIFIED,
        points=[MetricPoint(timestamp=int(time.time()), value=1.0)],
        tags=["source:local_test"]
    )]
    
    try:
        api.submit_metrics(body=MetricPayload(series=series))
        print("✓ Datadog metrics API working!")
    except Exception as e:
        print(f"✗ Error: {e}")

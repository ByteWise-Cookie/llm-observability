import vertexai
from vertexai.generative_models import GenerativeModel
import os
import time

project_id = os.getenv("GCP_PROJECT_ID")
vertexai.init(project=project_id, location="us-central1")
model = GenerativeModel("gemini-2.5-flash")

start = time.time()
response = model.generate_content("What is 2+2?")
end = time.time()

latency_ms = (end - start) * 1000
print(f"Latency: {latency_ms:.0f}ms")
if latency_ms < 5000:
    print("✓ Latency acceptable")
else:
    print("⚠ Latency high - check network")

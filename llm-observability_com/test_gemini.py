import vertexai
from vertexai.generative_models import GenerativeModel
import os

project_id = os.getenv("GCP_PROJECT_ID")
location = "us-central1"

vertexai.init(project=project_id, location=location)

# Hardcoded correct model name
model = GenerativeModel("gemini-2.5-flash")

response = model.generate_content("Say 'hello' in exactly one word")
print(f"✓ Gemini works! Response: {response.text}")

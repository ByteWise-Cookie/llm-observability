import requests
import json
import time

# Configuration
SERVICE_URL = "https://llm-observability-service-xxxx.run.app"  # Replace with your Cloud Run URL
CHAT_ENDPOINT = f"{SERVICE_URL}/chat"

def send_request(prompt, description):
    """Send request and print results"""
    print(f"\n{'='*60}")
    print(f"TEST: {description}")
    print(f"{'='*60}")
    print(f"Prompt: {prompt[:100]}...")
    
    start = time.time()
    response = requests.post(
        CHAT_ENDPOINT,
        json={"prompt": prompt},
        headers={"Content-Type": "application/json"}
    )
    end = time.time()
    
    if response.status_code == 200:
        data = response.json()
        print(f"\n✓ Request ID: {data['request_id']}")
        print(f"✓ Response: {data['response'][:200]}...")
        print(f"\nMetadata:")
        print(f"  - Latency: {data['metadata']['latency_ms']}ms")
        print(f"  - Confidence: {data['metadata']['confidence']}")
        print(f"  - Hallucination Risk: {data['metadata']['hallucination_risk']}")
        print(f"  - Model: {data['metadata']['model']}")
        
        # Interpretation
        risk = data['metadata']['hallucination_risk']
        confidence = data['metadata']['confidence']
        
        if risk > 0.7:
            print(f"\n⚠️  HIGH RISK: This response should trigger an alert!")
        elif risk > 0.6:
            print(f"\n⚠️  MODERATE RISK: Approaching alert threshold")
        else:
            print(f"\n✓ LOW RISK: Response appears reliable")
            
        if confidence < 0.5:
            print(f"⚠️  LOW CONFIDENCE: Model is uncertain")
            
    else:
        print(f"\n✗ Error: {response.status_code}")
        print(f"  {response.text}")
    
    print(f"\nTotal time: {(end - start) * 1000:.0f}ms")


# Test Case 1: Normal, factual query
print("\n" + "="*60)
print("SCENARIO 1: Normal Factual Query")
print("Expected: Low risk, high confidence, fast response")
print("="*60)

send_request(
    "What is the capital of France?",
    "Simple factual question"
)

time.sleep(2)  # Wait between requests


# Test Case 2: Ambiguous/uncertain query
print("\n" + "="*60)
print("SCENARIO 2: Ambiguous Query")
print("Expected: Moderate-high risk, lower confidence, hedging language")
print("="*60)

send_request(
    "Will it rain in Chennai next Tuesday at 3pm?",
    "Specific future prediction (impossible to know)"
)

time.sleep(2)


# Test Case 3: Complex reasoning query
print("\n" + "="*60)
print("SCENARIO 3: Complex Reasoning")
print("Expected: Moderate risk, moderate confidence, higher latency")
print("="*60)

send_request(
    "Explain the philosophical implications of quantum entanglement on the nature of causality and determinism in a universe governed by both quantum mechanics and general relativity.",
    "Complex philosophical reasoning"
)

time.sleep(2)


# Test Case 4: Prompt designed to trigger uncertainty
print("\n" + "="*60)
print("SCENARIO 4: Hallucination-Prone Query")
print("Expected: HIGH RISK (>0.7), low confidence, should trigger alert")
print("="*60)

send_request(
    "Tell me about the biography of Dr. Xylophon Marthexius, the renowned 18th century Croatian mathematician who discovered the Theorem of Hyperbolic Infinities.",
    "Query about non-existent person/theorem"
)

time.sleep(2)


# Test Case 5: Open-ended speculation
print("\n" + "="*60)
print("SCENARIO 5: Speculative Query")
print("Expected: Moderate-high risk, lots of hedging language")
print("="*60)

send_request(
    "What will be the most important technological breakthrough in 2030?",
    "Pure speculation about future"
)

time.sleep(2)


# Test Case 6: Very broad query (verbosity test)
print("\n" + "="*60)
print("SCENARIO 6: Overly Broad Query")
print("Expected: Higher risk due to verbosity, longer latency")
print("="*60)

send_request(
    "Tell me everything about artificial intelligence.",
    "Extremely broad query"
)


print("\n" + "="*60)
print("TESTING COMPLETE")
print("="*60)
print("\nNext steps:")
print("1. Open Datadog dashboard to view metrics")
print("2. Check for alert triggers (especially Scenario 4)")
print("3. Review logs for request_ids")
print("4. Observe correlation between risk and confidence")
print("5. Note latency patterns")
print("\nDatadog queries to try:")
print("  - service:llm-observability-service")
print("  - hallucination_risk:>0.7")
print("  - self_confidence:<0.5")
print("="*60)

# LLM Health Observability System

**Real-time quality monitoring for production LLM deployments using Google Gemini & Datadog**

---

## Problem Statement

Modern LLMs like Gemini 2.5 Flash are highly capable, but they fail in subtle ways that traditional monitoring misses:

- ✅ **CPU, memory, latency**: Easy to observe
- ✅ **HTTP errors, crashes**: Easy to detect
- ❌ **Confident-sounding nonsense**: Invisible to standard metrics
- ❌ **Model drift, quality degradation**: No alerts until users complain

**The gap:** Existing observability tools treat LLMs as black-box APIs. They measure *system health* but not *output quality*.

**The risk:** Silent failures where responses are plausible but unreliable, delivered with high confidence.

---

## Solution Overview

This system provides **operational observability for LLM quality risk**, not ground-truth hallucination detection.

### What It Does
- Instruments every LLM request with quality heuristics
- Generates actionable metrics: confidence, hedging, verbosity, latency
- Sends telemetry to Datadog for alerting, dashboards, and investigation
- Flags high-risk responses in real-time for engineer review

### What It Does NOT Do
- Claim to "detect hallucinations" with academic accuracy
- Replace human evaluation or user feedback loops
- Store or log raw prompts (privacy-safe by design)
- Provide ground-truth correctness scores

**Philosophy:** Treat LLM quality as a **risk signal** that requires operational response, like latency regressions or error rate spikes.

---

## Architecture
```
┌─────────────┐
│   Client    │
│  (API call) │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────┐
│   Google Cloud Run Service      │
│   ┌─────────────────────────┐   │
│   │  /chat Endpoint         │   │
│   └───────┬─────────────────┘   │
│           │                     │
│           ▼                     │
│   ┌─────────────────────────┐   │
│   │  Gemini 2.5 Flash API   │   │
│   │  (Vertex AI)            │   │
│   └───────┬─────────────────┘   │
│           │                     │
│           ▼                     │
│   ┌─────────────────────────┐   │
│   │  Evaluation Layer       │   │
│   │  • Self-confidence      │   │
│   │  • Hedging detection    │   │
│   │  • Verbosity analysis   │   │
│   │  • Risk scoring         │   │
│   └───────┬─────────────────┘   │
│           │                     │
└───────────┼─────────────────────┘
            │
            ▼
    ┌───────────────┐
    │   Datadog     │
    │ • Metrics     │
    │ • Logs        │
    │ • Alerts      │
    │ • Dashboard   │
    └───────────────┘
```

**Flow:**
1. User sends prompt to `/chat` endpoint
2. Service calls Gemini 2.5 Flash via Vertex AI
3. Response passes through evaluation layer
4. Metrics + structured logs sent to Datadog
5. Alerts trigger if risk thresholds exceeded
6. Engineers investigate via dashboard and logs

---

## Key Metrics & Risk Signals

### System Metrics
- **`llm.request.latency_ms`**: End-to-end response time
- **`llm.token.count`**: Input + output tokens (cost tracking)
- **`llm.error.count`**: API failures, timeouts, quota errors

### Quality Metrics
- **`llm.self_confidence`** (0.0 - 1.0)
  - After generating a response, we ask Gemini to rate its own confidence
  - Lower scores indicate model uncertainty
  - **Limitation:** Models can be overconfident on hallucinations

- **`llm.hallucination_risk`** (0.0 - 1.0)
  - Composite heuristic combining:
    - **Low confidence** (40% weight): `1.0 - self_confidence`
    - **Hedging language** (30% weight): Detection of words like "might", "possibly", "I think", "could be"
    - **Excessive verbosity** (30% weight): Response length >> prompt length
  - **Interpretation:**
    - `< 0.5`: Low risk
    - `0.5 - 0.7`: Moderate risk (review)
    - `> 0.7`: High risk (alert)
  - **Not a ground truth score**: This is an operational signal for triage

- **`llm.answer_length`**: Word count (flags unexpectedly long responses)

### Privacy & Logging
- Prompts are **never stored raw**
- `prompt_hash` (SHA256, first 16 chars) used for correlation
- All logs structured, queryable, retention-controlled

---

## Alerts & Dashboard

### Active Alerts

**1. High Hallucination Risk**
- **Trigger:** `avg(llm.hallucination_risk) > 0.7` for 5 minutes
- **Action:** Review recent logs, check for adversarial inputs, evaluate if model version changed
- **Why it matters:** Sustained high risk indicates quality degradation

**2. Latency Regression**
- **Trigger:** `p95(llm.request.latency_ms) > 3000ms` for 15 minutes
- **Action:** Check Vertex AI quotas, Cloud Run scaling, prompt complexity
- **Why it matters:** Slow responses degrade user experience

**3. Error Rate Spike**
- **Trigger:** `sum(llm.error.count) > 5` in 5 minutes
- **Action:** Check Vertex AI status, verify API credentials, review quota limits
- **Why it matters:** Service unavailability

### Dashboard Widgets
- **Hallucination risk over time**: Trend line with 0.7 threshold marker
- **Self-confidence distribution**: Histogram showing confidence spread
- **Latency percentiles**: P50, P95, P99 tracking
- **Request rate & error rate**: Volume + failure correlation
- **Active alerts panel**: Real-time alert status

**What Engineers Learn:**
- Is quality degrading over time? (Risk trending up)
- Do certain prompt patterns correlate with high risk?
- Is latency impacting confidence? (Rushed responses = lower quality)
- When did the last deployment affect quality?

---

## Tech Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **LLM** | Google Gemini 2.5 Flash (Vertex AI) | Inference engine |
| **Compute** | Google Cloud Run | Serverless API hosting |
| **Observability** | Datadog | Metrics, logs, alerts, dashboards |
| **Backend** | Python 3.11 + Flask | API service |
| **Libraries** | `vertexai`, `datadog-api-client` | Integration SDKs |

**Why These Choices:**
- **Gemini 2.5 Flash**: Best-in-class quality-to-latency ratio
- **Cloud Run**: Scales to zero, sub-second cold starts, cost-effective
- **Datadog**: Enterprise observability with built-in alerting, correlation, and integrations

---

## Deployment

### Prerequisites
- Google Cloud project with Vertex AI enabled
- Datadog account (free trial works)
- `gcloud` CLI authenticated

### Quick Start
```bash
# 1. Clone repository
git clone git@github.com:ByteWise-Cookie/llm-observability.git
cd llm-observability

# 2. Set environment variables
export GCP_PROJECT_ID=your-project-id
export DATADOG_API_KEY=your-datadog-api-key
export DATADOG_APP_KEY=your-datadog-app-key

# 3. Deploy to Cloud Run
./deploy.sh

# 4. Test endpoint
curl -X POST https://your-service-url.run.app/chat \
  -H "Content-Type: application/json" \
  -d '{"prompt":"What is AI?"}'
```

### Configuration
- **Model selection:** Set `MODEL_NAME` env var (default: `gemini-2.5-flash`)
- **Alert thresholds:** Edit Datadog monitor configs
- **Sampling:** For high traffic, sample metrics (1-10% of requests)

---

## Responsible AI Considerations

### Risk Signals ≠ Ground Truth
This system produces **operational risk scores**, not factual correctness judgments. A high risk score means "review this response," not "this response is definitely wrong."

### No Automated Censorship
We do not block or filter responses based on risk scores. All responses reach the user. Risk scores are for **post-hoc analysis and alerting**.

### Privacy by Design
- Raw prompts never stored
- SHA256 hashes used for correlation
- Logs have configurable retention (default: 30 days)
- No PII or sensitive data in telemetry

### Human-in-the-Loop
This tool is designed to **assist engineers**, not replace them. High-risk alerts should trigger human review, A/B testing, or prompt refinement—not automated actions.

### Bias Considerations
Hedging language detection may have cultural/linguistic biases (e.g., "I think" is more common in some English dialects). Risk scores should be interpreted in context, not as universal truth.

---

## Future Enhancements

- **Semantic similarity checks**: Compare response to retrieved context (RAG)
- **User feedback integration**: Thumbs up/down to refine risk scoring
- **Prompt injection detection**: Flag adversarial inputs
- **Cost tracking**: Per-request cost estimation from token counts
- **A/B testing support**: Compare risk scores across model versions

---

## License

MIT License - See LICENSE file

---

## Acknowledgments

Built for the AI Partner Catalyst using:
- Google Cloud Vertex AI & Gemini 2.5 Flash
- Datadog Observability Platform
- Inspired by production challenges in deploying LLMs at scale

---

## Contact

For questions or feedback: cipher0xx@gmail.com

**Demo Video:** [..]

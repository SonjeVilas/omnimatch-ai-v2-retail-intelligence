copy "C:\Users\Lenovo\.gemini\antigravity-ide\brain\7e1072b0-f74e-4a0c-ab4e-db2c988726f5\architecture_diagram_1790233541020.jpg" "C:\Users\Lenovo\Desktop\retail-intelligence-platform (1)\architecture.jpg"



<p align="center">
  <img src="https://img.shields.io/badge/Snowflake-29B5E8?style=for-the-badge&logo=snowflake&logoColor=white" alt="Snowflake"/>
  <img src="https://img.shields.io/badge/Cortex_AI-6366F1?style=for-the-badge&logo=snowflake&logoColor=white" alt="Cortex AI"/>
  <img src="https://img.shields.io/badge/Streamlit-FF4B4B?style=for-the-badge&logo=streamlit&logoColor=white" alt="Streamlit"/>
  <img src="https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white" alt="Python"/>
  <img src="https://img.shields.io/badge/SQL-4479A1?style=for-the-badge&logo=postgresql&logoColor=white" alt="SQL"/>
</p>

<h1 align="center">⚡ OmniMatch AI v2: Retail Intelligence Platform</h1>

<p align="center">
  <strong>AI-Powered Product Entity Resolution, Dynamic Pricing & Market Intelligence</strong><br/>
  Built Entirely on Native Snowflake Features
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Hackathon-Snowflake_x_Capgemini_2026-0284c7?style=flat-square" alt="Hackathon"/>
  <img src="https://img.shields.io/badge/Team-MatchMatrix-6366f1?style=flat-square" alt="Team"/>
  <img src="https://img.shields.io/badge/Precision-94.33%25-10b981?style=flat-square" alt="Precision"/>
  <img src="https://img.shields.io/badge/F1_Score-82.20%25-a855f7?style=flat-square" alt="F1"/>
  <img src="https://img.shields.io/badge/Snowflake_Features-17-38bdf8?style=flat-square" alt="Features"/>
</p>

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Key Results](#-key-results)
- [Architecture](#-architecture)
- [Snowflake Features Used (17)](#-snowflake-features-used-17)
- [Project Structure](#-project-structure)
- [Pipeline Deep Dive](#-pipeline-deep-dive)
  - [Step 1: Foundation Layer](#step-1-foundation-layer)
  - [Step 2: Cortex AI Pipeline](#step-2-cortex-ai-pipeline)
  - [Step 3: Dynamic Pricing Engine](#step-3-dynamic-pricing-engine)
  - [Step 4: Semantic Views](#step-4-semantic-views)
  - [Step 5: Cortex Agents](#step-5-cortex-agents)
  - [Step 6: Evaluation & Benchmarking](#step-6-evaluation--benchmarking)
  - [Step 7: Pipeline Execution](#step-7-pipeline-execution)
  - [Step 8: Data Quality Monitoring](#step-8-data-quality-monitoring)
- [Streamlit Dashboard](#-streamlit-dashboard)
- [Setup & Installation](#-setup--installation)
- [Database Schema](#-database-schema)
- [Dataset](#-dataset)
- [Tech Stack](#-tech-stack)
- [Team](#-team)
- [License](#-license)

---

## 🎯 Overview

**OmniMatch AI v2** is an enterprise-grade AI-powered entity resolution pipeline that automatically matches products across competing retailers — **Abt Electronics** and **Buy.com** — enabling dynamic competitive pricing strategies and comprehensive market intelligence.

### What makes this project unique?

- 🧠 **Real AI, not simulated** — Every LLM call, every embedding, every agent is a real Snowflake Cortex invocation
- 🔄 **Fully incremental** — Streams + Tasks + Dynamic Tables create a production-ready pipeline that handles new products automatically
- 🤖 **3 Autonomous Cortex Agents** — Real `CREATE AGENT` agents visible in Snowflake Intelligence, not keyword-routed templates
- 📊 **Rigorous benchmarking** — Ground truth evaluation with Precision/Recall/F1, not just demo metrics
- 💰 **Production-safe pricing** — Margin floors, max discount limits, and elasticity modeling with guardrails

### The Problem

Retailers need to know what their competitors are charging for the **same products**. But product catalogs across retailers have different names, descriptions, model numbers, and formatting. Manually matching thousands of products is impractical.

### The Solution

A multi-strategy hybrid AI pipeline that:
1. **Cleans & normalizes** product data using Dynamic Tables
2. **Generates vector embeddings** using Cortex Arctic
3. **Matches products** using a 4-signal hybrid scoring algorithm
4. **Verifies matches** using LLM reasoning (`llama3.1-70b`)
5. **Recommends optimal prices** using elasticity-based demand modeling
6. **Detects market anomalies** with actionable alerts
7. **Enables natural language analytics** via 3 Cortex Agents

---

## 🏆 Key Results

| Metric | Value | Context |
|--------|-------|---------|
| **Precision** | **94.33%** | Only 48 false positives out of 847 matches |
| **Recall** | **72.84%** | Found 799 of 1,097 true matches |
| **F1 Score** | **82.20%** | Balanced accuracy measure |
| **Products Matched** | **847** | Across 2,162 products (1,070 Abt + 1,092 Buy.com) |
| **LLM Verified** | **~750+** | Auto-confirmed (≥0.80) + LLM-verified (0.50–0.80) |
| **Pricing Strategies** | **4** | Each generates ~631 recommendations |
| **Cortex Agents** | **3** | Product Matching, Price Optimization, Market Intelligence |
| **Snowflake Features** | **17** | See full list below |

### v2 vs v1 Improvement

| Metric | v1 (Original) | v2 (Redesigned) | Improvement |
|--------|--------------|-----------------|-------------|
| Precision | 87.82% | **94.33%** | +6.51% |
| Recall | 72.29% | **72.84%** | +0.55% |
| F1 Score | 79.30% | **82.20%** | +2.90% |
| False Positives | 110 | **48** | **-56% fewer errors** |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DATA INGESTION LAYER                         │
│  RAW_ABT_CATALOG (1,070) ──────── RAW_BUY_CATALOG (1,092)         │
│         │                                    │                      │
│         ▼ Streams (CDC)                      ▼ Streams (CDC)        │
│  STREAM_ABT_CHANGES                  STREAM_BUY_CHANGES            │
└──────────────┬──────────────────────────────┬───────────────────────┘
               │                              │
               ▼                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     DATA PROCESSING LAYER                           │
│  DT_CLEAN_ABT_CATALOG ────────── DT_CLEAN_BUY_CATALOG             │
│  (Dynamic Table, 1hr lag)        (Dynamic Table, 1hr lag)          │
│  • Brand extraction (25 brands)  • Price normalization              │
│  • Model number parsing (regex)  • Embedding text generation        │
└──────────────┬──────────────────────────────┬───────────────────────┘
               │                              │
        ┌──────┴──────┐               ┌──────┴──────┐
        ▼             ▼               ▼             ▼
┌──────────────┐ ┌─────────────┐ ┌──────────────┐ ┌──────────────┐
│ ABT_EMBEDDINGS│ │  CORTEX     │ │ BUY_EMBEDDINGS│ │              │
│ 768-dim Arctic│ │  SEARCH     │ │ 768-dim Arctic│ │   UDFs       │
│ Vectors       │ │  SERVICE    │ │ Vectors       │ │ Token+Model  │
└───────┬───────┘ └──────┬──────┘ └──────┬────────┘ └──────┬───────┘
        │                │               │                  │
        └────────────────┴───────────────┴──────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      AI MATCHING LAYER                               │
│  V_CANDIDATE_MATCHES ──▶ 4-Strategy Hybrid Scoring                  │
│  • Vector Cosine (40%)  • Model Number (25%)                        │
│  • Token Jaccard (25%)  • Brand Alignment (10%)                     │
│                                                                      │
│  EXECUTE_ENTITY_RESOLUTION() ──▶ Top-1 per product                  │
│  VERIFY_MATCHES_WITH_LLM()  ──▶ llama3.1-70b verification          │
│                                                                      │
│  ══▶ FINAL_PRODUCT_MATCHES (847 rows, with LLM reasoning)          │
└──────────────┬──────────────────────────────┬───────────────────────┘
               │                              │
        ┌──────┴──────┐               ┌──────┴──────┐
        ▼             ▼               ▼             ▼
┌──────────────┐ ┌─────────────┐ ┌──────────────┐ ┌──────────────┐
│  PRICING     │ │  MARKET     │ │  BENCHMARK   │ │  3 SEMANTIC  │
│  ENGINE      │ │  INTEL      │ │  EVALUATION  │ │  VIEWS       │
│ 4 strategies │ │ Anomalies   │ │ P/R/F1       │ │ + VQRs       │
└──────┬───────┘ └──────┬──────┘ └──────────────┘ └──────┬───────┘
       │                │                                 │
       └────────────────┴─────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     INTELLIGENCE LAYER                               │
│  🔬 PRODUCT_MATCHING_AGENT     (Analyst + Search + Chart)           │
│  💰 PRICE_OPTIMIZATION_AGENT   (Analyst + Chart)                    │
│  🌐 MARKET_INTELLIGENCE_AGENT  (Analyst + Chart)                    │
│                                                                      │
│  Accessible via: Snowflake Intelligence UI + Streamlit Dashboard    │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 🛠️ Snowflake Features Used (17)

| # | Feature | Implementation | Significance |
|---|---------|---------------|-------------|
| 1 | **Cortex EMBED_TEXT_768** | `snowflake-arctic-embed-m` on 2,162 products | Semantic vector embeddings for product matching |
| 2 | **VECTOR_COSINE_SIMILARITY** | In candidate match scoring view | Native vector similarity — no external vector DB needed |
| 3 | **CORTEX.COMPLETE** | `llama3.1-70b` for match verification + error analysis | Real LLM reasoning per match, not static strings |
| 4 | **Cortex Search Service** | `PRODUCT_SEARCH_SERVICE` (2,162 products) | Hybrid vector + keyword search with attribute filtering |
| 5 | **Cortex Agents (3×)** | `CREATE AGENT ... FROM SPECIFICATION` | Real autonomous agents with tool orchestration |
| 6 | **Semantic Views (3×)** | Dimensions, facts, metrics, VQRs | Structured data layer for Cortex Analyst |
| 7 | **Cortex Analyst** | `cortex_analyst_text_to_sql` tool | Natural language to SQL generation |
| 8 | **Data to Chart** | `data_to_chart` tool on all 3 agents | Agent-generated visualizations |
| 9 | **Dynamic Tables (2×)** | `TARGET_LAG = '1 hour'` | Auto-refreshing cleaned catalogs |
| 10 | **Streams (2×)** | `APPEND_ONLY` on raw tables | CDC for new product detection |
| 11 | **Tasks (3×)** | Stream-triggered + chained | Incremental pipeline: embed → resolve → verify |
| 12 | **JavaScript UDFs (2×)** | Jaccard + Levenshtein | Token overlap and model number similarity |
| 13 | **Stored Procedures (9×)** | SQL-based pipeline orchestration | Embedding gen, entity resolution, pricing, evaluation |
| 14 | **Data Metric Functions (5×)** | 3 custom + 2 system DMFs | Precision drift, embedding freshness, match quality |
| 15 | **Snowflake Alerts (2×)** | Anomaly threshold + precision degradation | Proactive quality monitoring every 1–6 hours |
| 16 | **Streamlit in Snowflake** | 7-tab dashboard with real agent chat | Production dashboard querying Snowflake directly |
| 17 | **Snowflake Intelligence** | Agents visible in AI & ML → Agents | Natural language analytics in Snowsight |

---

## 📁 Project Structure

```
omnimatch-ai-v2-retail-intelligence/
│
├── 📄 README.md                        # This file
├── 📄 .gitignore                       # Git ignore rules
│
├── 🗄️ SQL Pipeline (execute in order)
│   ├── 01_foundation.sql               # Database, schemas, Dynamic Tables, Streams, Tasks, UDFs
│   ├── 02_cortex_ai_pipeline.sql       # Cortex Search, embeddings, entity resolution, LLM verification
│   ├── 03_pricing_and_market_intel.sql # Dynamic pricing engine, market intelligence views
│   ├── 04_semantic_views.sql           # 3 Semantic Views with VQRs for Cortex Agents
│   ├── 05_cortex_agents.sql            # 3 Cortex Agents (CREATE AGENT)
│   ├── 06_evaluation.sql               # Ground truth evaluation, accuracy views, LLM error analysis
│   ├── 07_execute_pipeline.sql         # End-to-end pipeline execution script
│   └── 08_dmf_and_alerts.sql           # Data Metric Functions + Snowflake Alerts
│
├── 🖥️ Streamlit Dashboard (Local)
│   ├── app.py                          # Streamlit app using get_active_session() + Plotly
│   └── environment.yml                 # Conda environment (plotly, snowflake-snowpark-python)
│
├── 🖥️ Streamlit Dashboard (Snowflake Workspace)
│   └── omnimatch-ai-v2/
│       ├── streamlit_app.py            # Streamlit app using st.connection("snowflake") + Altair
│       ├── snowflake.yml               # Snowflake deployment config
│       ├── pyproject.toml              # Python dependencies
│       └── .streamlit/
│           └── config.toml             # Streamlit theme configuration
│
└── 📚 Documentation
    ├── PROJECT_DOCUMENTATION.md        # Detailed project documentation
    └── omnimatch-ai-v2/
        ├── PROJECT_DOCUMENTATION.md    # Documentation (Workspace copy)
        ├── DEMO_PREPARATION_GUIDE.md   # Demo preparation guide
        └── DEMO_TRANSCRIPT.md          # Demo transcript
```

---

## 🔬 Pipeline Deep Dive

### Step 1: Foundation Layer
**File:** `01_foundation.sql`

Sets up the entire infrastructure:

- **Database & Schemas**: `RETAIL_INTELLIGENCE_V2_DB` with `CORE`, `CORTEX_AI`, and `ANALYTICS` schemas for separation of concerns
- **Raw Tables**: Copies source data from v1 database for independence (1,070 Abt + 1,092 Buy.com + 1,097 ground truth pairs)
- **Dynamic Tables**: Auto-refreshing cleaned catalogs with:
  - Brand extraction (25 consumer electronics brands via CASE expressions)
  - Model number parsing (regex: `[A-Z]{1,4}[-]?[0-9]{2,}[A-Z0-9-]*`)
  - Price normalization (`TRY_CAST` with regex cleaning)
  - Embedding text payload generation
- **Streams**: `APPEND_ONLY` CDC on both raw tables for detecting new product inserts
- **JavaScript UDFs**:
  - `UDF_TOKEN_OVERLAP_SCORE`: Jaccard similarity (tokenize → set intersection / union)
  - `UDF_MODEL_SIMILARITY`: Levenshtein distance with substring containment boost
- **Embedding Tables**: Store 768-dimension `snowflake-arctic-embed-m` vectors
- **Task**: `TASK_REFRESH_EMBEDDINGS` — runs every 60 minutes when streams have data

```sql
-- Example: Dynamic Table with brand extraction
CREATE OR REPLACE DYNAMIC TABLE DT_CLEAN_ABT_CATALOG
    TARGET_LAG = '1 hour'
    WAREHOUSE = RETAIL_AI_V2_WH
AS
SELECT
    ID, NAME, DESCRIPTION,
    TRY_CAST(REGEXP_REPLACE(PRICE, '[^0-9.]', '') AS FLOAT) AS CLEAN_PRICE,
    CASE
        WHEN UPPER(NAME) LIKE '%SONY%' THEN 'Sony'
        WHEN UPPER(NAME) LIKE '%CANON%' THEN 'Canon'
        -- ... 23 more brands
        ELSE 'Other'
    END AS BRAND,
    REGEXP_SUBSTR(UPPER(NAME), '[A-Z]{1,4}[\\-]?[0-9]{2,}[A-Z0-9\\-]*') AS EXTRACTED_MODEL,
    NAME || ' | ' || COALESCE(DESCRIPTION, '') AS EMBEDDING_TEXT,
    'ABT' AS SOURCE_CATALOG
FROM RAW_ABT_CATALOG WHERE NAME IS NOT NULL;
```

---

### Step 2: Cortex AI Pipeline
**File:** `02_cortex_ai_pipeline.sql`

The core AI matching engine:

#### Cortex Search Service
Hybrid vector + keyword search across both catalogs (2,162 products) with attribute filtering by brand, price, source catalog, and model number.

#### 4-Strategy Hybrid Scoring

| Signal | Weight | Method |
|--------|--------|--------|
| Vector Cosine Similarity | **40%** | `VECTOR_COSINE_SIMILARITY` on 768-dim Cortex Arctic embeddings |
| Model Number Match | **25%** | Levenshtein distance on extracted SKUs (JavaScript UDF) |
| Token Jaccard Overlap | **25%** | Jaccard similarity on tokenized product names (JavaScript UDF) |
| Brand Alignment | **10%** | Binary — 1.0 if same known brand, 0.0 otherwise |

**Special rules:**
- **Model exact match boost**: if model_score ≥ 0.90 → composite = 0.95 + (0.05 × vector_score)
- **Brand contradiction penalty**: if both have known but *different* brands → score × 0.30

#### Entity Resolution
`EXECUTE_ENTITY_RESOLUTION(threshold)` selects the best match per Abt product using `ROW_NUMBER() OVER (PARTITION BY ABT_ID ORDER BY COMPOSITE_SCORE DESC)`.

#### LLM Verification
`VERIFY_MATCHES_WITH_LLM(batch_size)` uses `CORTEX.COMPLETE('llama3.1-70b')`:
- **Auto-confirms** matches with score ≥ 0.80
- **LLM-verifies** uncertain matches (0.50–0.80) with structured JSON responses
- Returns per-match reasoning (e.g., *"Both are the Sony DSC-RX100 compact camera with identical model number"*)

#### Task Chain
```
TASK_REFRESH_EMBEDDINGS (stream-triggered, 60min)
    └── TASK_RESOLVE_MATCHES (chained)
        └── TASK_LLM_VERIFY (chained)
```

---

### Step 3: Dynamic Pricing Engine
**File:** `03_pricing_and_market_intel.sql`

#### 4 Configurable Pricing Strategies

| Strategy | Undercut | Min Margin | Max Discount | Use Case |
|----------|----------|------------|--------------|----------|
| 🔥 Aggressive Undercut | 2.5% | 10% floor | 25% cap | Win on price |
| 🤝 Price Matcher | 0% | 12% floor | 20% cap | Match competition |
| 💎 Margin Maximizer | 1% | 18% floor | 15% cap | Exploit margin opportunities |
| 🛡️ MAP/Brand Protect | 0.5% | 20% floor | 10% cap | Maintain manufacturer pricing |

#### Pricing Formula
```
RECOMMENDED_PRICE = GREATEST(
    margin_floor,           -- unit_cost × (1 + min_margin%)
    max_discount_floor,     -- current_price × (1 - max_discount%)
    undercut_target          -- competitor_price × (1 - undercut%)
)
```

#### Demand Elasticity Modeling
- Elasticity coefficient: **-1.65** (1% price drop → 1.65% demand increase)
- Base volume: 30 units/month
- Calculates: demand uplift + 30-day profit projection per product

#### Market Intelligence
- **Competitiveness Index**: -100 (always losing on price) to +100 (always winning)
- **Anomaly Detection**: Critical undercuts (>25% cheaper) and margin opportunities (>20% cheaper than market)

---

### Step 4: Semantic Views
**File:** `04_semantic_views.sql`

Three semantic views bridge natural language and SQL for Cortex Agents:

| Semantic View | Agent | Key Contents |
|---------------|-------|-------------|
| `SV_PRODUCT_MATCHING` | Product Matching | Match confidence, strategies, LLM status, price gaps |
| `SV_PRICING_INTELLIGENCE` | Price Optimization | Prices, margins, profit impact, demand uplift |
| `SV_MARKET_INTELLIGENCE` | Market Intelligence | Brand competitiveness, anomalies, market alerts |

Each includes:
- **Dimensions** with synonyms (e.g., "brand", "manufacturer", "product brand" → same column)
- **Facts** with descriptive comments
- **Metrics** with aggregation functions
- **AI_SQL_GENERATION** instructions for Cortex Analyst
- **Verified Query Representations (VQRs)** — gold-standard SQL examples

---

### Step 5: Cortex Agents
**File:** `05_cortex_agents.sql`

Three agents created with `CREATE AGENT ... FROM SPECIFICATION`:

| Agent | Avatar | Tools | Semantic View |
|-------|--------|-------|---------------|
| 🔬 **Product Matching Agent** | Blue | Cortex Analyst + Cortex Search + Data to Chart | `SV_PRODUCT_MATCHING` |
| 💰 **Price Optimization Agent** | Green | Cortex Analyst + Data to Chart | `SV_PRICING_INTELLIGENCE` |
| 🌐 **Market Intelligence Agent** | Purple | Cortex Analyst + Data to Chart | `SV_MARKET_INTELLIGENCE` |

Each agent has:
- YAML-based tool specification
- Response and orchestration instructions
- Sample questions for user onboarding
- Budget constraints (60s, 32K tokens)
- Profile (display name, avatar, color) for Snowflake Intelligence UI

**Tested and verified**: Agents generate SQL via semantic views, execute via Cortex Analyst, and return natural language answers.

---

### Step 6: Evaluation & Benchmarking
**File:** `06_evaluation.sql`

Rigorous ground truth evaluation:

| View | Purpose |
|------|---------|
| `V_BENCHMARK_EVALUATION` | FULL OUTER JOIN — classifies as TP, FP, or FN |
| `V_BENCHMARK_METRICS` | **Precision: 94.33%, Recall: 72.84%, F1: 82.20%** |
| `V_ERROR_FALSE_POSITIVES` | Highest-confidence wrong matches |
| `V_ERROR_FALSE_NEGATIVES` | Missed matches we should have found |
| `V_ACCURACY_BY_STRATEGY` | Precision breakdown by match strategy |
| `V_ACCURACY_BY_BRAND` | Precision & recall per brand |
| `EVALUATION_HISTORY` | Historical snapshots for tracking improvement |

**LLM Error Analysis**: `ANALYZE_ERRORS_WITH_LLM()` uses `llama3.1-70b` to explain why specific false positives/negatives occurred.

---

### Step 7: Pipeline Execution
**File:** `07_execute_pipeline.sql`

End-to-end execution script (run after files 01–06 create all objects):

1. ✅ Verify Dynamic Tables populated
2. ✅ Generate Cortex Embeddings (truncate + re-insert)
3. ✅ Entity Resolution at threshold **0.45**
4. ✅ LLM Verification: auto-confirm ≥0.80, LLM-verify 0.50–0.80, delete rejected
5. ✅ Generate Pricing Recommendations for all 4 strategies
6. ✅ Record evaluation snapshot
7. ✅ Final verification — all object row counts

---

### Step 8: Data Quality Monitoring
**File:** `08_dmf_and_alerts.sql`

#### Custom Data Metric Functions (DMFs)

| DMF | Monitors | Attached To |
|-----|----------|-------------|
| `DMF_FALSE_POSITIVE_COUNT` | Precision drift | `FINAL_PRODUCT_MATCHES (ABT_ID, BUY_ID)` |
| `DMF_MISSING_EMBEDDINGS` | Embedding freshness | `ABT_EMBEDDINGS (PRODUCT_ID)` |
| `DMF_LOW_CONFIDENCE_MATCH_COUNT` | Match quality degradation | `FINAL_PRODUCT_MATCHES (COMPOSITE_SCORE)` |

Plus system DMFs: `NULL_COUNT` on product names, `DUPLICATE_COUNT` on match IDs.

**Schedule**: Every 12 hours (`CRON 0 0,12 * * * UTC`).

#### Snowflake Alerts

| Alert | Schedule | Condition | Action |
|-------|----------|-----------|--------|
| `ALERT_CRITICAL_ANOMALIES` | 60 min | HIGH-severity anomalies > 10 | Log to ALERT_AUDIT_LOG |
| `ALERT_PRECISION_DEGRADATION` | 360 min | Precision < 90% | Log to ALERT_AUDIT_LOG |

---

## 📱 Streamlit Dashboard

A 7-tab production dashboard that queries Snowflake directly — it's a **presentation layer**, not a compute layer.

### Two Versions

| Version | File | Connection | Charts | Deployment |
|---------|------|-----------|--------|------------|
| **Local** | `app.py` | `get_active_session()` | Plotly | Snowpark / Local |
| **Workspace** | `omnimatch-ai-v2/streamlit_app.py` | `st.connection("snowflake")` | Altair | Snowflake Workspace (SPCS) |

### Dashboard Tabs

| Tab | Content |
|-----|---------|
| 📊 **Executive Overview** | Competitive win/loss pie chart, match strategy breakdown, brand price comparison |
| 🔬 **Entity Resolution Studio** | Filterable match table (brand, strategy, LLM status), confidence histogram |
| 🎯 **Benchmark & Accuracy** | Precision/Recall/F1 KPIs, accuracy by strategy bar chart, accuracy by brand scatter, confusion matrix |
| 💰 **Dynamic Pricing Engine** | Pricing recommendations table, profit impact by brand, margin metrics |
| 🌐 **Market Intelligence** | Brand competitiveness ranking (color-coded -100 to +100), anomaly alerts |
| 🤖 **Cortex Agent Chat** | **Real agent chat** via `SNOWFLAKE.CORTEX.DATA_AGENT_RUN()` — select from 3 agents, full conversation history |
| ⚡ **Architecture** | System architecture diagram, Snowflake features checklist, database structure |

---

## 🚀 Setup & Installation

### Prerequisites

- Snowflake account with **Cortex AI** enabled
- `ACCOUNTADMIN` role (or equivalent privileges)
- Cortex models available: `snowflake-arctic-embed-m`, `llama3.1-70b`
- Source data in `RETAIL_INTELLIGENCE_DB.CORE` (v1 database)

### Step-by-Step Setup

#### 1. Create All Objects (run SQL files in order)

```sql
-- Connect to Snowflake and run each file sequentially
-- File 01: Foundation (database, schemas, tables, UDFs, tasks)
-- File 02: AI Pipeline (search, matching, LLM verification)
-- File 03: Pricing & Market Intelligence
-- File 04: Semantic Views (3 views for 3 agents)
-- File 05: Cortex Agents (3 agents)
-- File 06: Evaluation & Benchmarking
```

#### 2. Execute the Pipeline

```sql
-- Run the full pipeline end-to-end
-- This generates embeddings, matches products, verifies with LLM,
-- generates pricing recommendations, and records evaluation
@07_execute_pipeline.sql
```

#### 3. Enable Data Quality Monitoring

```sql
-- Set up DMFs and alerts
@08_dmf_and_alerts.sql
```

#### 4. Deploy Streamlit Dashboard

**Option A: Snowflake Workspace (Recommended)**
```bash
# Navigate to the omnimatch-ai-v2/ directory in Snowflake Workspace
# The app will deploy automatically using snowflake.yml
```

**Option B: Local Development**
```bash
# Create conda environment
conda env create -f environment.yml
conda activate sf_env

# Run Streamlit locally (requires Snowpark session)
streamlit run app.py
```

### Verification

```sql
-- Check all objects are populated
SELECT 'RAW_ABT' AS OBJECT, COUNT(*) AS ROWS FROM CORE.RAW_ABT_CATALOG          -- 1,070
UNION ALL SELECT 'RAW_BUY', COUNT(*) FROM CORE.RAW_BUY_CATALOG                  -- 1,092
UNION ALL SELECT 'GROUND_TRUTH', COUNT(*) FROM CORE.GROUND_TRUTH_MAPPING         -- 1,097
UNION ALL SELECT 'ABT_EMBEDDINGS', COUNT(*) FROM CORTEX_AI.ABT_EMBEDDINGS        -- 1,070
UNION ALL SELECT 'BUY_EMBEDDINGS', COUNT(*) FROM CORTEX_AI.BUY_EMBEDDINGS        -- 1,092
UNION ALL SELECT 'FINAL_MATCHES', COUNT(*) FROM CORTEX_AI.FINAL_PRODUCT_MATCHES  -- ~887
UNION ALL SELECT 'PRICING_RECS', COUNT(*) FROM ANALYTICS.PRICING_RECOMMENDATIONS; -- ~2,524

-- Check benchmark metrics
SELECT * FROM ANALYTICS.V_BENCHMARK_METRICS;
-- Expected: Precision ~94.3%, Recall ~72.8%, F1 ~82.2%
```

---

## 🗄️ Database Schema

```
RETAIL_INTELLIGENCE_V2_DB
├── CORE (Raw + Cleaned Data)
│   ├── RAW_ABT_CATALOG ──────────── 1,070 Abt Electronics products
│   ├── RAW_BUY_CATALOG ──────────── 1,092 Buy.com products
│   ├── GROUND_TRUTH_MAPPING ─────── 1,097 expert-validated match pairs
│   ├── DT_CLEAN_ABT_CATALOG ─────── Dynamic Table (auto-refresh, 1hr lag)
│   ├── DT_CLEAN_BUY_CATALOG ─────── Dynamic Table (auto-refresh, 1hr lag)
│   ├── STREAM_ABT_CHANGES ──────── CDC stream (append-only)
│   └── STREAM_BUY_CHANGES ──────── CDC stream (append-only)
│
├── CORTEX_AI (AI Pipeline)
│   ├── UDF_TOKEN_OVERLAP_SCORE ──── JavaScript UDF (Jaccard similarity)
│   ├── UDF_MODEL_SIMILARITY ─────── JavaScript UDF (Levenshtein + containment)
│   ├── ABT_EMBEDDINGS ──────────── 768-dim Arctic vectors (1,070 products)
│   ├── BUY_EMBEDDINGS ──────────── 768-dim Arctic vectors (1,092 products)
│   ├── V_CANDIDATE_MATCHES ─────── Scoring view (4-strategy hybrid)
│   ├── FINAL_PRODUCT_MATCHES ───── ~887 resolved matches + LLM reasoning
│   ├── PRODUCT_SEARCH_SERVICE ──── Cortex Search (hybrid vector+keyword)
│   ├── SV_PRODUCT_MATCHING ─────── Semantic View (for Product Agent)
│   ├── PRODUCT_MATCHING_AGENT ──── Cortex Agent 🔬
│   ├── PRICE_OPTIMIZATION_AGENT ── Cortex Agent 💰
│   ├── MARKET_INTELLIGENCE_AGENT ─ Cortex Agent 🌐
│   ├── DMF_FALSE_POSITIVE_COUNT ── Data Metric Function
│   ├── DMF_MISSING_EMBEDDINGS ──── Data Metric Function
│   ├── DMF_LOW_CONFIDENCE_COUNT ── Data Metric Function
│   ├── TOOL_SEARCH_MATCHES ─────── Agent tool procedure
│   ├── TOOL_GET_PRICING_REC ─────── Agent tool procedure
│   ├── TOOL_MARKET_INTELLIGENCE ── Agent tool procedure
│   └── Tasks: REFRESH → RESOLVE → LLM_VERIFY (chained)
│
└── ANALYTICS (Business Intelligence)
    ├── PRICING_STRATEGY_CONFIG ──── 4 pricing strategies
    ├── PRICING_RECOMMENDATIONS ──── ~631 per strategy (~2,524 total)
    ├── V_COMPETITIVE_PRICE_INDEX ── Competitive pricing analysis
    ├── V_MARKET_INTELLIGENCE ────── Brand-level competitiveness (-100 to +100)
    ├── V_MARKET_ANOMALIES ──────── Critical undercuts + margin opportunities
    ├── V_BENCHMARK_EVALUATION ───── TP/FP/FN classification
    ├── V_BENCHMARK_METRICS ──────── P=94.3% | R=72.8% | F1=82.2%
    ├── V_ERROR_FALSE_POSITIVES ──── Error analysis (highest confidence FPs)
    ├── V_ERROR_FALSE_NEGATIVES ──── Error analysis (missed matches)
    ├── V_ACCURACY_BY_STRATEGY ───── Precision per match strategy
    ├── V_ACCURACY_BY_BRAND ─────── Precision & recall per brand
    ├── EVALUATION_HISTORY ──────── Historical accuracy snapshots
    ├── SV_PRICING_INTELLIGENCE ──── Semantic View (for Pricing Agent)
    ├── SV_MARKET_INTELLIGENCE ───── Semantic View (for Market Agent)
    ├── ALERT_CRITICAL_ANOMALIES ─── Snowflake Alert (60 min)
    ├── ALERT_PRECISION_DEGRADATION  Snowflake Alert (360 min)
    └── ALERT_AUDIT_LOG ──────────── Alert trigger history
```

---

## 📊 Dataset

**Source:** [Abt-Buy Benchmark Dataset](https://dbs.uni-leipzig.de/research/projects/object-matching/benchmark-datasets-for-entity-resolution) — University of Leipzig

| Table | Records | Description |
|-------|---------|-------------|
| Abt Electronics | 1,070 | Consumer electronics products (cameras, TVs, speakers, GPS, etc.) |
| Buy.com | 1,092 | Same product categories, different names and descriptions |
| Ground Truth | 1,097 | Expert-validated true product matches |

This is a standard benchmark for entity resolution research, enabling rigorous precision/recall/F1 evaluation.

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| **Data Platform** | Snowflake |
| **AI / ML** | Snowflake Cortex AI (Embeddings, LLM, Search, Agents, Analyst) |
| **Embedding Model** | `snowflake-arctic-embed-m` (768 dimensions) |
| **LLM** | `llama3.1-70b` (via CORTEX.COMPLETE) |
| **Dashboard** | Streamlit in Snowflake |
| **Visualization** | Altair (Workspace) / Plotly (Local) |
| **Pipeline** | Dynamic Tables + Streams + Tasks (fully incremental) |
| **Data Quality** | Data Metric Functions + Snowflake Alerts |
| **Language** | SQL + JavaScript (UDFs) + Python (Streamlit) |

---

## 👥 Team

**Team MatchMatrix** — Snowflake × Capgemini Hackathon 2026

---

## 📄 License

This project was built for the **Snowflake × Capgemini Hackathon 2026**.

---

<p align="center">
  <strong>⚡ Built with ❄️ Snowflake Cortex AI</strong><br/>
  <em>Real AI. Real Agents. Real Results.</em>
</p>

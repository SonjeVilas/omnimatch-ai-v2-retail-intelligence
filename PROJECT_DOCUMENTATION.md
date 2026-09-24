# OmniMatch AI v2: Retail Intelligence Platform

## Snowflake x Capgemini Hackathon 2026 | Team MatchMatrix

---

## Project Overview

An AI-powered entity resolution pipeline that automatically matches products across competing retailers (Abt Electronics and Buy.com), enabling dynamic competitive pricing strategies and comprehensive market intelligence — built entirely on native Snowflake features.

**Database:** `RETAIL_INTELLIGENCE_V2_DB`
**Dataset:** Abt-Buy benchmark (University of Leipzig) — 1,070 + 1,092 products, 1,097 ground truth pairs

---

## Step-by-Step Implementation

### Step 1: Foundation — Database, Schemas, Dynamic Tables, Streams, Tasks, UDFs
**File:** `01_foundation.sql`

| Object | Name | Significance |
|--------|------|-------------|
| Database | `RETAIL_INTELLIGENCE_V2_DB` | Clean redesigned database, independent from v1 |
| Schemas | `CORE`, `CORTEX_AI`, `ANALYTICS` | Separation of concerns: raw data, AI pipeline, business analytics |
| Warehouse | `RETAIL_AI_V2_WH` (MEDIUM) | Dedicated compute for the pipeline |
| Raw Tables | `RAW_ABT_CATALOG` (1,070), `RAW_BUY_CATALOG` (1,092), `GROUND_TRUTH_MAPPING` (1,097) | Source data copied from v1 for independence |
| Dynamic Table | `DT_CLEAN_ABT_CATALOG` | **Auto-refreshing** cleaned Abt catalog — brand extraction (25 brands via CASE), model number parsing (regex), price normalization, embedding payload generation. Refreshes automatically when raw data changes. |
| Dynamic Table | `DT_CLEAN_BUY_CATALOG` | Same as above for Buy.com, also extracts manufacturer field |
| Stream | `STREAM_ABT_CHANGES` | CDC (Change Data Capture) on Abt raw table — detects new product inserts |
| Stream | `STREAM_BUY_CHANGES` | CDC on Buy.com raw table |
| JavaScript UDF | `UDF_TOKEN_OVERLAP_SCORE` | Jaccard token overlap similarity between two product text strings (tokenize, intersect, divide by union) |
| JavaScript UDF | `UDF_MODEL_SIMILARITY` | Levenshtein distance-based model/SKU number similarity with substring containment boost (returns 0.92 for containment, 1.0 for exact match) |
| Embedding Tables | `ABT_EMBEDDINGS`, `BUY_EMBEDDINGS` | Store 768-dimension Cortex Arctic vectors per product |
| Stored Procedure | `GENERATE_EMBEDDINGS()` | MERGE-based embedding generation — only embeds new products, skips existing |
| Task | `TASK_REFRESH_EMBEDDINGS` | Scheduled every 60 minutes, triggered by streams — auto-generates embeddings for new products |

**Why it matters:** Dynamic Tables replace static views — they auto-refresh when upstream data changes. Streams + Tasks create an **incremental pipeline** that handles new products without manual reruns. This is a production-ready architecture, not a one-shot batch script.

---

### Step 2: Cortex AI Pipeline — Search Service, Embeddings, Entity Resolution, LLM Verification
**File:** `02_cortex_ai_pipeline.sql`

| Object | Name | Significance |
|--------|------|-------------|
| Cortex Search Service | `PRODUCT_SEARCH_SERVICE` | **Hybrid vector + keyword search** across both catalogs (2,162 products). Supports attribute filtering by brand, price, source catalog, model number. Auto-indexes and refreshes every hour. |
| View | `V_CANDIDATE_MATCHES` | Cross-join with blocking conditions (vector >= 0.50 OR same brand OR same model) to reduce comparison space. Computes 4-strategy hybrid score per pair. |
| Table | `FINAL_PRODUCT_MATCHES` (847 rows) | Final resolved matches with per-match LLM reasoning |
| Stored Procedure | `EXECUTE_ENTITY_RESOLUTION(threshold)` | Full pipeline: scores all candidate pairs, selects top-1 match per Abt product via ROW_NUMBER, classifies strategy, applies threshold |
| Stored Procedure | `VERIFY_MATCHES_WITH_LLM(batch_size)` | Uses `CORTEX.COMPLETE('llama3.1-70b')` to verify ambiguous matches (confidence 0.50-0.80). Auto-confirms high-confidence matches (>0.80). Parses JSON response for verdict + reasoning. |
| Task | `TASK_RESOLVE_MATCHES` | Chained after embedding refresh — re-runs entity resolution |
| Task | `TASK_LLM_VERIFY` | Chained after resolution — LLM-verifies uncertain matches |
| Stored Procedure | `TOOL_SEARCH_MATCHES` | Custom tool for Cortex Agent — searches matched products |
| Stored Procedure | `TOOL_GET_PRICING_RECOMMENDATION` | Custom tool for Cortex Agent — generates pricing rec for a product |
| Stored Procedure | `TOOL_MARKET_INTELLIGENCE` | Custom tool for Cortex Agent — brand-level market summary |

**4-Strategy Hybrid Scoring:**

| Signal | Weight | Method |
|--------|--------|--------|
| Vector Cosine Similarity | 40% | `VECTOR_COSINE_SIMILARITY` on Cortex Arctic 768-dim embeddings |
| Model Number Match | 25% | Levenshtein distance on extracted SKUs (JavaScript UDF) |
| Token Jaccard Overlap | 25% | Jaccard similarity on tokenized product names (JavaScript UDF) |
| Brand Alignment | 10% | Binary — 1.0 if same known brand, 0.0 otherwise |

**Special rules:**
- Model exact match boost: if model score >= 0.90, composite = 0.95 + (0.05 * vector)
- Brand contradiction penalty: if both products have known but different brands, score * 0.30

**LLM Verification:**
- 701 matches auto-confirmed (score >= 0.80)
- 50 matches LLM-verified via `llama3.1-70b` with structured JSON output
- 96 matches still PENDING (can be verified by running the procedure again)

**Why it matters:** This is **real** Cortex AI — not simulated. The Search Service provides native hybrid search. The LLM verification generates actual per-match explanations, not hardcoded strings. The task chain makes it incremental.

---

### Step 3: Dynamic Pricing Engine + Market Intelligence
**File:** `03_pricing_and_market_intel.sql`

| Object | Name | Significance |
|--------|------|-------------|
| Table | `PRICING_STRATEGY_CONFIG` | 4 configurable pricing strategies with guardrails |
| View | `V_COMPETITIVE_PRICE_INDEX` | Classifies each match as ABT_WINNING / BUY_WINNING / PRICE_PARITY with unit cost estimation |
| Table | `PRICING_RECOMMENDATIONS` (631 rows) | AI-generated pricing recommendations with margin guardrails and elasticity modeling |
| Stored Procedure | `GENERATE_PRICING_RECOMMENDATIONS(strategy_id)` | Computes recommended price using GREATEST of: margin floor, max discount floor, and undercut target. Calculates demand uplift (elasticity = -1.65) and 30-day profit projection. |
| View | `V_MARKET_INTELLIGENCE` | Brand-level competitive summary — match count, average prices, price gaps, competitiveness index (-100 to +100), LLM-confirmed count |
| View | `V_MARKET_ANOMALIES` | Critical undercuts (>25% cheaper) and margin opportunities (>20% cheaper than market) |

**4 Pricing Strategies:**

| Strategy | Undercut | Min Margin | Use Case |
|----------|----------|------------|----------|
| Aggressive Undercut | 2.5% | 10% floor | Win on price |
| Price Matcher | 0% | 12% floor | Match competition |
| Margin Maximizer | 1% | 18% floor | Exploit when competitor is pricier |
| MAP/Brand Protect | 0.5% | 20% floor | Maintain manufacturer pricing |

**Why it matters:** This is a complete pricing engine with elasticity-based demand modeling, not just price comparisons. The guardrails (margin floors, max discount limits) make it production-safe. The competitiveness index gives executives a single number per brand.

---

### Step 4: Semantic Views — 3 Views for 3 Cortex Agents
**File:** `04_semantic_views.sql`

| Object | Name | Powers Agent | Significance |
|--------|------|-------------|-------------|
| Semantic View | `SV_PRODUCT_MATCHING` | Product Matching Agent | Defines dimensions (brand, strategy, verification status), facts (scores, price gaps), metrics (match count, avg confidence), and 2 verified queries |
| Semantic View | `SV_PRICING_INTELLIGENCE` | Price Optimization Agent | Defines pricing dimensions (product, brand, competitive status, action type), facts (prices, margins, profit impact), metrics (total profit opportunity, avg margin) |
| Semantic View | `SV_MARKET_INTELLIGENCE` | Market Intelligence Agent | Defines market dimensions (brand, anomaly type/severity), facts (SKU counts, prices, competitiveness index), metrics (total brands, avg competitiveness) |

Each semantic view includes:
- **Dimensions** with synonyms (e.g., "brand", "manufacturer", "product brand" all map to the same column)
- **Facts** with descriptive comments for Cortex Analyst
- **Metrics** with aggregation functions
- **Verified Query Representations (VQRs)** — gold-standard SQL that Cortex Analyst can use as examples

**Why it matters:** Semantic Views are the bridge between natural language and SQL. They tell Cortex Analyst what the data means, how to join it, and how to aggregate it. Without them, the agents can't generate accurate SQL. The VQRs improve answer accuracy on common questions.

---

### Step 5: Cortex Agents — 3 Specialized Agents
**File:** `05_cortex_agents.sql`

| Agent | Tools | Semantic View | Purpose |
|-------|-------|---------------|---------|
| `PRODUCT_MATCHING_AGENT` | Cortex Analyst (MatchAnalyst) + Cortex Search (ProductSearch) + Data to Chart | `SV_PRODUCT_MATCHING` | Entity resolution expert — searches products, analyzes match quality, explains matches |
| `PRICE_OPTIMIZATION_AGENT` | Cortex Analyst (PricingAnalyst) + Data to Chart | `SV_PRICING_INTELLIGENCE` | Dynamic pricing strategist — recommends prices, projects profit impact |
| `MARKET_INTELLIGENCE_AGENT` | Cortex Analyst (MarketAnalyst) + Data to Chart | `SV_MARKET_INTELLIGENCE` | Market analyst — tracks competitiveness, detects anomalies |

Each agent has:
- **`FROM SPECIFICATION`** with YAML-based tool configuration
- **Instructions** for response style and tool orchestration
- **Sample questions** for user onboarding
- **Budget** (60s, 32K tokens) for cost control
- **Profile** with display name, avatar, and color for Snowflake Intelligence UI
- **Warehouse** attached to Analyst tools for SQL execution

**Tested and verified:** The Product Matching Agent was tested via `DATA_AGENT_RUN` and successfully:
1. Loaded the semantic view
2. Generated SQL: `SELECT COUNT(match_id) AS total_matches FROM __matches`
3. Executed via Cortex Analyst
4. Returned natural language answer: "847 total matches"

**Why it matters:** These are **real** Snowflake Cortex Agents created with `CREATE AGENT`, not simulated if/elif chains. They appear in Snowflake Intelligence (AI & ML > Agents), reason autonomously, generate SQL via semantic views, and can search products via Cortex Search. This is the core hackathon requirement.

---

### Step 6: Ground Truth Evaluation + LLM Error Analysis
**File:** `06_evaluation.sql`

| Object | Name | Significance |
|--------|------|-------------|
| View | `V_BENCHMARK_EVALUATION` | FULL OUTER JOIN of AI predictions vs ground truth — classifies each pair as TP, FP, or FN |
| View | `V_BENCHMARK_METRICS` | **Precision: 94.33%, Recall: 72.84%, F1: 82.20%** |
| View | `V_ERROR_FALSE_POSITIVES` | Highest-confidence wrong matches for debugging |
| View | `V_ERROR_FALSE_NEGATIVES` | Missed matches we should have found |
| View | `V_ACCURACY_BY_STRATEGY` | Precision breakdown by match strategy |
| View | `V_ACCURACY_BY_BRAND` | Precision and recall per brand |
| Table | `EVALUATION_HISTORY` | Historical evaluation snapshots for tracking improvement over time |
| Stored Procedure | `RECORD_EVALUATION_SNAPSHOT` | Records current metrics to history table |
| Stored Procedure | `ANALYZE_ERRORS_WITH_LLM` | Uses `CORTEX.COMPLETE('llama3.1-70b')` to explain why specific FPs/FNs occurred |

**Benchmark Results (v2 vs v1):**

| Metric | v1 (Original) | v2 (Redesigned) | Improvement |
|--------|--------------|-----------------|-------------|
| Precision | 87.82% | **94.33%** | +6.51% |
| Recall | 72.29% | **72.84%** | +0.55% |
| F1 Score | 79.30% | **82.20%** | +2.90% |
| False Positives | 110 | **48** | -56% fewer errors |

**Why it matters:** Rigorous evaluation with ground truth benchmarking proves the AI works. The LLM error analysis generates human-readable explanations for mistakes. The evaluation history table enables tracking accuracy improvements across pipeline iterations.

---

### Step 7: Streamlit Dashboard
**File:** `omnimatch-ai-v2/streamlit_app.py` (567 lines)

| Tab | Content |
|-----|---------|
| 📊 Executive Overview | Competitive win/loss pie chart, match strategy breakdown, brand price comparison |
| 🔬 Entity Resolution Studio | Filterable match table (brand, strategy, LLM status), confidence histogram |
| 🎯 Benchmark & Accuracy | Precision/Recall/F1 KPIs, accuracy by strategy bar chart, accuracy by brand scatter, confusion matrix |
| 💰 Dynamic Pricing Engine | Pricing recommendations table, profit impact by brand, margin metrics |
| 🌐 Market Intelligence | Brand competitiveness ranking (color-coded -100 to +100), anomaly alerts |
| 🤖 Cortex Agent Chat | **Real agent chat** via `DATA_AGENT_RUN` — select from 3 agents, full conversation history |
| ⚡ Architecture | System architecture diagram, Snowflake features checklist, database structure |

**Key design decisions:**
- Uses `st.connection("snowflake")` (not `get_active_session()`) — Workspace-compatible
- All data from Snowflake views — no Python matching engine running in the app
- Agent chat uses `SNOWFLAKE.CORTEX.DATA_AGENT_RUN()` for real agent invocation
- `@st.cache_data(ttl=300)` for performance
- Professional CSS with Plus Jakarta Sans font

**Why it matters:** The dashboard queries Snowflake directly — it's a presentation layer, not a compute layer. The agent chat tab calls real Cortex Agents, not keyword-routed templates.

---

## Complete Snowflake Features Used

| # | Feature | Implementation | Significance |
|---|---------|---------------|-------------|
| 1 | **Cortex EMBED_TEXT_768** | `snowflake-arctic-embed-m` on 2,162 products | Semantic vector embeddings for product matching |
| 2 | **VECTOR_COSINE_SIMILARITY** | In candidate match view | Native vector similarity scoring |
| 3 | **CORTEX.COMPLETE** | `llama3.1-70b` for match verification + error analysis | Real LLM reasoning per match, not static strings |
| 4 | **Cortex Search Service** | `PRODUCT_SEARCH_SERVICE` (2,162 products) | Hybrid vector + keyword search with attribute filtering |
| 5 | **Cortex Agents (3x)** | `CREATE AGENT ... FROM SPECIFICATION` | Real autonomous agents with tool orchestration |
| 6 | **Semantic Views (3x)** | Dimensions, facts, metrics, VQRs | Structured data layer for Cortex Analyst |
| 7 | **Cortex Analyst** | `cortex_analyst_text_to_sql` tool | Natural language to SQL generation |
| 8 | **Data to Chart** | `data_to_chart` tool on agents | Agent-generated visualizations |
| 9 | **Dynamic Tables (2x)** | `TARGET_LAG = '1 hour'` | Auto-refreshing cleaned catalogs |
| 10 | **Streams (2x)** | `APPEND_ONLY` on raw tables | CDC for new product detection |
| 11 | **Tasks (3x)** | Stream-triggered + chained | Incremental pipeline: embed → resolve → verify |
| 12 | **JavaScript UDFs (2x)** | Jaccard + Levenshtein | Token overlap and model number similarity |
| 13 | **Stored Procedures (6x)** | SQL-based pipeline orchestration | Embedding gen, entity resolution, pricing, evaluation |
| 14 | **Snowflake Intelligence** | Agents visible in AI & ML > Agents | Natural language analytics in Snowsight |
| 15 | **Streamlit in Snowflake** | 7-tab dashboard, Workspace container runtime | Production dashboard with real agent integration |

---

## Database Structure

```
RETAIL_INTELLIGENCE_V2_DB
├── CORE
│   ├── RAW_ABT_CATALOG (1,070 products)
│   ├── RAW_BUY_CATALOG (1,092 products)
│   ├── GROUND_TRUTH_MAPPING (1,097 validated pairs)
│   ├── DT_CLEAN_ABT_CATALOG (Dynamic Table)
│   ├── DT_CLEAN_BUY_CATALOG (Dynamic Table)
│   ├── STREAM_ABT_CHANGES
│   └── STREAM_BUY_CHANGES
├── CORTEX_AI
│   ├── ABT_EMBEDDINGS (768-dim vectors)
│   ├── BUY_EMBEDDINGS (768-dim vectors)
│   ├── FINAL_PRODUCT_MATCHES (847 matches + LLM reasoning)
│   ├── V_CANDIDATE_MATCHES (scoring view)
│   ├── PRODUCT_SEARCH_SERVICE (Cortex Search)
│   ├── SV_PRODUCT_MATCHING (Semantic View)
│   ├── PRODUCT_MATCHING_AGENT (Cortex Agent)
│   ├── PRICE_OPTIMIZATION_AGENT (Cortex Agent)
│   ├── MARKET_INTELLIGENCE_AGENT (Cortex Agent)
│   └── Tasks: REFRESH_EMBEDDINGS → RESOLVE_MATCHES → LLM_VERIFY
└── ANALYTICS
    ├── PRICING_STRATEGY_CONFIG (4 strategies)
    ├── PRICING_RECOMMENDATIONS (631 recommendations)
    ├── V_COMPETITIVE_PRICE_INDEX
    ├── V_MARKET_INTELLIGENCE
    ├── V_MARKET_ANOMALIES
    ├── V_BENCHMARK_METRICS (P=94.33% R=72.84% F1=82.20%)
    ├── V_ACCURACY_BY_STRATEGY
    ├── V_ACCURACY_BY_BRAND
    ├── EVALUATION_HISTORY
    ├── SV_PRICING_INTELLIGENCE (Semantic View)
    └── SV_MARKET_INTELLIGENCE (Semantic View)
```

---

## Files in Workspace

| File | Lines | Purpose |
|------|-------|---------|
| `01_foundation.sql` | 337 | Database, schemas, Dynamic Tables, Streams, Tasks, UDFs |
| `02_cortex_ai_pipeline.sql` | 384 | Cortex Search, embeddings, entity resolution, LLM verification |
| `03_pricing_and_market_intel.sql` | 303 | Pricing engine, market intelligence views |
| `04_semantic_views.sql` | 306 | 3 Semantic Views with VQRs |
| `05_cortex_agents.sql` | 265 | 3 Cortex Agents with tool specifications |
| `06_evaluation.sql` | 232 | Benchmark evaluation, accuracy views, LLM error analysis |
| `omnimatch-ai-v2/streamlit_app.py` | 567 | 7-tab Streamlit dashboard with real agent chat |
| `omnimatch-ai-v2/snowflake.yml` | 13 | Workspace deployment config |
| `omnimatch-ai-v2/pyproject.toml` | 18 | Python dependencies |
| `omnimatch-ai-v2/.streamlit/config.toml` | 4 | Streamlit theme config |
| **Total** | **2,429** | |

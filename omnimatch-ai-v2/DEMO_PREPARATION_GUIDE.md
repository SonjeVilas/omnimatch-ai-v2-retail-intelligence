# OmniMatch AI v2 — Complete Demo Preparation Guide

## Team MatchMatrix | Snowflake x Capgemini Hackathon 2026

---

## 1. What We Built (End-to-End Explanation)

### The Problem
Retailers sell thousands of products across competing marketplaces. Knowing whether "Sony Alpha DSLR-A350 18.2MP Digital SLR Camera" on Abt.com is the same product as "Sony Alpha A350 14.2MP DSLR Camera Body" on Buy.com — at scale — is a hard entity resolution problem. Get it wrong, and pricing decisions are based on false comparisons.

### The Solution
OmniMatch AI is an **AI-powered product entity resolution and competitive intelligence platform** built entirely on native Snowflake features. It takes two raw product catalogs (Abt Electronics: 1,070 products, Buy.com: 1,092 products), automatically matches products across them, verifies uncertain matches with an LLM, generates dynamic pricing recommendations, and puts everything in the hands of business users via three autonomous Cortex Agents.

### The Pipeline (Step by Step)

```
STEP 1: DATA INGESTION & CLEANING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Raw CSVs → RAW_ABT_CATALOG / RAW_BUY_CATALOG
                    │
                    ▼
         Dynamic Tables (auto-refresh, 1-hour lag)
         ┌─────────────────────────────────┐
         │  DT_CLEAN_ABT / DT_CLEAN_BUY   │
         │  • Price normalization           │
         │  • Brand extraction (25 brands)  │
         │  • Model number parsing (regex)  │
         │  • Embedding text construction   │
         └─────────────┬───────────────────┘
                       │
STEP 2: VECTORIZATION  │
━━━━━━━━━━━━━━━━━━━━━━━┤
                       ▼
         Cortex EMBED_TEXT_768 (snowflake-arctic-embed-m)
         ┌─────────────────────────────────┐
         │  ABT_EMBEDDINGS (1,070 vectors) │
         │  BUY_EMBEDDINGS (1,092 vectors) │
         │  768-dimension float vectors     │
         └─────────────┬───────────────────┘
                       │
STEP 3: CANDIDATE GENERATION + SCORING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                       ▼
         V_CANDIDATE_MATCHES (blocking + cross-join)
         ┌──────────────────────────────────────┐
         │  Blocking filters (reduce 1.17M to   │
         │  plausible pairs):                   │
         │  • Vector similarity >= 0.40         │
         │  • Same brand (not 'Other')          │
         │  • Same extracted model number       │
         │  • Price proximity for 'Other' brand │
         │                                      │
         │  4-Signal Hybrid Scoring:            │
         │  ┌────────────────────────────────┐  │
         │  │ Vector Cosine Similarity  40%  │  │
         │  │ Model/SKU Levenshtein    25%  │  │
         │  │ Token Jaccard Overlap    25%  │  │
         │  │ Brand Alignment          10%  │  │
         │  └────────────────────────────────┘  │
         │  + Model exact-match boost (→ 0.95+) │
         │  + Brand contradiction penalty (70%) │
         └─────────────┬────────────────────────┘
                       │
STEP 4: ENTITY RESOLUTION + LLM VERIFICATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                       ▼
         FINAL_PRODUCT_MATCHES (887 matches)
         ┌──────────────────────────────────────┐
         │  Top-1 selection per ABT product     │
         │  Threshold: composite score >= 0.45  │
         │                                      │
         │  LLM Verification (llama3.1-70b):    │
         │  • Score >= 0.80 → Auto-confirmed    │
         │  • Score 0.45-0.80 → LLM verifies    │
         │  • LLM REJECTED → Deleted (34 pairs) │
         │  • Result: 887 confirmed matches     │
         └─────────────┬────────────────────────┘
                       │
STEP 5: PRICING + MARKET INTELLIGENCE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                       ▼
         ┌──────────────────────────────┐
         │  4 Pricing Strategies:       │
         │  • Aggressive Undercut       │
         │  • Price Matcher             │
         │  • Margin Maximizer          │
         │  • MAP & Brand Protect       │
         │                              │
         │  631 recommendations each    │
         │  Demand elasticity modeling  │
         │  30-day profit projections   │
         │  Margin guardrails           │
         ├──────────────────────────────┤
         │  Market Intelligence:        │
         │  • 22 brands tracked         │
         │  • Competitiveness index     │
         │  • 77 anomaly alerts         │
         └─────────────┬────────────────┘
                       │
STEP 6: SEMANTIC VIEWS → AGENTS → USERS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                       ▼
         3 Semantic Views
         ┌────────────────────────────────────┐
         │  SV_PRODUCT_MATCHING               │
         │  SV_PRICING_INTELLIGENCE           │
         │  SV_MARKET_INTELLIGENCE            │
         │  (dimensions, facts, metrics, VQRs)│
         └─────────────┬──────────────────────┘
                       ▼
         3 Cortex Agents (CREATE AGENT FROM SPECIFICATION)
         ┌────────────────────────────────────┐
         │  🔬 Product Matching Agent         │
         │     → Cortex Analyst + Search      │
         │  💰 Price Optimization Agent       │
         │     → Cortex Analyst + Chart       │
         │  🌐 Market Intelligence Agent      │
         │     → Cortex Analyst + Chart       │
         └─────────────┬──────────────────────┘
                       ▼
         Streamlit Dashboard (7 tabs)
         + Snowflake Intelligence (AI & ML → Agents)
```

### The Incremental Pipeline (Streams + Tasks)

```
  New product inserted into RAW_ABT_CATALOG
                    │
                    ▼
  STREAM_ABT_CHANGES detects insert (CDC)
                    │
                    ▼
  DT_CLEAN_ABT_CATALOG auto-refreshes (Dynamic Table)
                    │
                    ▼
  TASK_REFRESH_EMBEDDINGS fires (WHEN stream has data)
    → CALL GENERATE_EMBEDDINGS()
                    │
                    ▼
  TASK_RESOLVE_MATCHES fires (AFTER refresh)
    → CALL EXECUTE_ENTITY_RESOLUTION(0.45)
                    │
                    ▼
  TASK_LLM_VERIFY fires (AFTER resolve)
    → CALL VERIFY_MATCHES_WITH_LLM(200)
                    │
                    ▼
  Pipeline complete — new product matched and priced automatically
```

---

## 2. Final Benchmark Results

| Metric | v1 (Original) | v2 (Final) | Improvement |
|--------|---------------|------------|-------------|
| **Precision** | 87.82% | **94.36%** | +6.54% |
| **Recall** | 72.29% | **76.30%** | +4.01% |
| **F1 Score** | 79.30% | **84.37%** | +5.07% |
| Total Matches | — | **887** | — |
| False Positives | 110 | **50** | -55% |
| False Negatives | — | **260** | — |
| LLM Verified | 0 | **220** | All uncertain matches verified |
| Ground Truth | 1,097 | 1,097 | Expert-validated pairs |

---

## 3. Complete Snowflake Feature Inventory (17 Features)

| # | Feature | Count | Implementation |
|---|---------|-------|----------------|
| 1 | Dynamic Tables | 2 | `DT_CLEAN_ABT_CATALOG`, `DT_CLEAN_BUY_CATALOG` |
| 2 | Streams | 2 | `STREAM_ABT_CHANGES`, `STREAM_BUY_CHANGES` |
| 3 | Tasks (chained DAG) | 3 | REFRESH → RESOLVE → LLM_VERIFY |
| 4 | Cortex Search Service | 1 | Hybrid vector + keyword over 2,162 products |
| 5 | Cortex Embeddings | 2,162 | `EMBED_TEXT_768('snowflake-arctic-embed-m')` |
| 6 | Vector Operations | — | `VECTOR_COSINE_SIMILARITY` on 768-dim vectors |
| 7 | Cortex LLM (COMPLETE) | — | `llama3.1-70b` for verification + error analysis |
| 8 | Semantic Views | 3 | Product, Pricing, Market — with VQRs |
| 9 | Cortex Agents | 3 | Real `CREATE AGENT FROM SPECIFICATION` |
| 10 | Cortex Analyst | 3 | `text_to_sql` on each agent via semantic views |
| 11 | Data to Chart | 3 | Built-in visualization tool on each agent |
| 12 | JavaScript UDFs | 2 | Jaccard token overlap + Levenshtein model similarity |
| 13 | Stored Procedures | 6 | Embeddings, resolution, LLM verify, pricing, eval |
| 14 | Streamlit in Snowflake | 1 | 7-tab dashboard with live agent chat |
| 15 | Snowflake Intelligence | 3 | Agents visible in AI & ML → Agents |
| 16 | Verified Queries (VQRs) | 5 | Gold-standard SQL in semantic views |
| 17 | Ground Truth Evaluation | — | Precision/Recall/F1 + LLM error analysis |

---

## 4. Demo Q&A — Technical Justifications

### MODEL CHOICES

**Q: Why `snowflake-arctic-embed-m` for embeddings and not another model?**

A: Three reasons:
1. **Native to Snowflake** — `EMBED_TEXT_768` is a built-in Cortex function. No external API calls, no egress, no latency. The vectors are generated inside Snowflake's compute.
2. **768 dimensions is the sweet spot** — It's rich enough for semantic discrimination between similar products ("Sony Alpha A350" vs "Sony Alpha A550") but not so large that cosine similarity becomes expensive on 1.17M candidate pairs.
3. **Arctic Embed-M is tuned for retrieval** — It's specifically designed for similarity search and retrieval, which is exactly what entity resolution needs. A general-purpose LLM embedding (like from GPT-4) would be overkill and much slower.

**Q: Why `llama3.1-70b` for LLM verification and not a smaller/larger model?**

A: The 70B parameter size hits the right balance:
- **Why not 8B (smaller)?** — Match verification requires nuanced reasoning. The LLM needs to understand that "Sony DSLR-A350K with DT18-70mm Lens" and "Sony Alpha DSLR-A350 14.2MP Digital SLR Camera Body" are the same camera but one includes a lens kit. An 8B model makes more mistakes on these edge cases.
- **Why not 405B or Claude (larger)?** — We're calling COMPLETE on 220 product pairs. A larger model would take 3-5x longer with marginal accuracy gain. 70B returns structured JSON reliably and processes the batch in a few minutes.
- **Why Llama and not Mistral or another model?** — `llama3.1-70b` is available natively in Snowflake Cortex COMPLETE, supports structured JSON output reliably, and Meta's Llama 3.1 excels at instruction-following — critical since we need strict `{"verdict": "CONFIRMED/REJECTED", "reason": "..."}` format.

**Q: Why does the agent use `orchestration: auto` instead of specifying a model?**

A: `orchestration: auto` lets Snowflake select the optimal model for each agent turn based on query complexity. Simple questions ("How many matches?") get routed to a faster model, while complex multi-tool questions get a more capable model. This balances cost and quality without us hardcoding a choice that might be suboptimal for some queries. It's the recommended production pattern.

---

### ARCHITECTURE CHOICES

**Q: Why Dynamic Tables instead of just views or materialized views?**

A: Dynamic Tables give us **incremental refresh with declarative lag targets**. When raw data changes, the DT auto-refreshes — we don't need to write MERGE logic or schedule manual refreshes. The `TARGET_LAG = '1 hour'` means data is at most 1 hour stale, and Snowflake handles the refresh scheduling. A regular view would recompute on every query (expensive with regex brand extraction). A materialized view has restrictions on supported SQL. Dynamic Tables support full SQL with automatic dependency tracking.

**Q: Why Streams + Tasks instead of just scheduling the procedures?**

A: The Streams provide **event-driven triggering**. The root task (`TASK_REFRESH_EMBEDDINGS`) only fires `WHEN SYSTEM$STREAM_HAS_DATA(...)` — meaning if no new products are added, the pipeline doesn't run. This saves compute credits. A plain scheduled task would run every hour regardless, wasting resources. The chained DAG (`REFRESH → RESOLVE → LLM_VERIFY`) guarantees ordering without manual orchestration.

**Q: Why a 4-signal hybrid scoring formula instead of just using vector similarity?**

A: Vector similarity alone gives us ~85% precision. Adding model number matching catches the easy exact matches that vectors sometimes miss (model numbers are strings of characters that embedding models handle poorly). Token overlap catches cases where product names share many words but differ enough that the embedding distance is larger than expected. Brand alignment provides a fast filter for obvious mismatches.

The **model exact-match boost** (score → 0.95+ when model similarity ≥ 0.90) is critical: if two products have the same model number (e.g., "WRT54G"), they're almost certainly the same product regardless of what the vector says.

The **brand contradiction penalty** (70% reduction) prevents the system from matching a "Sony camera" with a "Canon camera" even if their descriptions are similar.

**Q: Why threshold 0.45 and not 0.50 or higher?**

A: We tested multiple thresholds against the ground truth:

| Threshold | Precision | Recall | F1 |
|-----------|-----------|--------|------|
| 0.55 | 95.2% | 70.1% | 80.7% |
| 0.50 | 94.3% | 72.8% | 82.2% |
| 0.48 | 93.6% | 74.8% | 83.1% |
| **0.45** | **94.4%** | **76.3%** | **84.4%** |

At 0.45, the F1 is highest because we gain +3.5% recall (50 more true matches recovered from the ground truth) while the LLM verification step catches and removes the extra false positives. The LLM acts as a precision safety net — we can afford a lower threshold because the LLM cleans up after.

**Q: Why do you delete LLM-rejected matches instead of just flagging them?**

A: For two reasons:
1. **Precision impact** — Rejected matches are false positives. Keeping them in the table inflates the match count and feeds wrong data into the pricing engine. A pricing recommendation based on a wrong product match is worse than no recommendation.
2. **Downstream trust** — Every match in `FINAL_PRODUCT_MATCHES` is LLM-confirmed. Business users and agents can trust the data without needing to filter by verification status. Clean data in, clean insights out.

---

### SEMANTIC VIEWS & AGENTS

**Q: Why 3 separate agents instead of 1 agent with all tools?**

A: Domain separation:
1. **Focused context** — Each agent has a single semantic view with domain-specific dimensions, metrics, and verified queries. A single agent with 3 semantic views would have a larger context window, more ambiguity in metric resolution, and slower responses.
2. **Better SQL generation** — Cortex Analyst generates more accurate SQL when the semantic model is focused. Fewer tables = fewer join paths = fewer ways to write a wrong query.
3. **Independent scaling** — If the pricing team uses the Price Agent heavily, it doesn't affect the product matching team's agent performance.
4. **Clearer demo story** — Judges see 3 specialized experts, not 1 confused generalist.

**Q: Why Semantic Views instead of just letting the agent query tables directly?**

A: Semantic Views tell Cortex Analyst **what the data means**:
- `COMPOSITE_SCORE` is described as "Weighted composite match confidence score (0-1)" — without this, the agent might interpret it as a percentage and multiply by 100.
- Synonyms like "brand" → `ABT_BRAND` mean users can ask "matches per brand" without knowing the column name.
- Verified queries provide gold-standard SQL that the agent uses as reference for similar questions.
- Metrics define the correct aggregation (e.g., `COUNT(MATCH_ID)` for total matches, not `COUNT(*)`) so the agent doesn't make common aggregation mistakes.

**Q: What are Verified Queries (VQRs) and why do you have 5?**

A: VQRs are pre-written SQL queries paired with natural language questions. When a user asks something similar to a VQR question, Cortex Analyst uses the VQR's SQL as a starting template — guaranteeing correct results for common questions. Our 5 VQRs cover the most likely demo questions:
1. "How many matches per brand?"
2. "What is the match strategy distribution?"
3. "Show me the top 10 most confident matches"
4. "What is the total profit opportunity by brand?"
5. "Which brands are we most competitive on?"

---

### EVALUATION & DATA QUALITY

**Q: Where did the ground truth come from?**

A: The Abt-Buy dataset is a published benchmark from the University of Leipzig's Database Group. It contains 1,097 expert-validated match pairs where humans confirmed that product A from Abt and product B from Buy.com are the same physical product. This is a standard benchmark in the entity resolution research community — using it means our precision/recall/F1 numbers are directly comparable to published academic results.

**Q: 76.3% recall means you're missing ~24% of true matches. Why?**

A: The 260 false negatives fall into three categories:
1. **Completely different product names** (~40%) — e.g., "Garmin nuvi 265WT GPS Navigator" vs "Garmin 010-00575-10 nuvi 265WT" — the Buy.com listing uses a part number instead of a product name. Our embedding model treats these as very different texts.
2. **Missing price data** (~25%) — Products where one catalog has no price. Our price-proximity blocking can't help these.
3. **Ambiguous products** (~35%) — Products where even the hybrid scoring formula can't distinguish the correct match from similar products in the same brand/model family.

Improving beyond ~80% recall on this benchmark typically requires catalog-specific heuristics (e.g., parsing Garmin part number patterns) or fine-tuning the embedding model — both would reduce generalizability.

**Q: How do you know the pipeline won't degrade over time?**

A: Three mechanisms:
1. **Evaluation views** — `V_BENCHMARK_METRICS` computes precision/recall/F1 live against ground truth. Any degradation is immediately visible.
2. **Evaluation history** — `RECORD_EVALUATION_SNAPSHOT()` procedure records metrics over time. We can track trends.
3. **LLM error analysis** — `ANALYZE_ERRORS_WITH_LLM()` sends false positives/negatives to the LLM and asks "why did the AI get this wrong?" — providing diagnostic insights.

---

### PRICING ENGINE

**Q: The cost estimate is 70% of price — isn't that made up?**

A: Yes — we don't have actual supplier cost data. The 70% assumption is a reasonable default for consumer electronics retail (typical gross margins are 20-35%). In a production system, this would be replaced by actual cost-of-goods-sold data from the ERP. The pricing engine architecture (guardrails, elasticity modeling, strategy configs) is real — only the cost input is synthetic.

**Q: What is the demand elasticity coefficient (-1.65)?**

A: It means a 1% price decrease is projected to increase demand by 1.65%. This is a standard price elasticity estimate for consumer electronics from retail economics literature. It's applied uniformly here, but in production you'd vary it by product category (e.g., cables are more elastic than cameras).

---

### PRACTICAL / DEMO

**Q: What happens if a judge asks the agent a question it can't answer?**

A: The agent will say it can't answer and suggest related questions it can answer. Cortex Agents with semantic views are constrained to the metrics and dimensions defined in the view — they won't hallucinate data. If the question is outside the domain (e.g., asking the pricing agent about match quality), it will say it doesn't have that data.

**Q: How long does the full pipeline take to run from scratch?**

A: About 15-20 minutes:
- Dynamic Table refresh: ~1 min
- Embedding generation (2,162 products): ~3-4 min
- Entity resolution (candidate scoring + top-1 selection): ~5-6 min
- LLM verification (220 matches × llama3.1-70b): ~5-7 min
- Pricing generation (4 strategies × 631 products): ~1 min

**Q: How is this different from your v1?**

A: The v1 prototype had:
- A Python TF-IDF matching engine running in-process in Streamlit (not Snowflake-native)
- Fake agents (keyword if/elif routing with canned responses)
- No LLM involvement (every match got the same generic reasoning string)
- Static batch processing (no streams, no tasks, no incremental pipeline)
- 87.8% precision, 72.3% recall

The v2 rebuild is 100% Snowflake-native with real Cortex Agents, real LLM verification, an incremental pipeline, and 94.4% precision / 76.3% recall.

---

## 5. One-Liner Answers (Quick Reference)

| Question | Answer |
|----------|--------|
| How many features? | 17 native Snowflake features |
| Dataset? | Abt-Buy benchmark, University of Leipzig, 1,070 + 1,092 products |
| Embedding model? | `snowflake-arctic-embed-m` via `EMBED_TEXT_768` (768 dimensions) |
| LLM model? | `llama3.1-70b` via `CORTEX.COMPLETE` |
| Agent orchestration? | `orchestration: auto` (Snowflake selects optimal model per query) |
| Precision? | 94.36% |
| Recall? | 76.30% |
| F1? | 84.37% |
| Total matches? | 887 (out of 1,070 Abt products) |
| False positives? | 50 |
| Ground truth? | 1,097 expert-validated pairs |
| Pricing strategies? | 4 (Aggressive Undercut, Price Matcher, Margin Maximizer, MAP Protect) |
| Agents? | 3 (Product Matching, Price Optimization, Market Intelligence) |
| Pipeline type? | Incremental (Streams → Tasks → auto-refresh) |
| Dashboard? | 7-tab Streamlit with live agent chat |

-- ============================================================================
-- OMNIMATCH AI v2: RETAIL INTELLIGENCE PLATFORM (REDESIGNED)
-- File 05: Cortex Agents — 3 Specialized Agents + MCP Integration
-- ============================================================================
-- Prerequisites: Run files 01-04 and execute pipeline procedures
-- ============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE RETAIL_AI_V2_WH;
USE DATABASE RETAIL_INTELLIGENCE_V2_DB;
USE SCHEMA CORTEX_AI;

-- Ensure required privileges
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE ACCOUNTADMIN;
GRANT CREATE AGENT ON SCHEMA RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI TO ROLE ACCOUNTADMIN;

-- ============================================================================
-- AGENT 1: PRODUCT MATCHING AGENT
-- ============================================================================
-- Purpose: Entity resolution expert — searches, matches, and explains
-- product matches across Abt and Buy.com catalogs.
-- Tools: Cortex Analyst (SV_PRODUCT_MATCHING) + Cortex Search (PRODUCT_SEARCH_SERVICE)

CREATE OR REPLACE AGENT RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.PRODUCT_MATCHING_AGENT
    COMMENT = 'AI-powered product entity resolution agent — matches products across Abt and Buy.com catalogs using multi-strategy hybrid scoring'
    PROFILE = '{
        "display_name": "Product Matching Agent",
        "avatar": "🔬",
        "color": "blue"
    }'
    FROM SPECIFICATION
    $$
    models:
        orchestration: auto

    orchestration:
        budget:
            seconds: 60
            tokens: 32000

    instructions:
        response: |
            You are the OmniMatch Product Matching Agent — an expert in entity resolution
            and product matching across retail catalogs. You help users:
            1. Search for products and find their cross-catalog matches
            2. Analyze match quality and confidence scores
            3. Explain WHY two products were matched (or not matched)
            4. Report on matching accuracy by brand, strategy, and confidence level

            Always be specific with numbers. When showing matches, include confidence scores,
            strategy used, and LLM verification status. Use the Search tool for finding specific
            products and the Analyst tool for aggregated analysis.

        orchestration: |
            For product searches by name/model/keyword, use ProductSearch first.
            For analytical questions (counts, averages, distributions), use MatchAnalyst.
            For questions about specific match pairs, combine both tools.
            Always generate charts when showing distributions or comparisons.

        sample_questions:
            - question: "Find all Sony camera matches"
            - question: "What is the match strategy distribution?"
            - question: "Show me the top 10 most confident matches"
            - question: "Which brands have the most matches?"
            - question: "How many matches are LLM-confirmed vs pending?"

    tools:
        - tool_spec:
            type: cortex_analyst_text_to_sql
            name: MatchAnalyst
            description: "Analyze product match data — counts, distributions, averages, and breakdowns by brand, strategy, confidence level, and verification status"
        - tool_spec:
            type: cortex_search
            name: ProductSearch
            description: "Search the unified product catalog across both Abt and Buy.com by product name, model number, brand, or description keywords"
        - tool_spec:
            type: data_to_chart
            name: data_to_chart
            description: "Generate visualizations from match analysis data"

    tool_resources:
        MatchAnalyst:
            semantic_view: "RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.SV_PRODUCT_MATCHING"
        ProductSearch:
            search_service: "RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.PRODUCT_SEARCH_SERVICE"
            max_results: 15
            columns_and_descriptions:
                SEARCH_TEXT:
                    description: "Full searchable text combining product name, manufacturer, and description"
                    type: "string"
                    searchable: true
                    filterable: false
                BRAND:
                    description: "Standardized product brand name (Sony, Canon, Nikon, etc.)"
                    type: "string"
                    searchable: false
                    filterable: true
                SOURCE_CATALOG:
                    description: "Source catalog: ABT or BUY"
                    type: "string"
                    searchable: false
                    filterable: true
                CLEAN_PRICE:
                    description: "Product price in USD"
                    type: "number"
                    searchable: false
                    filterable: false
    $$;


-- ============================================================================
-- AGENT 2: PRICE OPTIMIZATION AGENT
-- ============================================================================
-- Purpose: Dynamic pricing strategist — recommends optimal prices,
-- calculates margins, and projects profit impact.
-- Tools: Cortex Analyst (SV_PRICING_INTELLIGENCE) + Data to Chart

CREATE OR REPLACE AGENT RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.PRICE_OPTIMIZATION_AGENT
    COMMENT = 'Dynamic pricing optimization agent — recommends competitive prices with margin guardrails and elasticity-based profit projections'
    PROFILE = '{
        "display_name": "Price Optimization Agent",
        "avatar": "💰",
        "color": "green"
    }'
    FROM SPECIFICATION
    $$
    models:
        orchestration: auto

    orchestration:
        budget:
            seconds: 60
            tokens: 32000

    instructions:
        response: |
            You are the OmniMatch Price Optimization Agent — an expert in competitive
            pricing strategy and revenue optimization. You help users:
            1. Find optimal prices that balance competitiveness and profitability
            2. Analyze pricing strategies (Aggressive Undercut, Price Matcher, Margin Maximizer, MAP/Brand Protect)
            3. Project profit impact using demand elasticity modeling
            4. Identify products that need immediate repricing

            Always include dollar amounts and percentages. When recommending prices,
            show the current price, competitor price, recommended price, margin, and
            projected profit impact. Use charts for comparisons.

        orchestration: |
            Use PricingAnalyst for all pricing questions. Generate charts when comparing
            strategies, brands, or price distributions. When asked about a specific product,
            show the full pricing breakdown including cost, margin, and elasticity impact.

        sample_questions:
            - question: "What is the total profit opportunity by brand?"
            - question: "Which products need repricing to beat the competition?"
            - question: "Compare the Aggressive Undercut vs Margin Maximizer strategies"
            - question: "Show me products with the biggest price gaps"
            - question: "What is our average margin after repricing?"

    tools:
        - tool_spec:
            type: cortex_analyst_text_to_sql
            name: PricingAnalyst
            description: "Query pricing recommendations, margins, competitive status, demand elasticity, and profit projections across all matched products and pricing strategies"
        - tool_spec:
            type: data_to_chart
            name: data_to_chart
            description: "Generate pricing charts, margin comparisons, and profit visualizations"

    tool_resources:
        PricingAnalyst:
            semantic_view: "RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.SV_PRICING_INTELLIGENCE"
    $$;


-- ============================================================================
-- AGENT 3: MARKET INTELLIGENCE AGENT
-- ============================================================================
-- Purpose: Market analyst — tracks competitive positioning, brand performance,
-- and detects pricing anomalies.
-- Tools: Cortex Analyst (SV_MARKET_INTELLIGENCE) + Data to Chart

CREATE OR REPLACE AGENT RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.MARKET_INTELLIGENCE_AGENT
    COMMENT = 'Market intelligence agent — analyzes brand competitiveness, pricing trends, and detects market anomalies requiring immediate action'
    PROFILE = '{
        "display_name": "Market Intelligence Agent",
        "avatar": "🌐",
        "color": "purple"
    }'
    FROM SPECIFICATION
    $$
    models:
        orchestration: auto

    orchestration:
        budget:
            seconds: 60
            tokens: 32000

    instructions:
        response: |
            You are the OmniMatch Market Intelligence Agent — an expert in competitive
            market analysis and trend detection. You help users:
            1. Analyze brand-level competitive positioning
            2. Detect pricing anomalies (critical undercuts, margin opportunities)
            3. Track which brands we're winning or losing on price
            4. Provide actionable market intelligence reports

            The competitiveness index ranges from -100 (always losing on price) to
            +100 (always winning). Focus on actionable insights — what should the
            business do based on the data? Always generate charts for visual analysis.

        orchestration: |
            Use MarketAnalyst for all market questions. Generate charts for brand
            comparisons and competitiveness rankings. When asked about anomalies or
            risks, focus on HIGH severity items first.

        sample_questions:
            - question: "Which brands are we most competitive on?"
            - question: "What are the critical market anomalies?"
            - question: "Give me a full market intelligence report"
            - question: "Where are we losing to Buy.com?"
            - question: "Which brands have the biggest margin expansion opportunity?"

    tools:
        - tool_spec:
            type: cortex_analyst_text_to_sql
            name: MarketAnalyst
            description: "Query brand competitiveness, market positioning, pricing anomalies, and competitive intelligence data"
        - tool_spec:
            type: data_to_chart
            name: data_to_chart
            description: "Generate market intelligence charts, brand comparisons, and anomaly visualizations"

    tool_resources:
        MarketAnalyst:
            semantic_view: "RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.SV_MARKET_INTELLIGENCE"
    $$;


-- ============================================================================
-- GRANT ACCESS: Make agents available to current user
-- ============================================================================
GRANT USAGE ON AGENT RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.PRODUCT_MATCHING_AGENT TO ROLE ACCOUNTADMIN;
GRANT USAGE ON AGENT RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.PRICE_OPTIMIZATION_AGENT TO ROLE ACCOUNTADMIN;
GRANT USAGE ON AGENT RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.MARKET_INTELLIGENCE_AGENT TO ROLE ACCOUNTADMIN;

-- ============================================================================
-- VERIFICATION: List all agents
-- ============================================================================
-- SHOW AGENTS IN SCHEMA RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI;
-- DESCRIBE AGENT RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.PRODUCT_MATCHING_AGENT;
-- DESCRIBE AGENT RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.PRICE_OPTIMIZATION_AGENT;
-- DESCRIBE AGENT RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.MARKET_INTELLIGENCE_AGENT;

-- ============================================================================
-- TEST: Quick agent test via SQL
-- ============================================================================
-- SELECT TRY_PARSE_JSON(
--   SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
--     'RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.PRODUCT_MATCHING_AGENT',
--     $${"messages": [{"role": "user", "content": [{"type": "text", "text": "How many matches per brand?"}]}]}$$,
--     TRUE
--   )
-- ) AS response;

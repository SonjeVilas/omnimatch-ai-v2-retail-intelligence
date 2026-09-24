-- ============================================================================
-- OMNIMATCH AI v2: RETAIL INTELLIGENCE PLATFORM (REDESIGNED)
-- File 02: Cortex AI Pipeline — Search Service, Entity Resolution, LLM Verification
-- ============================================================================
-- Prerequisites: Run 01_foundation.sql first, then CALL GENERATE_EMBEDDINGS()
-- ============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE RETAIL_AI_V2_WH;
USE DATABASE RETAIL_INTELLIGENCE_V2_DB;

-- ============================================================================
-- 1. CORTEX SEARCH SERVICE: Unified product catalog search
-- ============================================================================
USE SCHEMA CORTEX_AI;

CREATE OR REPLACE CORTEX SEARCH SERVICE PRODUCT_SEARCH_SERVICE
    ON SEARCH_TEXT
    ATTRIBUTES BRAND, CLEAN_PRICE, SOURCE_CATALOG, EXTRACTED_MODEL
    WAREHOUSE = RETAIL_AI_V2_WH
    TARGET_LAG = '1 hour'
    COMMENT = 'Hybrid vector + keyword search across Abt and Buy.com product catalogs'
AS (
    SELECT
        ID AS PRODUCT_ID,
        SEARCH_TEXT,
        NAME AS PRODUCT_NAME,
        BRAND,
        CLEAN_PRICE,
        EXTRACTED_MODEL,
        SOURCE_CATALOG
    FROM RETAIL_INTELLIGENCE_V2_DB.CORE.DT_CLEAN_ABT_CATALOG
    UNION ALL
    SELECT
        ID AS PRODUCT_ID,
        SEARCH_TEXT,
        NAME AS PRODUCT_NAME,
        BRAND,
        CLEAN_PRICE,
        EXTRACTED_MODEL,
        SOURCE_CATALOG
    FROM RETAIL_INTELLIGENCE_V2_DB.CORE.DT_CLEAN_BUY_CATALOG
);

-- ============================================================================
-- 2. CANDIDATE MATCH VIEW: Vector similarity + blocking
-- ============================================================================
-- This view generates candidate pairs using Cortex vector similarity
-- with brand/model blocking to reduce comparison space.

CREATE OR REPLACE VIEW V_CANDIDATE_MATCHES
    COMMENT = 'Candidate product match pairs with multi-strategy scoring'
AS
WITH scored_pairs AS (
    SELECT
        a.PRODUCT_ID                                    AS ABT_ID,
        b.PRODUCT_ID                                    AS BUY_ID,
        a.PRODUCT_NAME                                  AS ABT_NAME,
        b.PRODUCT_NAME                                  AS BUY_NAME,
        a.BRAND                                         AS ABT_BRAND,
        b.BRAND                                         AS BUY_BRAND,
        a.CLEAN_PRICE                                   AS ABT_PRICE,
        b.CLEAN_PRICE                                   AS BUY_PRICE,
        a.EXTRACTED_MODEL                               AS ABT_MODEL,
        b.EXTRACTED_MODEL                               AS BUY_MODEL,

        -- Strategy 1: Vector Cosine Similarity (Cortex Arctic Embeddings)
        VECTOR_COSINE_SIMILARITY(a.EMBEDDING, b.EMBEDDING) AS VECTOR_SCORE,

        -- Strategy 2: Token Jaccard Overlap
        RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.UDF_TOKEN_OVERLAP_SCORE(a.PRODUCT_NAME, b.PRODUCT_NAME) AS TOKEN_SCORE,

        -- Strategy 3: Model/SKU Number Similarity
        RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.UDF_MODEL_SIMILARITY(
            COALESCE(a.EXTRACTED_MODEL, ''),
            COALESCE(b.EXTRACTED_MODEL, '')
        ) AS MODEL_SCORE,

        -- Strategy 4: Brand Alignment (binary)
        CASE
            WHEN a.BRAND = b.BRAND AND a.BRAND != 'Other' THEN 1.0
            ELSE 0.0
        END AS BRAND_SCORE

    FROM RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.ABT_EMBEDDINGS a
    CROSS JOIN RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.BUY_EMBEDDINGS b
    WHERE
        -- Blocking conditions: only compare plausible pairs
        (
            VECTOR_COSINE_SIMILARITY(a.EMBEDDING, b.EMBEDDING) >= 0.40
            OR (a.BRAND = b.BRAND AND a.BRAND != 'Other')
            OR (a.EXTRACTED_MODEL IS NOT NULL AND b.EXTRACTED_MODEL IS NOT NULL
                AND a.EXTRACTED_MODEL = b.EXTRACTED_MODEL)
            -- Secondary pass: price-proximity blocking for 'Other' brand pairs
            -- catches missed matches where brand extraction failed but products are similar
            OR (a.BRAND = 'Other' AND b.BRAND = 'Other'
                AND a.CLEAN_PRICE IS NOT NULL AND b.CLEAN_PRICE IS NOT NULL
                AND ABS(a.CLEAN_PRICE - b.CLEAN_PRICE) / NULLIF(GREATEST(a.CLEAN_PRICE, b.CLEAN_PRICE), 0) < 0.30
                AND VECTOR_COSINE_SIMILARITY(a.EMBEDDING, b.EMBEDDING) >= 0.35)
        )
)
SELECT
    *,
    -- Hybrid composite score with weights: Vector 40%, Model 25%, Token 25%, Brand 10%
    CASE
        WHEN MODEL_SCORE >= 0.90 THEN 0.95 + (0.05 * VECTOR_SCORE)   -- Model exact match boost
        ELSE (VECTOR_SCORE * 0.40) + (MODEL_SCORE * 0.25) + (TOKEN_SCORE * 0.25) + (BRAND_SCORE * 0.10)
    END
    *
    -- Brand contradiction penalty: if both have known brands that differ, reduce by 70%
    CASE
        WHEN ABT_BRAND != 'Other' AND BUY_BRAND != 'Other' AND ABT_BRAND != BUY_BRAND THEN 0.30
        ELSE 1.0
    END AS COMPOSITE_SCORE
FROM scored_pairs;

-- ============================================================================
-- 3. ENTITY RESOLUTION TABLE: Final matches
-- ============================================================================
CREATE OR REPLACE TABLE FINAL_PRODUCT_MATCHES (
    MATCH_ID            VARCHAR(64),
    ABT_ID              NUMBER,
    BUY_ID              NUMBER,
    ABT_NAME            VARCHAR(1000),
    BUY_NAME            VARCHAR(1000),
    ABT_BRAND           VARCHAR(100),
    BUY_BRAND           VARCHAR(100),
    ABT_PRICE           FLOAT,
    BUY_PRICE           FLOAT,
    PRICE_DIFFERENCE    FLOAT,
    PRICE_GAP_PCT       FLOAT,
    VECTOR_SCORE        FLOAT,
    TOKEN_SCORE         FLOAT,
    MODEL_SCORE         FLOAT,
    BRAND_SCORE         FLOAT,
    COMPOSITE_SCORE     FLOAT,
    MATCH_STRATEGY      VARCHAR(100),
    LLM_VERIFICATION    VARCHAR(20),       -- CONFIRMED / REJECTED / UNCERTAIN
    LLM_REASONING       VARCHAR(2000),     -- Real LLM explanation per match
    IS_HIGH_CONFIDENCE  BOOLEAN,
    RESOLVED_AT         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Final AI-resolved product matches with LLM verification';

-- ============================================================================
-- 4. STORED PROCEDURE: Execute Entity Resolution Pipeline
-- ============================================================================
CREATE OR REPLACE PROCEDURE EXECUTE_ENTITY_RESOLUTION(CONFIDENCE_THRESHOLD FLOAT)
    RETURNS VARCHAR
    LANGUAGE SQL
    EXECUTE AS CALLER
    COMMENT = 'Run the full multi-strategy entity resolution pipeline with top-1 selection'
AS
BEGIN
    -- Step 1: Insert top-1 match per ABT product above threshold
    TRUNCATE TABLE RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES;

    INSERT INTO RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES (
        MATCH_ID, ABT_ID, BUY_ID, ABT_NAME, BUY_NAME,
        ABT_BRAND, BUY_BRAND, ABT_PRICE, BUY_PRICE,
        PRICE_DIFFERENCE, PRICE_GAP_PCT,
        VECTOR_SCORE, TOKEN_SCORE, MODEL_SCORE, BRAND_SCORE, COMPOSITE_SCORE,
        MATCH_STRATEGY, LLM_VERIFICATION, LLM_REASONING, IS_HIGH_CONFIDENCE
    )
    SELECT
        MD5(ABT_ID::VARCHAR || '-' || BUY_ID::VARCHAR) AS MATCH_ID,
        ABT_ID, BUY_ID, ABT_NAME, BUY_NAME,
        ABT_BRAND, BUY_BRAND, ABT_PRICE, BUY_PRICE,
        CASE WHEN ABT_PRICE IS NOT NULL AND BUY_PRICE IS NOT NULL
             THEN ROUND(ABT_PRICE - BUY_PRICE, 2) ELSE NULL END,
        CASE WHEN ABT_PRICE IS NOT NULL AND BUY_PRICE IS NOT NULL AND BUY_PRICE > 0
             THEN ROUND(((ABT_PRICE - BUY_PRICE) / BUY_PRICE) * 100, 2) ELSE NULL END,
        VECTOR_SCORE, TOKEN_SCORE, MODEL_SCORE, BRAND_SCORE, COMPOSITE_SCORE,
        -- Strategy classification
        CASE
            WHEN MODEL_SCORE >= 0.85 THEN 'EXACT_MODEL_MATCH'
            WHEN VECTOR_SCORE >= 0.70 THEN 'CORTEX_VECTOR_SEMANTIC'
            WHEN TOKEN_SCORE >= 0.50 THEN 'TOKEN_FUZZY_MATCH'
            ELSE 'HYBRID_ENSEMBLE'
        END,
        -- LLM verification placeholder (will be updated in step 2)
        'PENDING',
        'Pending LLM verification',
        CASE WHEN COMPOSITE_SCORE >= 0.75 THEN TRUE ELSE FALSE END
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (PARTITION BY ABT_ID ORDER BY COMPOSITE_SCORE DESC) AS RN
        FROM RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.V_CANDIDATE_MATCHES
        WHERE COMPOSITE_SCORE >= :CONFIDENCE_THRESHOLD
    )
    WHERE RN = 1;

    RETURN 'Entity resolution complete: ' ||
           (SELECT COUNT(*) FROM RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES) ||
           ' matches found at threshold ' || :CONFIDENCE_THRESHOLD;
END;

-- ============================================================================
-- 5. STORED PROCEDURE: LLM Match Verification
-- ============================================================================
-- Uses CORTEX.COMPLETE to verify ambiguous matches and provide per-match reasoning.
-- Only verifies matches in the UNCERTAIN band (0.50 - 0.80 confidence).
-- High-confidence matches (>0.80) are auto-confirmed.

CREATE OR REPLACE PROCEDURE VERIFY_MATCHES_WITH_LLM(BATCH_SIZE INT)
    RETURNS VARCHAR
    LANGUAGE SQL
    EXECUTE AS CALLER
    COMMENT = 'Use Cortex LLM to verify ambiguous matches and generate per-match explanations'
AS
DECLARE
    verified_count INT DEFAULT 0;
    auto_confirmed INT DEFAULT 0;
    pending_before INT DEFAULT 0;
    pending_after INT DEFAULT 0;
BEGIN
    -- Step 1: Count pending before auto-confirm
    pending_before := (SELECT COUNT(*) FROM RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES
                       WHERE COMPOSITE_SCORE >= 0.80 AND LLM_VERIFICATION = 'PENDING');

    -- Step 2: Auto-confirm high-confidence matches
    UPDATE RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES
    SET LLM_VERIFICATION = 'CONFIRMED',
        LLM_REASONING = 'Auto-confirmed: composite score above 0.80 with strong multi-signal agreement',
        IS_HIGH_CONFIDENCE = TRUE
    WHERE COMPOSITE_SCORE >= 0.80
      AND LLM_VERIFICATION = 'PENDING';

    auto_confirmed := :pending_before;

    -- Step 3: LLM-verify uncertain matches (0.50 - 0.80)
    -- Process in batches to manage Cortex API throughput
    CREATE OR REPLACE TEMPORARY TABLE _LLM_BATCH AS
    SELECT
        MATCH_ID,
        ABT_NAME,
        BUY_NAME,
        ABT_BRAND,
        BUY_BRAND,
        COMPOSITE_SCORE,
        VECTOR_SCORE,
        MODEL_SCORE,
        SNOWFLAKE.CORTEX.COMPLETE(
            'llama3.1-70b',
            'You are a product matching expert. Determine if these two product listings refer to the SAME physical product.

Product A (Abt Electronics): ' || ABT_NAME || '
Product B (Buy.com): ' || BUY_NAME || '

Matching signals:
- Vector similarity: ' || ROUND(VECTOR_SCORE, 3)::VARCHAR || '
- Model number similarity: ' || ROUND(MODEL_SCORE, 3)::VARCHAR || '
- Brand A: ' || ABT_BRAND || ', Brand B: ' || BUY_BRAND || '

Respond with EXACTLY this JSON format (no other text):
{"verdict": "CONFIRMED" or "REJECTED", "reason": "one sentence explanation"}'
        ) AS LLM_RESPONSE
    FROM RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES
    WHERE LLM_VERIFICATION = 'PENDING'
      AND COMPOSITE_SCORE BETWEEN 0.50 AND 0.80
    LIMIT :BATCH_SIZE;

    -- Step 4: Parse LLM responses and update matches
    UPDATE RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES f
    SET f.LLM_VERIFICATION = COALESCE(
            TRY_PARSE_JSON(b.LLM_RESPONSE):verdict::VARCHAR,
            'UNCERTAIN'
        ),
        f.LLM_REASONING = COALESCE(
            TRY_PARSE_JSON(b.LLM_RESPONSE):reason::VARCHAR,
            LEFT(b.LLM_RESPONSE, 500)
        )
    FROM _LLM_BATCH b
    WHERE f.MATCH_ID = b.MATCH_ID;

    verified_count := (SELECT COUNT(*) FROM _LLM_BATCH);

    DROP TABLE IF EXISTS _LLM_BATCH;

    RETURN 'LLM verification complete: ' || :auto_confirmed || ' auto-confirmed, ' ||
           :verified_count || ' LLM-verified';
END;

-- ============================================================================
-- 6. TASK: Scheduled entity resolution refresh
-- ============================================================================
CREATE OR REPLACE TASK TASK_RESOLVE_MATCHES
    WAREHOUSE = RETAIL_AI_V2_WH
    AFTER RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.TASK_REFRESH_EMBEDDINGS
    COMMENT = 'Re-run entity resolution after embeddings refresh'
AS
    CALL RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.EXECUTE_ENTITY_RESOLUTION(0.50);

ALTER TASK TASK_RESOLVE_MATCHES RESUME;

CREATE OR REPLACE TASK TASK_LLM_VERIFY
    WAREHOUSE = RETAIL_AI_V2_WH
    AFTER RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.TASK_RESOLVE_MATCHES
    COMMENT = 'LLM-verify uncertain matches after resolution'
AS
    CALL RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.VERIFY_MATCHES_WITH_LLM(100);

ALTER TASK TASK_LLM_VERIFY RESUME;

-- ============================================================================
-- 7. CUSTOM TOOL PROCEDURES (for Cortex Agents to call)
-- ============================================================================

-- 7a. Product search and match lookup tool
CREATE OR REPLACE PROCEDURE TOOL_SEARCH_MATCHES(QUERY VARCHAR, MIN_CONFIDENCE FLOAT)
    RETURNS TABLE (
        ABT_NAME VARCHAR, BUY_NAME VARCHAR, ABT_BRAND VARCHAR,
        ABT_PRICE FLOAT, BUY_PRICE FLOAT, COMPOSITE_SCORE FLOAT,
        MATCH_STRATEGY VARCHAR, LLM_VERIFICATION VARCHAR, PRICE_GAP_PCT FLOAT
    )
    LANGUAGE SQL
    EXECUTE AS CALLER
    COMMENT = 'Search matched products by name, brand, or model — used by Product Matching Agent'
AS
BEGIN
    LET res RESULTSET := (
        SELECT ABT_NAME, BUY_NAME, ABT_BRAND, ABT_PRICE, BUY_PRICE,
               COMPOSITE_SCORE, MATCH_STRATEGY, LLM_VERIFICATION, PRICE_GAP_PCT
        FROM RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES
        WHERE COMPOSITE_SCORE >= :MIN_CONFIDENCE
          AND (LOWER(ABT_NAME) LIKE '%' || LOWER(:QUERY) || '%'
               OR LOWER(BUY_NAME) LIKE '%' || LOWER(:QUERY) || '%'
               OR LOWER(ABT_BRAND) LIKE '%' || LOWER(:QUERY) || '%')
        ORDER BY COMPOSITE_SCORE DESC
        LIMIT 20
    );
    RETURN TABLE(res);
END;

-- 7b. Pricing recommendation tool
CREATE OR REPLACE PROCEDURE TOOL_GET_PRICING_RECOMMENDATION(PRODUCT_QUERY VARCHAR, STRATEGY VARCHAR)
    RETURNS TABLE (
        PRODUCT_NAME VARCHAR, CURRENT_PRICE FLOAT, COMPETITOR_PRICE FLOAT,
        RECOMMENDED_PRICE FLOAT, PRICE_CHANGE_PCT FLOAT,
        NEW_MARGIN_PCT FLOAT, DEMAND_UPLIFT_PCT FLOAT,
        MONTHLY_PROFIT_IMPACT FLOAT, ACTION_TYPE VARCHAR
    )
    LANGUAGE SQL
    EXECUTE AS CALLER
    COMMENT = 'Generate dynamic pricing recommendation — used by Price Optimization Agent'
AS
BEGIN
    LET res RESULTSET := (
        SELECT
            ABT_NAME AS PRODUCT_NAME,
            ABT_PRICE AS CURRENT_PRICE,
            BUY_PRICE AS COMPETITOR_PRICE,
            pr.RECOMMENDED_PRICE,
            pr.PRICE_CHANGE_PCT,
            pr.NEW_MARGIN_PCT,
            pr.DEMAND_UPLIFT_PCT,
            pr.MONTHLY_PROFIT_IMPACT,
            pr.ACTION_TYPE
        FROM RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES m
        JOIN RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.PRICING_RECOMMENDATIONS pr
            ON m.MATCH_ID = pr.MATCH_ID
        WHERE LOWER(m.ABT_NAME) LIKE '%' || LOWER(:PRODUCT_QUERY) || '%'
           OR LOWER(m.ABT_BRAND) LIKE '%' || LOWER(:PRODUCT_QUERY) || '%'
        ORDER BY m.COMPOSITE_SCORE DESC
        LIMIT 10
    );
    RETURN TABLE(res);
END;

-- 7c. Market intelligence tool
CREATE OR REPLACE PROCEDURE TOOL_MARKET_INTELLIGENCE(BRAND_FILTER VARCHAR)
    RETURNS TABLE (
        BRAND VARCHAR, MATCHED_SKUS INT, AVG_CONFIDENCE FLOAT,
        AVG_ABT_PRICE FLOAT, AVG_BUY_PRICE FLOAT, AVG_PRICE_GAP_PCT FLOAT,
        ABT_WINNING INT, BUY_WINNING INT, COMPETITIVENESS_INDEX FLOAT
    )
    LANGUAGE SQL
    EXECUTE AS CALLER
    COMMENT = 'Brand-level market intelligence summary — used by Market Intelligence Agent'
AS
BEGIN
    LET res RESULTSET := (
        SELECT * FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.V_MARKET_INTELLIGENCE
        WHERE :BRAND_FILTER = 'ALL' OR UPPER(BRAND) = UPPER(:BRAND_FILTER)
        ORDER BY MATCHED_SKUS DESC
        LIMIT 25
    );
    RETURN TABLE(res);
END;

-- ============================================================================
-- EXECUTION ORDER:
-- 1. Run 01_foundation.sql first
-- 2. CALL RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.GENERATE_EMBEDDINGS();
-- 3. CALL RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.EXECUTE_ENTITY_RESOLUTION(0.50);
-- 4. CALL RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.VERIFY_MATCHES_WITH_LLM(200);
-- ============================================================================

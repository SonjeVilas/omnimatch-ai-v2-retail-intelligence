-- ============================================================================
-- OMNIMATCH AI v2: RETAIL INTELLIGENCE PLATFORM (REDESIGNED)
-- File 06: Ground Truth Evaluation, Data Metric Functions, LLM Error Analysis
-- ============================================================================
-- Prerequisites: Run files 01-05 and execute pipeline procedures
-- ============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE RETAIL_AI_V2_WH;
USE DATABASE RETAIL_INTELLIGENCE_V2_DB;
USE SCHEMA ANALYTICS;

-- ============================================================================
-- 1. BENCHMARK EVALUATION VIEW (TP / FP / FN classification)
-- ============================================================================
CREATE OR REPLACE VIEW V_BENCHMARK_EVALUATION
    COMMENT = 'Full outer join of AI predictions vs ground truth — classifies each pair as TP, FP, or FN'
AS
SELECT
    COALESCE(m.ABT_ID, gt.ID_ABT) AS ABT_ID,
    COALESCE(m.BUY_ID, gt.ID_BUY) AS BUY_ID,
    m.ABT_NAME,
    m.BUY_NAME,
    m.ABT_BRAND,
    m.COMPOSITE_SCORE,
    m.MATCH_STRATEGY,
    m.LLM_VERIFICATION,
    CASE
        WHEN m.ABT_ID IS NOT NULL AND gt.ID_ABT IS NOT NULL THEN 'TRUE_POSITIVE'
        WHEN m.ABT_ID IS NOT NULL AND gt.ID_ABT IS NULL     THEN 'FALSE_POSITIVE'
        WHEN m.ABT_ID IS NULL     AND gt.ID_ABT IS NOT NULL THEN 'FALSE_NEGATIVE'
    END AS CLASSIFICATION,
    CASE WHEN gt.ID_ABT IS NOT NULL THEN TRUE ELSE FALSE END AS IS_GROUND_TRUTH,
    CASE WHEN m.ABT_ID IS NOT NULL THEN TRUE ELSE FALSE END AS IS_PREDICTED
FROM RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES m
FULL OUTER JOIN RETAIL_INTELLIGENCE_V2_DB.CORE.GROUND_TRUTH_MAPPING gt
    ON m.ABT_ID = gt.ID_ABT AND m.BUY_ID = gt.ID_BUY;

-- ============================================================================
-- 2. BENCHMARK SUMMARY METRICS VIEW (Precision, Recall, F1)
-- ============================================================================
CREATE OR REPLACE VIEW V_BENCHMARK_METRICS
    COMMENT = 'Precision, Recall, and F1 Score computed from ground truth evaluation'
AS
WITH counts AS (
    SELECT
        COUNT_IF(CLASSIFICATION = 'TRUE_POSITIVE') AS TP,
        COUNT_IF(CLASSIFICATION = 'FALSE_POSITIVE') AS FP,
        COUNT_IF(CLASSIFICATION = 'FALSE_NEGATIVE') AS FN
    FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.V_BENCHMARK_EVALUATION
)
SELECT
    (SELECT COUNT(*) FROM RETAIL_INTELLIGENCE_V2_DB.CORE.GROUND_TRUTH_MAPPING) AS TOTAL_GROUND_TRUTH,
    (SELECT COUNT(*) FROM RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES) AS TOTAL_PREDICTED,
    TP AS TRUE_POSITIVES,
    FP AS FALSE_POSITIVES,
    FN AS FALSE_NEGATIVES,
    ROUND((TP / NULLIF(TP + FP, 0)) * 100, 2) AS PRECISION_PCT,
    ROUND((TP / NULLIF(TP + FN, 0)) * 100, 2) AS RECALL_PCT,
    ROUND(
        (2.0 * (TP / NULLIF(TP + FP, 0)) * (TP / NULLIF(TP + FN, 0)))
        / NULLIF((TP / NULLIF(TP + FP, 0)) + (TP / NULLIF(TP + FN, 0)), 0) * 100, 2
    ) AS F1_SCORE_PCT
FROM counts;

-- ============================================================================
-- 3. ERROR ANALYSIS VIEWS
-- ============================================================================

-- Top False Positives (highest confidence wrong matches)
CREATE OR REPLACE VIEW V_ERROR_FALSE_POSITIVES
    COMMENT = 'Highest-confidence false positive matches for error analysis'
AS
SELECT
    ABT_ID, BUY_ID, ABT_NAME, BUY_NAME, ABT_BRAND,
    COMPOSITE_SCORE, MATCH_STRATEGY, LLM_VERIFICATION
FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.V_BENCHMARK_EVALUATION
WHERE CLASSIFICATION = 'FALSE_POSITIVE'
ORDER BY COMPOSITE_SCORE DESC;

-- Top False Negatives (missed matches we should have found)
CREATE OR REPLACE VIEW V_ERROR_FALSE_NEGATIVES
    COMMENT = 'Missed ground truth matches — products we should have matched but did not'
AS
SELECT
    gt.ID_ABT AS ABT_ID,
    gt.ID_BUY AS BUY_ID,
    a.NAME AS ABT_NAME,
    b.NAME AS BUY_NAME,
    a_clean.BRAND AS ABT_BRAND,
    b_clean.BRAND AS BUY_BRAND
FROM RETAIL_INTELLIGENCE_V2_DB.CORE.GROUND_TRUTH_MAPPING gt
LEFT JOIN RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES m
    ON gt.ID_ABT = m.ABT_ID AND gt.ID_BUY = m.BUY_ID
JOIN RETAIL_INTELLIGENCE_V2_DB.CORE.RAW_ABT_CATALOG a ON gt.ID_ABT = a.ID
JOIN RETAIL_INTELLIGENCE_V2_DB.CORE.RAW_BUY_CATALOG b ON gt.ID_BUY = b.ID
LEFT JOIN RETAIL_INTELLIGENCE_V2_DB.CORE.DT_CLEAN_ABT_CATALOG a_clean ON gt.ID_ABT = a_clean.ID
LEFT JOIN RETAIL_INTELLIGENCE_V2_DB.CORE.DT_CLEAN_BUY_CATALOG b_clean ON gt.ID_BUY = b_clean.ID
WHERE m.ABT_ID IS NULL;

-- ============================================================================
-- 4. ACCURACY BY STRATEGY VIEW
-- ============================================================================
CREATE OR REPLACE VIEW V_ACCURACY_BY_STRATEGY
    COMMENT = 'Match accuracy broken down by resolution strategy'
AS
SELECT
    MATCH_STRATEGY,
    COUNT(*) AS TOTAL_PREDICTIONS,
    COUNT_IF(CLASSIFICATION = 'TRUE_POSITIVE') AS TRUE_POSITIVES,
    COUNT_IF(CLASSIFICATION = 'FALSE_POSITIVE') AS FALSE_POSITIVES,
    ROUND(COUNT_IF(CLASSIFICATION = 'TRUE_POSITIVE')::FLOAT
          / NULLIF(COUNT(*), 0) * 100, 2) AS PRECISION_PCT,
    ROUND(AVG(COMPOSITE_SCORE) * 100, 2) AS AVG_CONFIDENCE_PCT
FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.V_BENCHMARK_EVALUATION
WHERE CLASSIFICATION IN ('TRUE_POSITIVE', 'FALSE_POSITIVE')
GROUP BY MATCH_STRATEGY
ORDER BY PRECISION_PCT DESC;

-- ============================================================================
-- 5. ACCURACY BY BRAND VIEW
-- ============================================================================
CREATE OR REPLACE VIEW V_ACCURACY_BY_BRAND
    COMMENT = 'Match accuracy broken down by product brand'
AS
SELECT
    ABT_BRAND AS BRAND,
    COUNT(*) AS TOTAL,
    COUNT_IF(CLASSIFICATION = 'TRUE_POSITIVE') AS TP,
    COUNT_IF(CLASSIFICATION = 'FALSE_POSITIVE') AS FP,
    COUNT_IF(CLASSIFICATION = 'FALSE_NEGATIVE') AS FN,
    ROUND(COUNT_IF(CLASSIFICATION = 'TRUE_POSITIVE')::FLOAT
          / NULLIF(COUNT_IF(CLASSIFICATION IN ('TRUE_POSITIVE', 'FALSE_POSITIVE')), 0) * 100, 2) AS PRECISION_PCT,
    ROUND(COUNT_IF(CLASSIFICATION = 'TRUE_POSITIVE')::FLOAT
          / NULLIF(COUNT_IF(CLASSIFICATION IN ('TRUE_POSITIVE', 'FALSE_NEGATIVE')), 0) * 100, 2) AS RECALL_PCT
FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.V_BENCHMARK_EVALUATION
WHERE ABT_BRAND IS NOT NULL AND ABT_BRAND != 'Other'
GROUP BY ABT_BRAND
HAVING COUNT(*) >= 5
ORDER BY TOTAL DESC;

-- ============================================================================
-- 6. EVALUATION HISTORY TABLE (for trend tracking)
-- ============================================================================
CREATE OR REPLACE TABLE EVALUATION_HISTORY (
    EVAL_ID         VARCHAR(64) DEFAULT UUID_STRING(),
    EVAL_TIMESTAMP  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONFIDENCE_THRESHOLD FLOAT,
    TOTAL_GROUND_TRUTH INT,
    TOTAL_PREDICTED    INT,
    TRUE_POSITIVES     INT,
    FALSE_POSITIVES    INT,
    FALSE_NEGATIVES    INT,
    PRECISION_PCT      FLOAT,
    RECALL_PCT         FLOAT,
    F1_SCORE_PCT       FLOAT,
    NOTES              VARCHAR(500)
) COMMENT = 'Historical evaluation runs for tracking accuracy improvements over time';

-- Procedure to record evaluation snapshot
CREATE OR REPLACE PROCEDURE RECORD_EVALUATION_SNAPSHOT(THRESHOLD FLOAT, NOTES VARCHAR)
    RETURNS VARCHAR
    LANGUAGE SQL
    EXECUTE AS CALLER
    COMMENT = 'Record current evaluation metrics to history table'
AS
BEGIN
    INSERT INTO RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.EVALUATION_HISTORY (
        CONFIDENCE_THRESHOLD, TOTAL_GROUND_TRUTH, TOTAL_PREDICTED,
        TRUE_POSITIVES, FALSE_POSITIVES, FALSE_NEGATIVES,
        PRECISION_PCT, RECALL_PCT, F1_SCORE_PCT, NOTES
    )
    SELECT
        :THRESHOLD,
        TOTAL_GROUND_TRUTH, TOTAL_PREDICTED,
        TRUE_POSITIVES, FALSE_POSITIVES, FALSE_NEGATIVES,
        PRECISION_PCT, RECALL_PCT, F1_SCORE_PCT,
        :NOTES
    FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.V_BENCHMARK_METRICS;

    RETURN 'Evaluation snapshot recorded at ' || CURRENT_TIMESTAMP()::VARCHAR;
END;

-- ============================================================================
-- 7. LLM ERROR ANALYSIS PROCEDURE
-- ============================================================================
-- Uses CORTEX.COMPLETE to explain why specific false positives/negatives occurred

CREATE OR REPLACE PROCEDURE ANALYZE_ERRORS_WITH_LLM(ERROR_TYPE VARCHAR, BATCH_SIZE INT)
    RETURNS TABLE (ABT_NAME VARCHAR, BUY_NAME VARCHAR, CLASSIFICATION VARCHAR, LLM_ANALYSIS VARCHAR)
    LANGUAGE SQL
    EXECUTE AS CALLER
    COMMENT = 'Use Cortex LLM to explain false positives and false negatives'
AS
BEGIN
    LET res RESULTSET := (
        SELECT
            ABT_NAME,
            BUY_NAME,
            CLASSIFICATION,
            SNOWFLAKE.CORTEX.COMPLETE(
                'llama3.1-70b',
                CASE
                    WHEN CLASSIFICATION = 'FALSE_POSITIVE' THEN
                        'These two products were matched by our AI but they are NOT the same product. Explain in one sentence why the AI might have been confused:
Product A: ' || COALESCE(ABT_NAME, 'Unknown') || '
Product B: ' || COALESCE(BUY_NAME, 'Unknown')
                    ELSE
                        'These two products ARE the same product but our AI failed to match them. Explain in one sentence why the AI might have missed this match:
Product A: ' || COALESCE(ABT_NAME, 'Unknown') || '
Product B: ' || COALESCE(BUY_NAME, 'Unknown')
                END
            ) AS LLM_ANALYSIS
        FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.V_BENCHMARK_EVALUATION
        WHERE CLASSIFICATION = :ERROR_TYPE
        ORDER BY COMPOSITE_SCORE DESC NULLS LAST
        LIMIT :BATCH_SIZE
    );
    RETURN TABLE(res);
END;

-- ============================================================================
-- EXECUTION:
-- SELECT * FROM V_BENCHMARK_METRICS;
-- SELECT * FROM V_ACCURACY_BY_STRATEGY;
-- SELECT * FROM V_ACCURACY_BY_BRAND;
-- SELECT * FROM V_ERROR_FALSE_POSITIVES LIMIT 10;
-- SELECT * FROM V_ERROR_FALSE_NEGATIVES LIMIT 10;
-- CALL RECORD_EVALUATION_SNAPSHOT(0.50, 'Initial v2 pipeline run');
-- CALL ANALYZE_ERRORS_WITH_LLM('FALSE_POSITIVE', 5);
-- CALL ANALYZE_ERRORS_WITH_LLM('FALSE_NEGATIVE', 5);
-- ============================================================================

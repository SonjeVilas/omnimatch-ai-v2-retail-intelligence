-- ============================================================================
-- OMNIMATCH AI v2: RETAIL INTELLIGENCE PLATFORM (REDESIGNED)
-- File 08: Data Metric Functions (DMFs) + Snowflake Alert
-- ============================================================================
-- Prerequisites: Run files 01-07 first (all objects must exist with data)
-- ============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE RETAIL_AI_V2_WH;
USE DATABASE RETAIL_INTELLIGENCE_V2_DB;

-- ============================================================================
-- 1. GRANT PRIVILEGES FOR DMFs
-- ============================================================================
GRANT EXECUTE DATA METRIC FUNCTION ON ACCOUNT TO ROLE ACCOUNTADMIN;

-- ============================================================================
-- 2. CUSTOM DMF: Precision Drift Monitor
-- ============================================================================
-- Tracks precision of FINAL_PRODUCT_MATCHES against ground truth.
-- Returns the number of false positives — a value > 0 means precision < 100%.
-- Rising values indicate the pipeline is degrading.

USE SCHEMA CORTEX_AI;

CREATE OR REPLACE DATA METRIC FUNCTION DMF_FALSE_POSITIVE_COUNT(
    arg_t TABLE(arg_abt_id NUMBER, arg_buy_id NUMBER)
)
RETURNS NUMBER
COMMENT = 'Counts false positives: predicted matches that are NOT in the ground truth. Rising values indicate precision degradation.'
AS
$$
    SELECT COUNT(*)
    FROM arg_t p
    WHERE NOT EXISTS (
        SELECT 1
        FROM RETAIL_INTELLIGENCE_V2_DB.CORE.GROUND_TRUTH_MAPPING gt
        WHERE gt.ID_ABT = p.arg_abt_id AND gt.ID_BUY = p.arg_buy_id
    )
$$;

-- ============================================================================
-- 3. CUSTOM DMF: Embedding Freshness Monitor
-- ============================================================================
-- Returns the number of products in the cleaned catalog that are missing
-- embeddings. A value > 0 means the embedding pipeline is stale.

CREATE OR REPLACE DATA METRIC FUNCTION DMF_MISSING_EMBEDDINGS(
    arg_t TABLE(arg_product_id NUMBER)
)
RETURNS NUMBER
COMMENT = 'Counts products that exist in the cleaned catalog but lack embeddings. Non-zero means the embedding pipeline is stale.'
AS
$$
    SELECT COUNT(*)
    FROM RETAIL_INTELLIGENCE_V2_DB.CORE.DT_CLEAN_ABT_CATALOG c
    WHERE NOT EXISTS (
        SELECT 1 FROM arg_t e WHERE e.arg_product_id = c.ID
    )
$$;

-- ============================================================================
-- 4. CUSTOM DMF: Match Confidence Distribution Monitor
-- ============================================================================
-- Returns the count of low-confidence matches (below 0.60).
-- A rising count signals the pipeline is producing weaker matches.

CREATE OR REPLACE DATA METRIC FUNCTION DMF_LOW_CONFIDENCE_MATCH_COUNT(
    arg_t TABLE(arg_composite_score FLOAT)
)
RETURNS NUMBER
COMMENT = 'Counts matches with composite score below 0.60. Rising values indicate match quality degradation.'
AS
$$
    SELECT COUNT(*)
    FROM arg_t
    WHERE arg_composite_score < 0.60
$$;

-- ============================================================================
-- 5. ATTACH DMFs TO TABLES
-- ============================================================================

-- 5a: Attach precision monitor to FINAL_PRODUCT_MATCHES
ALTER TABLE RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES
    ADD DATA METRIC FUNCTION RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.DMF_FALSE_POSITIVE_COUNT
    ON (ABT_ID, BUY_ID);

-- 5b: Attach freshness monitor to ABT_EMBEDDINGS
ALTER TABLE RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.ABT_EMBEDDINGS
    ADD DATA METRIC FUNCTION RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.DMF_MISSING_EMBEDDINGS
    ON (PRODUCT_ID);

-- 5c: Attach low-confidence monitor to FINAL_PRODUCT_MATCHES
ALTER TABLE RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES
    ADD DATA METRIC FUNCTION RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.DMF_LOW_CONFIDENCE_MATCH_COUNT
    ON (COMPOSITE_SCORE);

-- 5d: Attach system NULL_COUNT DMF to key columns
ALTER TABLE RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT
    ON (ABT_NAME);

ALTER TABLE RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.NULL_COUNT
    ON (BUY_NAME);

-- 5e: Attach system DUPLICATE_COUNT to match IDs (should always be 0)
ALTER TABLE RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES
    ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.DUPLICATE_COUNT
    ON (MATCH_ID);

-- ============================================================================
-- 6. SET DMF SCHEDULE: Run every 12 hours
-- ============================================================================
ALTER TABLE RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES
    SET DATA_METRIC_SCHEDULE = 'USING CRON 0 0,12 * * * UTC';

ALTER TABLE RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.ABT_EMBEDDINGS
    SET DATA_METRIC_SCHEDULE = 'USING CRON 0 0,12 * * * UTC';

-- ============================================================================
-- 7. ALERT: Critical Anomaly Threshold
-- ============================================================================
-- Fires when the number of HIGH-severity market anomalies exceeds 10,
-- logging the alert into an audit table for operational tracking.

USE SCHEMA ANALYTICS;

-- Audit table for alert history
CREATE OR REPLACE TABLE ALERT_AUDIT_LOG (
    ALERT_NAME          VARCHAR(200),
    TRIGGERED_AT        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    ANOMALY_COUNT       NUMBER,
    CRITICAL_UNDERCUTS  NUMBER,
    MARGIN_OPPORTUNITIES NUMBER,
    DETAILS             VARCHAR(2000)
) COMMENT = 'Audit log for Snowflake Alert triggers — tracks anomaly threshold breaches';

-- Grant alert privileges
GRANT EXECUTE ALERT ON ACCOUNT TO ROLE ACCOUNTADMIN;

-- Create the alert (serverless — no warehouse needed)
CREATE OR REPLACE ALERT ALERT_CRITICAL_ANOMALIES
    SCHEDULE = '60 MINUTE'
    COMMENT = 'Fires when critical market anomalies exceed threshold — logs to audit table and can trigger notifications'
    IF (EXISTS (
        SELECT 1
        FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.V_MARKET_ANOMALIES
        WHERE SEVERITY = 'HIGH'
        HAVING COUNT(*) > 10
    ))
    THEN
        INSERT INTO RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.ALERT_AUDIT_LOG
            (ALERT_NAME, ANOMALY_COUNT, CRITICAL_UNDERCUTS, MARGIN_OPPORTUNITIES, DETAILS)
        SELECT
            'ALERT_CRITICAL_ANOMALIES',
            COUNT(*),
            COUNT_IF(ANOMALY_TYPE = 'CRITICAL_UNDERCUT'),
            COUNT_IF(ANOMALY_TYPE = 'MARGIN_OPPORTUNITY'),
            'Threshold exceeded: ' || COUNT(*) || ' HIGH-severity anomalies detected at ' || CURRENT_TIMESTAMP()::VARCHAR
        FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.V_MARKET_ANOMALIES
        WHERE SEVERITY = 'HIGH';

-- Resume the alert so it is active
ALTER ALERT ALERT_CRITICAL_ANOMALIES RESUME;

-- ============================================================================
-- 8. ALERT: Precision Degradation Monitor
-- ============================================================================
-- Fires when precision drops below 90% — early warning for pipeline issues.

CREATE OR REPLACE ALERT ALERT_PRECISION_DEGRADATION
    SCHEDULE = '360 MINUTE'
    COMMENT = 'Fires when entity resolution precision drops below 90% — early warning for pipeline quality issues'
    IF (EXISTS (
        SELECT 1
        FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.V_BENCHMARK_METRICS
        WHERE PRECISION_PCT < 90.0
    ))
    THEN
        INSERT INTO RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.ALERT_AUDIT_LOG
            (ALERT_NAME, ANOMALY_COUNT, DETAILS)
        SELECT
            'ALERT_PRECISION_DEGRADATION',
            FALSE_POSITIVES,
            'Precision degraded to ' || PRECISION_PCT || '% (threshold: 90%). ' ||
            'False positives: ' || FALSE_POSITIVES || ', F1: ' || F1_SCORE_PCT || '%'
        FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.V_BENCHMARK_METRICS;

-- Resume the alert
ALTER ALERT ALERT_PRECISION_DEGRADATION RESUME;

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================
-- SHOW DATA METRIC FUNCTIONS IN SCHEMA RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI;
-- SHOW ALERTS IN SCHEMA RETAIL_INTELLIGENCE_V2_DB.ANALYTICS;
-- SELECT * FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.ALERT_AUDIT_LOG;
--
-- Manual DMF test:
-- SELECT RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.DMF_FALSE_POSITIVE_COUNT(
--     SELECT ABT_ID, BUY_ID FROM RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES
-- );
--
-- Manual alert test:
-- EXECUTE ALERT ALERT_CRITICAL_ANOMALIES;
-- ============================================================================

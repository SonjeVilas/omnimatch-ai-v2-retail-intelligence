-- ============================================================================
-- OMNIMATCH AI v2: RETAIL INTELLIGENCE PLATFORM (REDESIGNED)
-- File 01: Foundation — Database, Schemas, Dynamic Tables, Streams, Tasks, UDFs
-- ============================================================================
-- This file creates the new RETAIL_INTELLIGENCE_V2_DB database from scratch.
-- Source data is read from RETAIL_INTELLIGENCE_DB.CORE (original, untouched).
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- ============================================================================
-- 1. DATABASE & SCHEMAS
-- ============================================================================
CREATE DATABASE IF NOT EXISTS RETAIL_INTELLIGENCE_V2_DB
    COMMENT = 'OmniMatch AI v2: Redesigned Retail Intelligence Platform — Snowflake x Capgemini Hackathon 2026';

CREATE SCHEMA IF NOT EXISTS RETAIL_INTELLIGENCE_V2_DB.CORE
    COMMENT = 'Raw ingestion and cleaned data layer';

CREATE SCHEMA IF NOT EXISTS RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI
    COMMENT = 'Cortex AI pipeline: embeddings, search, matching, agents';

CREATE SCHEMA IF NOT EXISTS RETAIL_INTELLIGENCE_V2_DB.ANALYTICS
    COMMENT = 'Dynamic pricing, market intelligence, evaluation metrics';

-- ============================================================================
-- 2. WAREHOUSE
-- ============================================================================
CREATE WAREHOUSE IF NOT EXISTS RETAIL_AI_V2_WH
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 120
    AUTO_RESUME = TRUE
    COMMENT = 'Dedicated warehouse for OmniMatch AI v2 pipeline';

USE WAREHOUSE RETAIL_AI_V2_WH;
USE DATABASE RETAIL_INTELLIGENCE_V2_DB;

-- ============================================================================
-- 3. RAW TABLES (mirror from original DB for independence)
-- ============================================================================
USE SCHEMA CORE;

CREATE OR REPLACE TABLE RAW_ABT_CATALOG (
    ID          NUMBER,
    NAME        VARCHAR(1000),
    DESCRIPTION VARCHAR(5000),
    PRICE       VARCHAR(50)
) COMMENT = 'Abt Electronics product catalog — raw ingestion';

CREATE OR REPLACE TABLE RAW_BUY_CATALOG (
    ID           NUMBER,
    NAME         VARCHAR(1000),
    DESCRIPTION  VARCHAR(5000),
    MANUFACTURER VARCHAR(500),
    PRICE        VARCHAR(50)
) COMMENT = 'Buy.com product catalog — raw ingestion';

CREATE OR REPLACE TABLE GROUND_TRUTH_MAPPING (
    ID_ABT NUMBER,
    ID_BUY NUMBER
) COMMENT = 'Expert-validated true product matches (benchmark dataset)';

-- Copy data from original DB
INSERT INTO RAW_ABT_CATALOG SELECT * FROM RETAIL_INTELLIGENCE_DB.CORE.RAW_ABT_CATALOG;
INSERT INTO RAW_BUY_CATALOG SELECT * FROM RETAIL_INTELLIGENCE_DB.CORE.RAW_BUY_CATALOG;
INSERT INTO GROUND_TRUTH_MAPPING SELECT * FROM RETAIL_INTELLIGENCE_DB.CORE.GROUND_TRUTH_MAPPING;

-- ============================================================================
-- 4. UDFS: Reusable matching functions (SQL + Python)
-- ============================================================================
USE SCHEMA CORTEX_AI;

-- 4a. Token Overlap Score (Jaccard Similarity)
CREATE OR REPLACE FUNCTION UDF_TOKEN_OVERLAP_SCORE(TEXT1 VARCHAR, TEXT2 VARCHAR)
    RETURNS FLOAT
    LANGUAGE JAVASCRIPT
    COMMENT = 'Jaccard token overlap similarity between two product text strings'
AS $$
    if (!TEXT1 || !TEXT2) return 0.0;
    var tokens1 = TEXT1.toLowerCase().replace(/[^a-z0-9\s]/g, ' ').split(/\s+/).filter(t => t.length > 1);
    var tokens2 = TEXT2.toLowerCase().replace(/[^a-z0-9\s]/g, ' ').split(/\s+/).filter(t => t.length > 1);
    if (tokens1.length === 0 || tokens2.length === 0) return 0.0;
    var set1 = new Set(tokens1);
    var set2 = new Set(tokens2);
    var intersection = 0;
    set1.forEach(function(t) { if (set2.has(t)) intersection++; });
    var union_size = set1.size + set2.size - intersection;
    return union_size > 0 ? intersection / union_size : 0.0;
$$;

-- 4b. Model Number Similarity (Levenshtein-based)
CREATE OR REPLACE FUNCTION UDF_MODEL_SIMILARITY(MODEL1 VARCHAR, MODEL2 VARCHAR)
    RETURNS FLOAT
    LANGUAGE JAVASCRIPT
    COMMENT = 'Levenshtein-based model/SKU number similarity with substring containment boost'
AS $$
    if (!MODEL1 || !MODEL2) return 0.0;
    var m1 = MODEL1.toUpperCase().replace(/[^A-Z0-9]/g, '');
    var m2 = MODEL2.toUpperCase().replace(/[^A-Z0-9]/g, '');
    if (m1.length < 3 || m2.length < 3) return 0.0;
    if (m1 === m2) return 1.0;
    if (m1.length >= 4 && m2.length >= 4) {
        if (m1.indexOf(m2) >= 0 || m2.indexOf(m1) >= 0) return 0.92;
    }
    // Levenshtein distance
    var len1 = m1.length, len2 = m2.length;
    var dp = [];
    for (var i = 0; i <= len1; i++) {
        dp[i] = [i];
        for (var j = 1; j <= len2; j++) {
            dp[i][j] = i === 0 ? j : 0;
        }
    }
    for (var i = 1; i <= len1; i++) {
        for (var j = 1; j <= len2; j++) {
            var cost = m1[i-1] === m2[j-1] ? 0 : 1;
            dp[i][j] = Math.min(dp[i-1][j]+1, dp[i][j-1]+1, dp[i-1][j-1]+cost);
        }
    }
    var maxLen = Math.max(len1, len2);
    var sim = 1.0 - (dp[len1][len2] / maxLen);
    return sim >= 0.75 ? sim : 0.0;
$$;

-- ============================================================================
-- 5. DYNAMIC TABLES: Auto-refreshing cleaned product catalogs
-- ============================================================================
USE SCHEMA CORE;

CREATE OR REPLACE DYNAMIC TABLE DT_CLEAN_ABT_CATALOG
    TARGET_LAG = '1 hour'
    WAREHOUSE = RETAIL_AI_V2_WH
    COMMENT = 'Cleaned Abt catalog with brand extraction, model parsing, and embedding payload'
AS
SELECT
    ID,
    NAME,
    DESCRIPTION,
    -- Price normalization
    TRY_CAST(REGEXP_REPLACE(PRICE, '[^0-9.]', '') AS FLOAT) AS CLEAN_PRICE,
    -- Brand extraction (top 30 consumer electronics brands)
    CASE
        WHEN UPPER(NAME) LIKE '%SONY%' THEN 'Sony'
        WHEN UPPER(NAME) LIKE '%CANON%' THEN 'Canon'
        WHEN UPPER(NAME) LIKE '%PANASONIC%' THEN 'Panasonic'
        WHEN UPPER(NAME) LIKE '%SAMSUNG%' THEN 'Samsung'
        WHEN UPPER(NAME) LIKE '%LG %' OR UPPER(NAME) LIKE 'LG %' THEN 'LG'
        WHEN UPPER(NAME) LIKE '%NIKON%' THEN 'Nikon'
        WHEN UPPER(NAME) LIKE '%TOSHIBA%' THEN 'Toshiba'
        WHEN UPPER(NAME) LIKE '%DENON%' THEN 'Denon'
        WHEN UPPER(NAME) LIKE '%GARMIN%' THEN 'Garmin'
        WHEN UPPER(NAME) LIKE '%APPLE%' OR UPPER(NAME) LIKE '%IPOD%' OR UPPER(NAME) LIKE '%IPHONE%' THEN 'Apple'
        WHEN UPPER(NAME) LIKE '%WEBER%' THEN 'Weber'
        WHEN UPPER(NAME) LIKE '%LINKSYS%' THEN 'Linksys'
        WHEN UPPER(NAME) LIKE '%NETGEAR%' THEN 'Netgear'
        WHEN UPPER(NAME) LIKE '%LOGITECH%' THEN 'Logitech'
        WHEN UPPER(NAME) LIKE '%SANUS%' THEN 'Sanus'
        WHEN UPPER(NAME) LIKE '%PEERLESS%' THEN 'Peerless'
        WHEN UPPER(NAME) LIKE '%CUISINART%' THEN 'Cuisinart'
        WHEN UPPER(NAME) LIKE '%SENNHEISER%' THEN 'Sennheiser'
        WHEN UPPER(NAME) LIKE '%PIONEER%' THEN 'Pioneer'
        WHEN UPPER(NAME) LIKE '%BELKIN%' THEN 'Belkin'
        WHEN UPPER(NAME) LIKE '%BOSE%' THEN 'Bose'
        WHEN UPPER(NAME) LIKE '%SHARP%' THEN 'Sharp'
        WHEN UPPER(NAME) LIKE '%OLYMPUS%' THEN 'Olympus'
        WHEN UPPER(NAME) LIKE '%TOMTOM%' THEN 'TomTom'
        WHEN UPPER(NAME) LIKE '%GRIFFIN%' THEN 'Griffin'
        ELSE 'Other'
    END AS BRAND,
    -- Model number extraction
    REGEXP_SUBSTR(UPPER(NAME), '[A-Z]{1,4}[\\-]?[0-9]{2,}[A-Z0-9\\-]*') AS EXTRACTED_MODEL,
    -- Embedding text payload (concatenation of name + description for vector embedding)
    NAME || ' | ' || COALESCE(DESCRIPTION, '') AS EMBEDDING_TEXT,
    -- Search text (for Cortex Search Service)
    NAME || ' ' || COALESCE(DESCRIPTION, '') AS SEARCH_TEXT,
    'ABT' AS SOURCE_CATALOG
FROM RAW_ABT_CATALOG
WHERE NAME IS NOT NULL;

CREATE OR REPLACE DYNAMIC TABLE DT_CLEAN_BUY_CATALOG
    TARGET_LAG = '1 hour'
    WAREHOUSE = RETAIL_AI_V2_WH
    COMMENT = 'Cleaned Buy.com catalog with brand extraction, model parsing, and embedding payload'
AS
SELECT
    ID,
    NAME,
    DESCRIPTION,
    MANUFACTURER,
    TRY_CAST(REGEXP_REPLACE(PRICE, '[^0-9.]', '') AS FLOAT) AS CLEAN_PRICE,
    CASE
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%SONY%' THEN 'Sony'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%CANON%' THEN 'Canon'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%PANASONIC%' THEN 'Panasonic'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%SAMSUNG%' THEN 'Samsung'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%LG %' OR UPPER(NAME) LIKE 'LG %' THEN 'LG'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%NIKON%' THEN 'Nikon'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%TOSHIBA%' THEN 'Toshiba'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%DENON%' THEN 'Denon'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%GARMIN%' THEN 'Garmin'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%APPLE%' OR UPPER(NAME) LIKE '%IPOD%' THEN 'Apple'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%WEBER%' THEN 'Weber'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%LINKSYS%' THEN 'Linksys'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%NETGEAR%' THEN 'Netgear'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%LOGITECH%' THEN 'Logitech'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%SANUS%' THEN 'Sanus'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%PEERLESS%' THEN 'Peerless'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%CUISINART%' THEN 'Cuisinart'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%SENNHEISER%' THEN 'Sennheiser'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%PIONEER%' THEN 'Pioneer'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%BELKIN%' THEN 'Belkin'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%BOSE%' THEN 'Bose'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%SHARP%' THEN 'Sharp'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%OLYMPUS%' THEN 'Olympus'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%TOMTOM%' THEN 'TomTom'
        WHEN UPPER(COALESCE(NAME,'') || ' ' || COALESCE(MANUFACTURER,'')) LIKE '%GRIFFIN%' THEN 'Griffin'
        ELSE 'Other'
    END AS BRAND,
    REGEXP_SUBSTR(UPPER(NAME), '[A-Z]{1,4}[\\-]?[0-9]{2,}[A-Z0-9\\-]*') AS EXTRACTED_MODEL,
    NAME || ' | ' || COALESCE(MANUFACTURER, '') || ' | ' || COALESCE(DESCRIPTION, '') AS EMBEDDING_TEXT,
    NAME || ' ' || COALESCE(MANUFACTURER, '') || ' ' || COALESCE(DESCRIPTION, '') AS SEARCH_TEXT,
    'BUY' AS SOURCE_CATALOG
FROM RAW_BUY_CATALOG
WHERE NAME IS NOT NULL;

-- ============================================================================
-- 6. STREAMS: Change Data Capture on raw tables
-- ============================================================================
CREATE OR REPLACE STREAM STREAM_ABT_CHANGES
    ON TABLE RAW_ABT_CATALOG
    APPEND_ONLY = TRUE
    COMMENT = 'Captures new product inserts into Abt catalog';

CREATE OR REPLACE STREAM STREAM_BUY_CHANGES
    ON TABLE RAW_BUY_CATALOG
    APPEND_ONLY = TRUE
    COMMENT = 'Captures new product inserts into Buy.com catalog';

-- ============================================================================
-- 7. EMBEDDING TABLES
-- ============================================================================
USE SCHEMA CORTEX_AI;

CREATE OR REPLACE TABLE ABT_EMBEDDINGS (
    PRODUCT_ID     NUMBER,
    PRODUCT_NAME   VARCHAR(1000),
    BRAND          VARCHAR(100),
    EXTRACTED_MODEL VARCHAR(100),
    CLEAN_PRICE    FLOAT,
    EMBEDDING_TEXT VARCHAR(6000),
    EMBEDDING      VECTOR(FLOAT, 768),
    EMBEDDED_AT    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Cortex Arctic embeddings for Abt product catalog';

CREATE OR REPLACE TABLE BUY_EMBEDDINGS (
    PRODUCT_ID     NUMBER,
    PRODUCT_NAME   VARCHAR(1000),
    BRAND          VARCHAR(100),
    EXTRACTED_MODEL VARCHAR(100),
    CLEAN_PRICE    FLOAT,
    EMBEDDING_TEXT VARCHAR(6000),
    EMBEDDING      VECTOR(FLOAT, 768),
    EMBEDDED_AT    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Cortex Arctic embeddings for Buy.com product catalog';

-- ============================================================================
-- 8. STORED PROCEDURE: Generate Embeddings
-- ============================================================================
CREATE OR REPLACE PROCEDURE GENERATE_EMBEDDINGS()
    RETURNS VARCHAR
    LANGUAGE SQL
    EXECUTE AS CALLER
    COMMENT = 'Generate Cortex Arctic embeddings for all products in both catalogs'
AS
BEGIN
    -- Abt embeddings
    MERGE INTO RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.ABT_EMBEDDINGS tgt
    USING (
        SELECT
            ID AS PRODUCT_ID,
            NAME AS PRODUCT_NAME,
            BRAND,
            EXTRACTED_MODEL,
            CLEAN_PRICE,
            EMBEDDING_TEXT,
            SNOWFLAKE.CORTEX.EMBED_TEXT_768('snowflake-arctic-embed-m', LEFT(EMBEDDING_TEXT, 512))::VECTOR(FLOAT, 768) AS EMBEDDING
        FROM RETAIL_INTELLIGENCE_V2_DB.CORE.DT_CLEAN_ABT_CATALOG
    ) src
    ON tgt.PRODUCT_ID = src.PRODUCT_ID
    WHEN NOT MATCHED THEN INSERT (PRODUCT_ID, PRODUCT_NAME, BRAND, EXTRACTED_MODEL, CLEAN_PRICE, EMBEDDING_TEXT, EMBEDDING)
        VALUES (src.PRODUCT_ID, src.PRODUCT_NAME, src.BRAND, src.EXTRACTED_MODEL, src.CLEAN_PRICE, src.EMBEDDING_TEXT, src.EMBEDDING);

    -- Buy embeddings
    MERGE INTO RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.BUY_EMBEDDINGS tgt
    USING (
        SELECT
            ID AS PRODUCT_ID,
            NAME AS PRODUCT_NAME,
            BRAND,
            EXTRACTED_MODEL,
            CLEAN_PRICE,
            EMBEDDING_TEXT,
            SNOWFLAKE.CORTEX.EMBED_TEXT_768('snowflake-arctic-embed-m', LEFT(EMBEDDING_TEXT, 512))::VECTOR(FLOAT, 768) AS EMBEDDING
        FROM RETAIL_INTELLIGENCE_V2_DB.CORE.DT_CLEAN_BUY_CATALOG
    ) src
    ON tgt.PRODUCT_ID = src.PRODUCT_ID
    WHEN NOT MATCHED THEN INSERT (PRODUCT_ID, PRODUCT_NAME, BRAND, EXTRACTED_MODEL, CLEAN_PRICE, EMBEDDING_TEXT, EMBEDDING)
        VALUES (src.PRODUCT_ID, src.PRODUCT_NAME, src.BRAND, src.EXTRACTED_MODEL, src.CLEAN_PRICE, src.EMBEDDING_TEXT, src.EMBEDDING);

    RETURN 'Embeddings generated for ABT (' || (SELECT COUNT(*) FROM RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.ABT_EMBEDDINGS) || ') and BUY (' || (SELECT COUNT(*) FROM RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.BUY_EMBEDDINGS) || ') products';
END;

-- ============================================================================
-- 9. TASK: Scheduled embedding refresh (triggered by stream or scheduled)
-- ============================================================================
USE SCHEMA CORTEX_AI;

CREATE OR REPLACE TASK TASK_REFRESH_EMBEDDINGS
    WAREHOUSE = RETAIL_AI_V2_WH
    SCHEDULE = '60 MINUTE'
    COMMENT = 'Periodically regenerate embeddings for new products'
    WHEN SYSTEM$STREAM_HAS_DATA('RETAIL_INTELLIGENCE_V2_DB.CORE.STREAM_ABT_CHANGES')
         OR SYSTEM$STREAM_HAS_DATA('RETAIL_INTELLIGENCE_V2_DB.CORE.STREAM_BUY_CHANGES')
AS
    CALL RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.GENERATE_EMBEDDINGS();

-- Resume the task so it is active
ALTER TASK TASK_REFRESH_EMBEDDINGS RESUME;

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================
-- SELECT COUNT(*) FROM RETAIL_INTELLIGENCE_V2_DB.CORE.RAW_ABT_CATALOG;       -- expect 1070
-- SELECT COUNT(*) FROM RETAIL_INTELLIGENCE_V2_DB.CORE.RAW_BUY_CATALOG;       -- expect 1092
-- SELECT COUNT(*) FROM RETAIL_INTELLIGENCE_V2_DB.CORE.GROUND_TRUTH_MAPPING;   -- expect 1097
-- SELECT * FROM RETAIL_INTELLIGENCE_V2_DB.CORE.DT_CLEAN_ABT_CATALOG LIMIT 5;
-- SELECT * FROM RETAIL_INTELLIGENCE_V2_DB.CORE.DT_CLEAN_BUY_CATALOG LIMIT 5;

-- ============================================================================
-- OMNIMATCH AI v2: RETAIL INTELLIGENCE PLATFORM (REDESIGNED)
-- File 03: Dynamic Pricing Engine + Market Intelligence Views
-- ============================================================================
-- Prerequisites: Run 01_foundation.sql, 02_cortex_ai_pipeline.sql,
--                and execute GENERATE_EMBEDDINGS() + EXECUTE_ENTITY_RESOLUTION()
-- ============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE RETAIL_AI_V2_WH;
USE DATABASE RETAIL_INTELLIGENCE_V2_DB;
USE SCHEMA ANALYTICS;

-- ============================================================================
-- 1. PRICING STRATEGY CONFIGURATION
-- ============================================================================
CREATE OR REPLACE TABLE PRICING_STRATEGY_CONFIG (
    STRATEGY_ID     VARCHAR(50) PRIMARY KEY,
    STRATEGY_NAME   VARCHAR(100),
    DESCRIPTION     VARCHAR(500),
    UNDERCUT_PCT    FLOAT,
    MIN_MARGIN_PCT  FLOAT,
    MAX_DISCOUNT_PCT FLOAT,
    PREMIUM_PCT     FLOAT,
    ELASTICITY_COEFF FLOAT DEFAULT -1.65,
    IS_ACTIVE       BOOLEAN DEFAULT TRUE
) COMMENT = 'Configurable dynamic pricing strategies with guardrails';

INSERT INTO PRICING_STRATEGY_CONFIG VALUES
    ('AGGRESSIVE_UNDERCUT', 'Aggressive Undercut',
     'Beat competitor by 2.5% while respecting 10% minimum margin floor',
     2.5, 10.0, 25.0, 0.0, -1.65, TRUE),
    ('PRICE_MATCHER', 'Price Matcher',
     'Match exact competitor price with 12% margin floor',
     0.0, 12.0, 20.0, 0.0, -1.65, TRUE),
    ('MARGIN_MAXIMIZER', 'Margin Maximizer',
     'Optimize for high gross margin; price at premium when competitor is uncompetitive',
     1.0, 18.0, 15.0, 4.0, -1.65, TRUE),
    ('BRAND_PROTECT', 'MAP & Brand Protect',
     'Maintain manufacturer advertised price corridors (+/- 0.5%)',
     0.5, 20.0, 10.0, 0.0, -1.65, TRUE);

-- ============================================================================
-- 2. COMPETITIVE PRICE INDEX VIEW
-- ============================================================================
CREATE OR REPLACE VIEW V_COMPETITIVE_PRICE_INDEX
    COMMENT = 'Competitive pricing analysis for all matched products'
AS
SELECT
    m.MATCH_ID,
    m.ABT_ID,
    m.BUY_ID,
    m.ABT_NAME,
    m.BUY_NAME,
    m.ABT_BRAND,
    m.ABT_PRICE,
    m.BUY_PRICE,
    m.PRICE_DIFFERENCE,
    m.PRICE_GAP_PCT,
    m.COMPOSITE_SCORE,
    m.MATCH_STRATEGY,
    m.LLM_VERIFICATION,
    -- Cost estimation (70% of reference price)
    ROUND(COALESCE(m.ABT_PRICE, m.BUY_PRICE) * 0.70, 2) AS ESTIMATED_UNIT_COST,
    -- Current margin
    CASE WHEN m.ABT_PRICE > 0
         THEN ROUND(((m.ABT_PRICE - (COALESCE(m.ABT_PRICE, m.BUY_PRICE) * 0.70)) / m.ABT_PRICE) * 100, 2)
         ELSE NULL END AS CURRENT_MARGIN_PCT,
    -- Competitive status
    CASE
        WHEN m.ABT_PRICE IS NULL OR m.BUY_PRICE IS NULL THEN 'PRICE_UNAVAILABLE'
        WHEN m.ABT_PRICE < m.BUY_PRICE THEN 'ABT_WINNING'
        WHEN m.ABT_PRICE > m.BUY_PRICE THEN 'BUY_WINNING'
        ELSE 'PRICE_PARITY'
    END AS COMPETITIVE_STATUS
FROM RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES m;

-- ============================================================================
-- 3. PRICING RECOMMENDATIONS TABLE + PROCEDURE
-- ============================================================================
CREATE OR REPLACE TABLE PRICING_RECOMMENDATIONS (
    RECOMMENDATION_ID   VARCHAR(64),
    MATCH_ID            VARCHAR(64),
    STRATEGY_ID         VARCHAR(50),
    ABT_ID              NUMBER,
    PRODUCT_NAME        VARCHAR(1000),
    BRAND               VARCHAR(100),
    CURRENT_PRICE       FLOAT,
    COMPETITOR_PRICE    FLOAT,
    UNIT_COST           FLOAT,
    CURRENT_MARGIN_PCT  FLOAT,
    COMPETITIVE_STATUS  VARCHAR(50),
    RECOMMENDED_PRICE   FLOAT,
    PRICE_CHANGE_PCT    FLOAT,
    NEW_MARGIN_PCT      FLOAT,
    DEMAND_UPLIFT_PCT   FLOAT,
    MONTHLY_PROFIT_IMPACT FLOAT,
    ACTION_TYPE         VARCHAR(100),
    GENERATED_AT        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'AI-generated dynamic pricing recommendations with elasticity modeling';

CREATE OR REPLACE PROCEDURE GENERATE_PRICING_RECOMMENDATIONS(STRATEGY_ID_PARAM VARCHAR)
    RETURNS VARCHAR
    LANGUAGE SQL
    EXECUTE AS CALLER
    COMMENT = 'Generate dynamic pricing recommendations for all matched products using specified strategy'
AS
BEGIN
    DELETE FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.PRICING_RECOMMENDATIONS
    WHERE STRATEGY_ID = :STRATEGY_ID_PARAM;

    INSERT INTO RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.PRICING_RECOMMENDATIONS (
        RECOMMENDATION_ID, MATCH_ID, STRATEGY_ID, ABT_ID, PRODUCT_NAME, BRAND,
        CURRENT_PRICE, COMPETITOR_PRICE, UNIT_COST, CURRENT_MARGIN_PCT,
        COMPETITIVE_STATUS, RECOMMENDED_PRICE, PRICE_CHANGE_PCT,
        NEW_MARGIN_PCT, DEMAND_UPLIFT_PCT, MONTHLY_PROFIT_IMPACT, ACTION_TYPE
    )
    SELECT
        MD5(cpi.MATCH_ID || '-' || s.STRATEGY_ID) AS RECOMMENDATION_ID,
        cpi.MATCH_ID,
        s.STRATEGY_ID,
        cpi.ABT_ID,
        cpi.ABT_NAME AS PRODUCT_NAME,
        cpi.ABT_BRAND AS BRAND,
        cpi.ABT_PRICE AS CURRENT_PRICE,
        cpi.BUY_PRICE AS COMPETITOR_PRICE,
        cpi.ESTIMATED_UNIT_COST AS UNIT_COST,
        cpi.CURRENT_MARGIN_PCT,
        cpi.COMPETITIVE_STATUS,
        -- Recommended price calculation with guardrails
        ROUND(
            GREATEST(
                -- Floor: unit cost + minimum margin
                cpi.ESTIMATED_UNIT_COST * (1.0 + (s.MIN_MARGIN_PCT / 100.0)),
                -- Floor: max discount from current price
                COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE) * (1.0 - (s.MAX_DISCOUNT_PCT / 100.0)),
                -- Target: competitor price minus undercut
                CASE WHEN cpi.BUY_PRICE > 0
                     THEN cpi.BUY_PRICE * (1.0 - (s.UNDERCUT_PCT / 100.0))
                     ELSE COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE) * (1.0 + (s.PREMIUM_PCT / 100.0))
                END
            ), 2
        ) AS RECOMMENDED_PRICE,
        -- Price change percentage
        ROUND(
            ((GREATEST(
                cpi.ESTIMATED_UNIT_COST * (1.0 + (s.MIN_MARGIN_PCT / 100.0)),
                COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE) * (1.0 - (s.MAX_DISCOUNT_PCT / 100.0)),
                CASE WHEN cpi.BUY_PRICE > 0
                     THEN cpi.BUY_PRICE * (1.0 - (s.UNDERCUT_PCT / 100.0))
                     ELSE COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE) * (1.0 + (s.PREMIUM_PCT / 100.0))
                END
            ) - COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE))
            / NULLIF(COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE), 0)) * 100, 2
        ) AS PRICE_CHANGE_PCT,
        -- New margin after repricing
        ROUND(
            ((GREATEST(
                cpi.ESTIMATED_UNIT_COST * (1.0 + (s.MIN_MARGIN_PCT / 100.0)),
                COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE) * (1.0 - (s.MAX_DISCOUNT_PCT / 100.0)),
                CASE WHEN cpi.BUY_PRICE > 0
                     THEN cpi.BUY_PRICE * (1.0 - (s.UNDERCUT_PCT / 100.0))
                     ELSE COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE) * (1.0 + (s.PREMIUM_PCT / 100.0))
                END
            ) - cpi.ESTIMATED_UNIT_COST)
            / NULLIF(GREATEST(
                cpi.ESTIMATED_UNIT_COST * (1.0 + (s.MIN_MARGIN_PCT / 100.0)),
                COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE) * (1.0 - (s.MAX_DISCOUNT_PCT / 100.0)),
                CASE WHEN cpi.BUY_PRICE > 0
                     THEN cpi.BUY_PRICE * (1.0 - (s.UNDERCUT_PCT / 100.0))
                     ELSE COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE) * (1.0 + (s.PREMIUM_PCT / 100.0))
                END
            ), 0)) * 100, 2
        ) AS NEW_MARGIN_PCT,
        -- Demand elasticity uplift
        ROUND(-1.0 * s.ELASTICITY_COEFF *
            (((GREATEST(
                cpi.ESTIMATED_UNIT_COST * (1.0 + (s.MIN_MARGIN_PCT / 100.0)),
                COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE) * (1.0 - (s.MAX_DISCOUNT_PCT / 100.0)),
                CASE WHEN cpi.BUY_PRICE > 0
                     THEN cpi.BUY_PRICE * (1.0 - (s.UNDERCUT_PCT / 100.0))
                     ELSE COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE) * (1.0 + (s.PREMIUM_PCT / 100.0))
                END
            ) - COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE))
            / NULLIF(COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE), 0)), 2
        ) AS DEMAND_UPLIFT_PCT,
        -- Monthly profit impact (base 30 units/month)
        ROUND(
            (30 * (1.0 + (-1.0 * s.ELASTICITY_COEFF *
                (((GREATEST(
                    cpi.ESTIMATED_UNIT_COST * (1.0 + (s.MIN_MARGIN_PCT / 100.0)),
                    COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE) * (1.0 - (s.MAX_DISCOUNT_PCT / 100.0)),
                    CASE WHEN cpi.BUY_PRICE > 0
                         THEN cpi.BUY_PRICE * (1.0 - (s.UNDERCUT_PCT / 100.0))
                         ELSE COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE) * (1.0 + (s.PREMIUM_PCT / 100.0))
                    END
                ) - COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE))
                / NULLIF(COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE), 0))))
            ) *
            (GREATEST(
                cpi.ESTIMATED_UNIT_COST * (1.0 + (s.MIN_MARGIN_PCT / 100.0)),
                COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE) * (1.0 - (s.MAX_DISCOUNT_PCT / 100.0)),
                CASE WHEN cpi.BUY_PRICE > 0
                     THEN cpi.BUY_PRICE * (1.0 - (s.UNDERCUT_PCT / 100.0))
                     ELSE COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE) * (1.0 + (s.PREMIUM_PCT / 100.0))
                END
            ) - cpi.ESTIMATED_UNIT_COST)
            -
            (30 * (COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE) - cpi.ESTIMATED_UNIT_COST))
        , 2) AS MONTHLY_PROFIT_IMPACT,
        -- Action type
        CASE
            WHEN cpi.COMPETITIVE_STATUS = 'BUY_WINNING' THEN 'Re-price to Win'
            WHEN cpi.COMPETITIVE_STATUS = 'ABT_WINNING' THEN 'Margin Expansion'
            WHEN cpi.COMPETITIVE_STATUS = 'PRICE_PARITY' THEN 'Maintain Parity'
            ELSE 'Set Catalog Price'
        END AS ACTION_TYPE
    FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.V_COMPETITIVE_PRICE_INDEX cpi
    CROSS JOIN RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.PRICING_STRATEGY_CONFIG s
    WHERE s.STRATEGY_ID = :STRATEGY_ID_PARAM
      AND s.IS_ACTIVE = TRUE
      AND COALESCE(cpi.ABT_PRICE, cpi.BUY_PRICE) > 0;

    RETURN 'Pricing recommendations generated: ' ||
           (SELECT COUNT(*) FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.PRICING_RECOMMENDATIONS
            WHERE STRATEGY_ID = :STRATEGY_ID_PARAM) || ' for strategy ' || :STRATEGY_ID_PARAM;
END;

-- ============================================================================
-- 4. MARKET INTELLIGENCE VIEW
-- ============================================================================
CREATE OR REPLACE VIEW V_MARKET_INTELLIGENCE
    COMMENT = 'Brand-level competitive market intelligence summary'
AS
SELECT
    ABT_BRAND AS BRAND,
    COUNT(*) AS MATCHED_SKUS,
    ROUND(AVG(COMPOSITE_SCORE) * 100, 1) AS AVG_CONFIDENCE,
    ROUND(AVG(CASE WHEN ABT_PRICE > 0 THEN ABT_PRICE END), 2) AS AVG_ABT_PRICE,
    ROUND(AVG(CASE WHEN BUY_PRICE > 0 THEN BUY_PRICE END), 2) AS AVG_BUY_PRICE,
    ROUND(AVG(PRICE_GAP_PCT), 2) AS AVG_PRICE_GAP_PCT,
    COUNT(CASE WHEN ABT_PRICE < BUY_PRICE THEN 1 END) AS ABT_WINNING,
    COUNT(CASE WHEN ABT_PRICE > BUY_PRICE THEN 1 END) AS BUY_WINNING,
    COUNT(CASE WHEN ABT_PRICE = BUY_PRICE THEN 1 END) AS PRICE_PARITY,
    -- Competitiveness index: -100 (always losing) to +100 (always winning)
    ROUND(
        ((COUNT(CASE WHEN ABT_PRICE < BUY_PRICE THEN 1 END) -
          COUNT(CASE WHEN ABT_PRICE > BUY_PRICE THEN 1 END))::FLOAT /
         NULLIF(COUNT(CASE WHEN ABT_PRICE IS NOT NULL AND BUY_PRICE IS NOT NULL THEN 1 END), 0))
        * 100, 1
    ) AS COMPETITIVENESS_INDEX,
    -- Match quality
    COUNT(CASE WHEN LLM_VERIFICATION = 'CONFIRMED' THEN 1 END) AS LLM_CONFIRMED_COUNT,
    COUNT(CASE WHEN MATCH_STRATEGY = 'EXACT_MODEL_MATCH' THEN 1 END) AS EXACT_MODEL_MATCHES
FROM RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES
GROUP BY ABT_BRAND
HAVING ABT_BRAND != 'Other' OR COUNT(*) <= 50;

-- ============================================================================
-- 5. MARKET ANOMALIES VIEW
-- ============================================================================
CREATE OR REPLACE VIEW V_MARKET_ANOMALIES
    COMMENT = 'Critical pricing anomalies requiring immediate attention'
AS
-- Severe competitor undercuts (>25% cheaper)
SELECT
    'CRITICAL_UNDERCUT' AS ANOMALY_TYPE,
    'HIGH' AS SEVERITY,
    ABT_BRAND AS BRAND,
    ABT_NAME AS PRODUCT_NAME,
    ABT_PRICE,
    BUY_PRICE,
    PRICE_GAP_PCT,
    'Competitor is ' || ROUND(PRICE_GAP_PCT, 1) || '% cheaper — risk of significant sales loss' AS DESCRIPTION,
    'Execute automated markdown with margin floor' AS RECOMMENDED_ACTION
FROM RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES
WHERE PRICE_GAP_PCT > 25.0
  AND ABT_PRICE IS NOT NULL AND BUY_PRICE IS NOT NULL

UNION ALL

-- Margin expansion opportunities (Abt >20% cheaper)
SELECT
    'MARGIN_OPPORTUNITY' AS ANOMALY_TYPE,
    'MEDIUM' AS SEVERITY,
    ABT_BRAND AS BRAND,
    ABT_NAME AS PRODUCT_NAME,
    ABT_PRICE,
    BUY_PRICE,
    PRICE_GAP_PCT,
    'Abt is ' || ROUND(ABS(PRICE_GAP_PCT), 1) || '% below market — opportunity to raise price' AS DESCRIPTION,
    'Increase price incrementally to capture additional margin' AS RECOMMENDED_ACTION
FROM RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES
WHERE PRICE_GAP_PCT < -20.0
  AND ABT_PRICE IS NOT NULL AND BUY_PRICE IS NOT NULL;

-- ============================================================================
-- EXECUTION:
-- CALL RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.GENERATE_PRICING_RECOMMENDATIONS('AGGRESSIVE_UNDERCUT');
-- CALL RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.GENERATE_PRICING_RECOMMENDATIONS('PRICE_MATCHER');
-- CALL RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.GENERATE_PRICING_RECOMMENDATIONS('MARGIN_MAXIMIZER');
-- CALL RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.GENERATE_PRICING_RECOMMENDATIONS('BRAND_PROTECT');
-- ============================================================================

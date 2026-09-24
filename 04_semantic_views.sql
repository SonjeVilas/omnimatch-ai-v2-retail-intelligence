-- ============================================================================
-- OMNIMATCH AI v2: RETAIL INTELLIGENCE PLATFORM (REDESIGNED)
-- File 04: Semantic Views — 3 views for 3 Cortex Agents
-- ============================================================================
-- Prerequisites: Run files 01-03 and execute pipeline procedures
-- ============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE RETAIL_AI_V2_WH;
USE DATABASE RETAIL_INTELLIGENCE_V2_DB;

-- Grant semantic view creation
GRANT CREATE SEMANTIC VIEW ON SCHEMA CORTEX_AI TO ROLE ACCOUNTADMIN;
GRANT CREATE SEMANTIC VIEW ON SCHEMA ANALYTICS TO ROLE ACCOUNTADMIN;

-- ============================================================================
-- SEMANTIC VIEW 1: Product Matching (for PRODUCT_MATCHING_AGENT)
-- ============================================================================
USE SCHEMA CORTEX_AI;

CREATE OR REPLACE SEMANTIC VIEW SV_PRODUCT_MATCHING

    TABLES (
        matches AS RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES
            PRIMARY KEY (MATCH_ID)
            WITH SYNONYMS ('product matches', 'matched products', 'entity resolution results')
            COMMENT = 'AI-resolved product matches between Abt and Buy.com catalogs',

        ground_truth AS RETAIL_INTELLIGENCE_V2_DB.CORE.GROUND_TRUTH_MAPPING
            PRIMARY KEY (ID_ABT, ID_BUY)
            COMMENT = 'Expert-validated true product match pairs'
    )

    RELATIONSHIPS (
        matches_to_ground_truth AS
            matches (ABT_ID, BUY_ID) REFERENCES ground_truth (ID_ABT, ID_BUY)
    )

    FACTS (
        matches.vector_sim AS VECTOR_SCORE
            COMMENT = 'Cortex Arctic vector cosine similarity score (0-1)',
        matches.token_sim AS TOKEN_SCORE
            COMMENT = 'Jaccard token overlap similarity score (0-1)',
        matches.model_sim AS MODEL_SCORE
            COMMENT = 'Model/SKU number Levenshtein similarity score (0-1)',
        matches.brand_sim AS BRAND_SCORE
            COMMENT = 'Brand alignment score (0 or 1)',
        matches.confidence AS COMPOSITE_SCORE
            COMMENT = 'Weighted composite match confidence score (0-1)',
        matches.price_diff AS PRICE_DIFFERENCE
            COMMENT = 'Price difference in dollars (Abt minus Buy)',
        matches.price_gap AS PRICE_GAP_PCT
            COMMENT = 'Price gap as percentage'
    )

    DIMENSIONS (
        matches.abt_product AS ABT_NAME
            WITH SYNONYMS = ('abt product', 'abt item', 'our product')
            COMMENT = 'Product name from Abt Electronics catalog',
        matches.buy_product AS BUY_NAME
            WITH SYNONYMS = ('buy product', 'competitor product', 'buy.com product')
            COMMENT = 'Product name from Buy.com catalog',
        matches.abt_brand AS ABT_BRAND
            WITH SYNONYMS = ('brand', 'manufacturer', 'product brand')
            COMMENT = 'Standardized brand name extracted from Abt product',
        matches.buy_brand AS BUY_BRAND
            COMMENT = 'Standardized brand name from Buy.com product',
        matches.strategy AS MATCH_STRATEGY
            WITH SYNONYMS = ('matching strategy', 'match method', 'resolution strategy')
            COMMENT = 'Primary strategy that drove the match: EXACT_MODEL_MATCH, CORTEX_VECTOR_SEMANTIC, TOKEN_FUZZY_MATCH, or HYBRID_ENSEMBLE',
        matches.verification AS LLM_VERIFICATION
            WITH SYNONYMS = ('llm status', 'verification status', 'confirmed')
            COMMENT = 'LLM verification status: CONFIRMED, REJECTED, UNCERTAIN, or PENDING',
        matches.high_confidence AS IS_HIGH_CONFIDENCE
            COMMENT = 'Whether the match is high confidence (score >= 0.75)',
        matches.match_time AS RESOLVED_AT
            COMMENT = 'Timestamp when the match was resolved'
    )

    METRICS (
        matches.total_matches AS COUNT(MATCH_ID)
            WITH SYNONYMS = ('match count', 'number of matches', 'how many matches')
            COMMENT = 'Total number of product matches',
        matches.avg_confidence AS AVG(matches.confidence)
            WITH SYNONYMS = ('average confidence', 'mean confidence')
            COMMENT = 'Average composite confidence score across matches',
        matches.high_confidence_count AS COUNT_IF(IS_HIGH_CONFIDENCE = TRUE)
            COMMENT = 'Number of high-confidence matches (score >= 0.75)',
        matches.confirmed_count AS COUNT_IF(LLM_VERIFICATION = 'CONFIRMED')
            COMMENT = 'Number of LLM-confirmed matches',
        matches.avg_vector_score AS AVG(matches.vector_sim)
            COMMENT = 'Average Cortex vector similarity score',
        matches.avg_price_gap AS AVG(matches.price_gap)
            WITH SYNONYMS = ('average price difference', 'mean price gap')
            COMMENT = 'Average price gap percentage across matched products'
    )

    AI_SQL_GENERATION 'When asked about matches, always include the brand dimension. When asked about accuracy or quality, focus on confidence scores and LLM verification status. Price gap is calculated as (Abt price - Buy price) / Buy price * 100, so positive means Abt is more expensive.'

    AI_VERIFIED_QUERIES (
        vq_matches_by_brand AS (
            QUESTION 'How many matches per brand?'
            SQL 'SELECT matches.abt_brand, COUNT(matches.match_id) AS total_matches FROM RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES AS matches GROUP BY matches.abt_brand ORDER BY total_matches DESC'
        ),
        vq_strategy_distribution AS (
            QUESTION 'What is the match strategy distribution?'
            SQL 'SELECT matches.match_strategy, COUNT(matches.match_id) AS total_matches, AVG(matches.composite_score) AS avg_confidence FROM RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES AS matches GROUP BY matches.match_strategy ORDER BY total_matches DESC'
        ),
        vq_top_confident AS (
            QUESTION 'Show me the top 10 most confident matches'
            SQL 'SELECT matches.abt_name, matches.buy_name, matches.abt_brand, matches.composite_score, matches.match_strategy, matches.llm_verification FROM RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES AS matches ORDER BY matches.composite_score DESC LIMIT 10'
        )
    )

    COMMENT = 'Semantic view for product entity resolution analysis — powers the Product Matching Agent';


-- ============================================================================
-- SEMANTIC VIEW 2: Pricing Intelligence (for PRICE_OPTIMIZATION_AGENT)
-- ============================================================================
USE SCHEMA ANALYTICS;

CREATE OR REPLACE SEMANTIC VIEW SV_PRICING_INTELLIGENCE

    TABLES (
        recommendations AS RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.PRICING_RECOMMENDATIONS
            PRIMARY KEY (RECOMMENDATION_ID)
            WITH SYNONYMS ('pricing recommendations', 'price recommendations', 'repricing')
            COMMENT = 'AI-generated dynamic pricing recommendations with elasticity modeling',

        strategies AS RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.PRICING_STRATEGY_CONFIG
            PRIMARY KEY (STRATEGY_ID)
            COMMENT = 'Configurable pricing strategy presets'
    )

    RELATIONSHIPS (
        recommendations_to_strategies AS
            recommendations (STRATEGY_ID) REFERENCES strategies
    )

    FACTS (
        recommendations.current AS CURRENT_PRICE
            COMMENT = 'Current Abt Electronics price',
        recommendations.competitor AS COMPETITOR_PRICE
            COMMENT = 'Buy.com competitor price',
        recommendations.cost AS UNIT_COST
            COMMENT = 'Estimated unit cost (70% of reference price)',
        recommendations.curr_margin AS CURRENT_MARGIN_PCT
            COMMENT = 'Current gross margin percentage',
        recommendations.rec_price AS RECOMMENDED_PRICE
            COMMENT = 'AI-recommended optimized price',
        recommendations.price_chg AS PRICE_CHANGE_PCT
            COMMENT = 'Recommended price change as percentage',
        recommendations.new_margin AS NEW_MARGIN_PCT
            COMMENT = 'Projected margin after repricing',
        recommendations.demand AS DEMAND_UPLIFT_PCT
            COMMENT = 'Projected demand uplift from price elasticity',
        recommendations.profit AS MONTHLY_PROFIT_IMPACT
            COMMENT = 'Estimated 30-day profit impact in dollars'
    )

    DIMENSIONS (
        recommendations.product AS PRODUCT_NAME
            WITH SYNONYMS = ('product', 'item', 'sku')
            COMMENT = 'Product name',
        recommendations.brand AS BRAND
            WITH SYNONYMS = ('manufacturer', 'brand name')
            COMMENT = 'Product brand',
        recommendations.comp_status AS COMPETITIVE_STATUS
            WITH SYNONYMS = ('competitive position', 'price position', 'winning or losing')
            COMMENT = 'Competitive pricing status: ABT_WINNING, BUY_WINNING, PRICE_PARITY, or PRICE_UNAVAILABLE',
        recommendations.action AS ACTION_TYPE
            WITH SYNONYMS = ('recommended action', 'what to do', 'pricing action')
            COMMENT = 'Recommended pricing action type',
        recommendations.strategy AS STRATEGY_ID
            COMMENT = 'Pricing strategy identifier',
        strategies.strategy_name AS STRATEGY_NAME
            WITH SYNONYMS = ('strategy', 'pricing strategy')
            COMMENT = 'Pricing strategy display name',
        recommendations.gen_time AS GENERATED_AT
            COMMENT = 'Timestamp when recommendation was generated'
    )

    METRICS (
        recommendations.total_recommendations AS COUNT(RECOMMENDATION_ID)
            WITH SYNONYMS = ('recommendation count', 'how many recommendations')
            COMMENT = 'Total number of pricing recommendations',
        recommendations.avg_price_change AS AVG(recommendations.price_chg)
            WITH SYNONYMS = ('average price change', 'mean adjustment')
            COMMENT = 'Average recommended price change percentage',
        recommendations.total_profit_opportunity AS SUM(recommendations.profit)
            WITH SYNONYMS = ('total profit', 'profit opportunity', 'total margin opportunity')
            COMMENT = 'Total projected 30-day profit impact across all products',
        recommendations.avg_margin AS AVG(recommendations.new_margin)
            COMMENT = 'Average projected margin after repricing',
        recommendations.avg_demand_uplift AS AVG(recommendations.demand)
            COMMENT = 'Average projected demand uplift percentage',
        recommendations.reprice_needed AS COUNT_IF(ACTION_TYPE = 'Re-price to Win')
            COMMENT = 'Number of products needing repricing to be competitive'
    )

    AI_SQL_GENERATION 'When asked about pricing, always include the strategy dimension. Profit impact is a 30-day projection based on elasticity modeling. Positive profit impact means the repricing increases profit; negative means it decreases profit but may win competitive position.'

    AI_VERIFIED_QUERIES (
        vq_profit_by_brand AS (
            QUESTION 'What is the total profit opportunity by brand?'
            SQL 'SELECT r.brand, SUM(r.monthly_profit_impact) AS total_profit, COUNT(*) AS product_count FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.PRICING_RECOMMENDATIONS AS r GROUP BY r.brand ORDER BY total_profit DESC'
        ),
        vq_reprice_needed AS (
            QUESTION 'Which products need repricing?'
            SQL 'SELECT r.product_name, r.brand, r.current_price, r.competitor_price, r.recommended_price, r.price_change_pct, r.monthly_profit_impact FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.PRICING_RECOMMENDATIONS AS r WHERE r.action_type = ''Re-price to Win'' ORDER BY ABS(r.price_change_pct) DESC LIMIT 20'
        )
    )

    COMMENT = 'Semantic view for dynamic pricing and margin optimization — powers the Price Optimization Agent';


-- ============================================================================
-- SEMANTIC VIEW 3: Market Intelligence (for MARKET_INTELLIGENCE_AGENT)
-- ============================================================================

CREATE OR REPLACE SEMANTIC VIEW SV_MARKET_INTELLIGENCE

    TABLES (
        market AS RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.V_MARKET_INTELLIGENCE
            PRIMARY KEY (BRAND)
            COMMENT = 'Brand-level competitive market intelligence aggregations',

        anomalies AS RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.V_MARKET_ANOMALIES
            COMMENT = 'Critical pricing anomalies and market alerts'
    )

    FACTS (
        market.sku_count AS MATCHED_SKUS
            COMMENT = 'Number of matched SKUs for the brand',
        market.avg_conf AS AVG_CONFIDENCE
            COMMENT = 'Average match confidence percentage',
        market.abt_avg AS AVG_ABT_PRICE
            COMMENT = 'Average Abt Electronics price for the brand',
        market.buy_avg AS AVG_BUY_PRICE
            COMMENT = 'Average Buy.com price for the brand',
        market.gap AS AVG_PRICE_GAP_PCT
            COMMENT = 'Average price gap percentage for the brand',
        market.abt_win AS ABT_WINNING
            COMMENT = 'Number of SKUs where Abt is cheaper',
        market.buy_win AS BUY_WINNING
            COMMENT = 'Number of SKUs where Buy.com is cheaper',
        market.comp_idx AS COMPETITIVENESS_INDEX
            COMMENT = 'Competitiveness index from -100 (always losing) to +100 (always winning)',
        anomalies.abt_price AS ANOMALY_ABT_PRICE
            COMMENT = 'Abt price in the anomaly',
        anomalies.buy_price AS ANOMALY_BUY_PRICE
            COMMENT = 'Buy.com price in the anomaly',
        anomalies.gap_pct AS ANOMALY_PRICE_GAP
            COMMENT = 'Price gap percentage in the anomaly'
    )

    DIMENSIONS (
        market.brand AS BRAND
            WITH SYNONYMS = ('brand name', 'manufacturer', 'company')
            COMMENT = 'Product brand name',
        anomalies.type AS ANOMALY_TYPE
            WITH SYNONYMS = ('alert type', 'anomaly category')
            COMMENT = 'Type of market anomaly: CRITICAL_UNDERCUT or MARGIN_OPPORTUNITY',
        anomalies.severity AS SEVERITY
            WITH SYNONYMS = ('alert severity', 'priority')
            COMMENT = 'Anomaly severity: HIGH or MEDIUM',
        anomalies.product AS ANOMALY_PRODUCT
            WITH SYNONYMS = ('affected product', 'anomaly product')
            COMMENT = 'Product affected by the anomaly',
        anomalies.description AS ANOMALY_DESCRIPTION
            COMMENT = 'Human-readable description of the anomaly',
        anomalies.action AS RECOMMENDED_ACTION
            COMMENT = 'Recommended action to address the anomaly'
    )

    METRICS (
        market.total_brands AS COUNT(market.brand)
            WITH SYNONYMS = ('brand count', 'number of brands')
            COMMENT = 'Total number of tracked brands',
        market.total_matched_skus AS SUM(market.sku_count)
            WITH SYNONYMS = ('total skus', 'total products matched')
            COMMENT = 'Total matched SKUs across all brands',
        market.avg_competitiveness AS AVG(market.comp_idx)
            WITH SYNONYMS = ('overall competitiveness', 'market position')
            COMMENT = 'Average competitiveness index across all brands',
        anomalies.total_anomalies AS COUNT(anomalies.type)
            WITH SYNONYMS = ('anomaly count', 'alert count', 'how many anomalies')
            COMMENT = 'Total number of active market anomalies',
        anomalies.critical_anomalies AS COUNT_IF(anomalies.severity = 'HIGH')
            COMMENT = 'Number of high-severity anomalies'
    )

    AI_SQL_GENERATION 'When asked about market trends or brand performance, query the market table. When asked about alerts, risks, or anomalies, query the anomalies table. Competitiveness index ranges from -100 (always losing on price) to +100 (always winning on price).'

    AI_VERIFIED_QUERIES (
        vq_brand_competitiveness AS (
            QUESTION 'Which brands are we most competitive on?'
            SQL 'SELECT brand, matched_skus, competitiveness_index, abt_winning, buy_winning, avg_price_gap_pct FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.V_MARKET_INTELLIGENCE ORDER BY competitiveness_index DESC'
        ),
        vq_critical_anomalies AS (
            QUESTION 'What are the critical market anomalies?'
            SQL 'SELECT anomaly_type, severity, brand, product_name, abt_price, buy_price, price_gap_pct, description, recommended_action FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.V_MARKET_ANOMALIES WHERE severity = ''HIGH'' ORDER BY price_gap_pct DESC'
        )
    )

    COMMENT = 'Semantic view for competitive market intelligence and trend detection — powers the Market Intelligence Agent';

"""
============================================================================
OMNIMATCH AI v2: RETAIL INTELLIGENCE PLATFORM
Streamlit Dashboard — Queries Snowflake Directly, Embeds 3 Cortex Agents
Snowflake x Capgemini Hackathon 2026 | Team MatchMatrix
============================================================================
"""

import streamlit as st
import pandas as pd
import numpy as np
import plotly.express as px
import plotly.graph_objects as go
import json
import time

# -- Snowflake Session --
from snowflake.snowpark.context import get_active_session
session = get_active_session()

# -- Page Config --
st.set_page_config(
    page_title="OmniMatch AI v2 | Retail Intelligence",
    page_icon="⚡",
    layout="wide",
    initial_sidebar_state="expanded"
)

# -- CSS --
st.markdown("""
<style>
@import url('https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&family=JetBrains+Mono:wght@400;500;600&display=swap');

.stApp {
    background: linear-gradient(150deg, #f8fafc 0%, #f1f5f9 60%, #e0f2fe 100%) !important;
    font-family: 'Plus Jakarta Sans', -apple-system, sans-serif !important;
}
[data-testid="stSidebar"] { background: #ffffff !important; border-right: 1px solid #e2e8f0 !important; }

.brand-header {
    background: linear-gradient(135deg, #ffffff 0%, #f0f9ff 60%, #e0f2fe 100%);
    border: 1px solid #bae6fd; border-radius: 16px;
    padding: 22px 28px; margin-bottom: 22px;
    box-shadow: 0 10px 25px -5px rgba(2,132,199,0.08);
}
.brand-badge {
    display: inline-block; padding: 4px 12px; border-radius: 20px;
    font-size: 0.76rem; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase;
    background: linear-gradient(90deg, #0284c7, #6366f1); color: #fff;
    box-shadow: 0 2px 8px rgba(2,132,199,0.25); margin-bottom: 8px;
}
.header-title {
    font-size: 2.1rem; font-weight: 800; letter-spacing: -0.025em;
    background: linear-gradient(90deg, #0f172a 20%, #0369a1 70%, #4338ca 100%);
    -webkit-background-clip: text; -webkit-text-fill-color: transparent; margin: 0;
}
.header-subtitle { font-size: 0.98rem; color: #475569; margin-top: 6px; font-weight: 500; }

.kpi-card {
    background: #fff; border: 1px solid #e2e8f0; border-radius: 14px;
    padding: 16px 18px; box-shadow: 0 4px 14px rgba(15,23,42,0.04);
    position: relative; overflow: hidden;
}
.kpi-card::before {
    content: ''; position: absolute; top: 0; left: 0; width: 4px; height: 100%;
    background: linear-gradient(180deg, #0284c7, #6366f1);
}
.kpi-title { font-size: 0.78rem; font-weight: 700; color: #64748b; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 4px; }
.kpi-value { font-size: 1.75rem; font-weight: 800; color: #0f172a; }
.kpi-sub { font-size: 0.78rem; color: #059669; font-weight: 600; margin-top: 2px; }

.stTabs [data-baseweb="tab-list"] { gap: 6px; background: #f1f5f9; padding: 6px; border-radius: 12px; border: 1px solid #e2e8f0; }
.stTabs [data-baseweb="tab"] { border-radius: 8px; padding: 8px 16px; font-weight: 600; color: #64748b; border: none !important; }
.stTabs [aria-selected="true"] { background: #fff !important; color: #0284c7 !important; font-weight: 700 !important; box-shadow: 0 2px 8px rgba(0,0,0,0.05) !important; }
</style>
""", unsafe_allow_html=True)


# ============================================================================
# DATA LOADING (all from Snowflake — no Python engine)
# ============================================================================
@st.cache_data(ttl=300, show_spinner="Loading match data from Snowflake...")
def load_matches():
    return session.sql("SELECT * FROM RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.FINAL_PRODUCT_MATCHES").to_pandas()

@st.cache_data(ttl=300, show_spinner="Loading benchmark metrics...")
def load_metrics():
    return session.sql("SELECT * FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.V_BENCHMARK_METRICS").to_pandas()

@st.cache_data(ttl=300, show_spinner="Loading pricing data...")
def load_pricing(strategy_id):
    return session.sql(f"""
        SELECT * FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.PRICING_RECOMMENDATIONS
        WHERE STRATEGY_ID = '{strategy_id}'
    """).to_pandas()

@st.cache_data(ttl=300, show_spinner="Loading market intelligence...")
def load_market_intel():
    return session.sql("SELECT * FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.V_MARKET_INTELLIGENCE").to_pandas()

@st.cache_data(ttl=300, show_spinner="Loading anomalies...")
def load_anomalies():
    return session.sql("SELECT * FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.V_MARKET_ANOMALIES").to_pandas()

@st.cache_data(ttl=300, show_spinner="Loading accuracy by strategy...")
def load_accuracy_strategy():
    return session.sql("SELECT * FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.V_ACCURACY_BY_STRATEGY").to_pandas()

@st.cache_data(ttl=300, show_spinner="Loading accuracy by brand...")
def load_accuracy_brand():
    return session.sql("SELECT * FROM RETAIL_INTELLIGENCE_V2_DB.ANALYTICS.V_ACCURACY_BY_BRAND").to_pandas()

matches_df = load_matches()
metrics_df = load_metrics()

# ============================================================================
# SIDEBAR
# ============================================================================
st.sidebar.markdown("""
<div style="padding: 10px 0; text-align: center;">
    <h2 style="margin: 0; color: #38bdf8; font-weight: 800;">⚡ OmniMatch AI v2</h2>
    <p style="margin: 2px 0 0 0; color: #94a3b8; font-size: 0.8rem;">Snowflake x Capgemini Hackathon</p>
</div>
""", unsafe_allow_html=True)
st.sidebar.markdown("---")

st.sidebar.subheader("🏷️ Pricing Strategy")
strategy_options = {
    'Aggressive Undercut': 'AGGRESSIVE_UNDERCUT',
    'Price Matcher': 'PRICE_MATCHER',
    'Margin Maximizer': 'MARGIN_MAXIMIZER',
    'MAP & Brand Protect': 'BRAND_PROTECT'
}
selected_strategy_name = st.sidebar.selectbox("Active Strategy", list(strategy_options.keys()))
selected_strategy_id = strategy_options[selected_strategy_name]

st.sidebar.markdown("---")
st.sidebar.subheader("🤖 Cortex Agents")
st.sidebar.caption("3 specialized agents available:")
st.sidebar.markdown("- **🔬 Product Matching** — Entity resolution")
st.sidebar.markdown("- **💰 Price Optimization** — Dynamic pricing")
st.sidebar.markdown("- **🌐 Market Intelligence** — Trend detection")
st.sidebar.markdown("---")
st.sidebar.caption("🚀 Powered by Snowflake Cortex AI")

# ============================================================================
# HEADER + KPIs
# ============================================================================
st.markdown("""
<div class="brand-header">
    <span class="brand-badge">🏆 Team MatchMatrix</span>
    <h1 class="header-title">OmniMatch AI v2: Retail Intelligence Platform</h1>
    <p class="header-subtitle">
        Enterprise AI-Powered Product Entity Resolution, Dynamic Pricing & Market Intelligence — Built on Snowflake Cortex
    </p>
</div>
""", unsafe_allow_html=True)

# KPIs
m = metrics_df.iloc[0] if not metrics_df.empty else {}
pricing_df = load_pricing(selected_strategy_id)
total_profit = pricing_df['MONTHLY_PROFIT_IMPACT'].sum() if not pricing_df.empty and 'MONTHLY_PROFIT_IMPACT' in pricing_df.columns else 0
anomalies_df = load_anomalies()

k1, k2, k3, k4, k5 = st.columns(5)
with k1:
    st.markdown(f"""<div class="kpi-card"><div class="kpi-title">Match Rate</div>
    <div class="kpi-value">{len(matches_df):,} <span style="font-size:1rem;color:#94a3b8">/ 1,070</span></div>
    <div class="kpi-sub">⚡ {round(len(matches_df)/1070*100,1)}% Matched</div></div>""", unsafe_allow_html=True)
with k2:
    prec = m.get('PRECISION_PCT', 0)
    st.markdown(f"""<div class="kpi-card"><div class="kpi-title">Precision</div>
    <div class="kpi-value" style="color:#38bdf8">{prec}%</div>
    <div class="kpi-sub">✓ TP: {m.get('TRUE_POSITIVES', 0)}</div></div>""", unsafe_allow_html=True)
with k3:
    f1 = m.get('F1_SCORE_PCT', 0)
    st.markdown(f"""<div class="kpi-card"><div class="kpi-title">F1 Score</div>
    <div class="kpi-value" style="color:#a855f7">{f1}%</div>
    <div class="kpi-sub">🎯 Recall: {m.get('RECALL_PCT', 0)}%</div></div>""", unsafe_allow_html=True)
with k4:
    st.markdown(f"""<div class="kpi-card"><div class="kpi-title">30-Day Profit Opp.</div>
    <div class="kpi-value" style="color:#10b981">${total_profit:,.0f}</div>
    <div class="kpi-sub">📈 {selected_strategy_name}</div></div>""", unsafe_allow_html=True)
with k5:
    st.markdown(f"""<div class="kpi-card"><div class="kpi-title">Market Alerts</div>
    <div class="kpi-value" style="color:#f59e0b">{len(anomalies_df)}</div>
    <div class="kpi-sub">⚠️ Active Anomalies</div></div>""", unsafe_allow_html=True)

st.markdown("<div style='margin-top:15px'></div>", unsafe_allow_html=True)

# ============================================================================
# TABS
# ============================================================================
tab_exec, tab_matches, tab_bench, tab_pricing, tab_market, tab_agents, tab_arch = st.tabs([
    "📊 Executive Overview",
    "🔬 Entity Resolution Studio",
    "🎯 Benchmark & Accuracy",
    "💰 Dynamic Pricing Engine",
    "🌐 Market Intelligence",
    "🤖 Cortex Agent Chat",
    "⚡ Architecture & Snowflake Features"
])

# ============================================================================
# TAB 1: EXECUTIVE OVERVIEW
# ============================================================================
with tab_exec:
    st.markdown("### 📈 Executive Performance Dashboard")
    c1, c2 = st.columns(2)
    with c1:
        st.markdown("#### ⚔️ Competitive Win/Loss Distribution")
        if not pricing_df.empty and 'COMPETITIVE_STATUS' in pricing_df.columns:
            status_counts = pricing_df['COMPETITIVE_STATUS'].value_counts().reset_index()
            status_counts.columns = ['Status', 'Count']
            fig = px.pie(status_counts, values='Count', names='Status', hole=0.45,
                         color_discrete_sequence=['#10b981', '#f43f5e', '#38bdf8', '#64748b'])
            fig.update_layout(paper_bgcolor='rgba(0,0,0,0)', plot_bgcolor='rgba(0,0,0,0)',
                              font=dict(family='Plus Jakarta Sans'), margin=dict(t=20,b=20,l=20,r=20))
            st.plotly_chart(fig, use_container_width=True)
    with c2:
        st.markdown("#### 🧩 Match Strategy Breakdown")
        strat_counts = matches_df['MATCH_STRATEGY'].value_counts().reset_index()
        strat_counts.columns = ['Strategy', 'Count']
        fig2 = px.bar(strat_counts, x='Count', y='Strategy', orientation='h', text='Count',
                      color_discrete_sequence=['#6366f1', '#38bdf8', '#06b6d4', '#8b5cf6'])
        fig2.update_layout(paper_bgcolor='rgba(0,0,0,0)', plot_bgcolor='rgba(0,0,0,0)',
                           showlegend=False, margin=dict(t=20,b=20,l=20,r=20))
        st.plotly_chart(fig2, use_container_width=True)

    st.markdown("---")
    st.markdown("#### 🏢 Brand Coverage & Price Comparison")
    market_df = load_market_intel()
    if not market_df.empty:
        top = market_df.head(12)
        fig3 = go.Figure()
        fig3.add_trace(go.Bar(name='Abt Avg Price', x=top['BRAND'], y=top['AVG_ABT_PRICE'], marker_color='#38bdf8'))
        fig3.add_trace(go.Bar(name='Buy.com Avg Price', x=top['BRAND'], y=top['AVG_BUY_PRICE'], marker_color='#f43f5e'))
        fig3.update_layout(barmode='group', paper_bgcolor='rgba(0,0,0,0)', plot_bgcolor='rgba(0,0,0,0)',
                           margin=dict(t=30,b=20,l=20,r=20))
        st.plotly_chart(fig3, use_container_width=True)

# ============================================================================
# TAB 2: ENTITY RESOLUTION STUDIO
# ============================================================================
with tab_matches:
    st.markdown("### 🔬 AI Entity Resolution Results")
    mc1, mc2, mc3 = st.columns(3)
    with mc1:
        brand_filter = st.selectbox("Brand Filter", ['All'] + sorted(matches_df['ABT_BRAND'].unique().tolist()))
    with mc2:
        strategy_filter = st.selectbox("Strategy Filter", ['All'] + sorted(matches_df['MATCH_STRATEGY'].unique().tolist()))
    with mc3:
        llm_filter = st.selectbox("LLM Verification", ['All'] + sorted(matches_df['LLM_VERIFICATION'].unique().tolist()))

    filtered = matches_df.copy()
    if brand_filter != 'All':
        filtered = filtered[filtered['ABT_BRAND'] == brand_filter]
    if strategy_filter != 'All':
        filtered = filtered[filtered['MATCH_STRATEGY'] == strategy_filter]
    if llm_filter != 'All':
        filtered = filtered[filtered['LLM_VERIFICATION'] == llm_filter]

    st.markdown(f"**{len(filtered):,}** matches displayed")

    display_cols = ['ABT_NAME', 'BUY_NAME', 'ABT_BRAND', 'COMPOSITE_SCORE', 'MATCH_STRATEGY',
                    'LLM_VERIFICATION', 'ABT_PRICE', 'BUY_PRICE', 'PRICE_GAP_PCT']
    available_cols = [c for c in display_cols if c in filtered.columns]
    st.dataframe(filtered[available_cols].sort_values('COMPOSITE_SCORE', ascending=False).head(100),
                 use_container_width=True, height=400)

    st.markdown("#### 📊 Confidence Score Distribution")
    if 'COMPOSITE_SCORE' in filtered.columns:
        fig_hist = px.histogram(filtered, x='COMPOSITE_SCORE', nbins=30, color_discrete_sequence=['#6366f1'])
        fig_hist.update_layout(paper_bgcolor='rgba(0,0,0,0)', plot_bgcolor='rgba(0,0,0,0)',
                               margin=dict(t=20,b=20,l=20,r=20))
        st.plotly_chart(fig_hist, use_container_width=True)

# ============================================================================
# TAB 3: BENCHMARK & ACCURACY
# ============================================================================
with tab_bench:
    st.markdown("### 🎯 Ground Truth Benchmark Evaluation")
    if not metrics_df.empty:
        bm = metrics_df.iloc[0]
        b1, b2, b3, b4, b5 = st.columns(5)
        b1.metric("Ground Truth", f"{int(bm.get('TOTAL_GROUND_TRUTH', 0)):,}")
        b2.metric("Predicted", f"{int(bm.get('TOTAL_PREDICTED', 0)):,}")
        b3.metric("Precision", f"{bm.get('PRECISION_PCT', 0)}%")
        b4.metric("Recall", f"{bm.get('RECALL_PCT', 0)}%")
        b5.metric("F1 Score", f"{bm.get('F1_SCORE_PCT', 0)}%")

    st.markdown("---")
    c1, c2 = st.columns(2)
    with c1:
        st.markdown("#### 📈 Accuracy by Strategy")
        strat_acc = load_accuracy_strategy()
        if not strat_acc.empty:
            fig_sa = px.bar(strat_acc, x='MATCH_STRATEGY', y='PRECISION_PCT', text='PRECISION_PCT',
                            color='MATCH_STRATEGY', color_discrete_sequence=['#10b981','#38bdf8','#a855f7','#f59e0b'])
            fig_sa.update_layout(paper_bgcolor='rgba(0,0,0,0)', plot_bgcolor='rgba(0,0,0,0)',
                                 showlegend=False, margin=dict(t=20,b=20))
            st.plotly_chart(fig_sa, use_container_width=True)
    with c2:
        st.markdown("#### 🏢 Accuracy by Brand")
        brand_acc = load_accuracy_brand()
        if not brand_acc.empty:
            fig_ba = px.scatter(brand_acc, x='PRECISION_PCT', y='RECALL_PCT', size='TOTAL',
                                color='BRAND', hover_name='BRAND', size_max=30)
            fig_ba.update_layout(paper_bgcolor='rgba(0,0,0,0)', plot_bgcolor='rgba(0,0,0,0)',
                                 margin=dict(t=20,b=20))
            st.plotly_chart(fig_ba, use_container_width=True)

    st.markdown("#### 🔍 Confusion Matrix")
    if not metrics_df.empty:
        bm = metrics_df.iloc[0]
        tp = int(bm.get('TRUE_POSITIVES', 0))
        fp = int(bm.get('FALSE_POSITIVES', 0))
        fn = int(bm.get('FALSE_NEGATIVES', 0))
        cm = pd.DataFrame({'Predicted Match': [tp, fn], 'Predicted No Match': [fp, 0]},
                          index=['Actual Match', 'Actual No Match'])
        st.dataframe(cm, use_container_width=True)

# ============================================================================
# TAB 4: DYNAMIC PRICING
# ============================================================================
with tab_pricing:
    st.markdown(f"### 💰 Dynamic Pricing Engine — {selected_strategy_name}")
    if not pricing_df.empty:
        pc1, pc2, pc3, pc4 = st.columns(4)
        pc1.metric("Products Priced", f"{len(pricing_df):,}")
        avg_chg = pricing_df['PRICE_CHANGE_PCT'].mean() if 'PRICE_CHANGE_PCT' in pricing_df.columns else 0
        pc2.metric("Avg Price Change", f"{avg_chg:.1f}%")
        avg_margin = pricing_df['NEW_MARGIN_PCT'].mean() if 'NEW_MARGIN_PCT' in pricing_df.columns else 0
        pc3.metric("Avg New Margin", f"{avg_margin:.1f}%")
        pc4.metric("Total Profit Opp.", f"${total_profit:,.0f}")

        st.markdown("---")
        st.markdown("#### 📋 Pricing Recommendations")
        price_display = ['PRODUCT_NAME', 'BRAND', 'CURRENT_PRICE', 'COMPETITOR_PRICE',
                         'RECOMMENDED_PRICE', 'PRICE_CHANGE_PCT', 'NEW_MARGIN_PCT',
                         'DEMAND_UPLIFT_PCT', 'MONTHLY_PROFIT_IMPACT', 'ACTION_TYPE']
        available = [c for c in price_display if c in pricing_df.columns]
        st.dataframe(pricing_df[available].sort_values('MONTHLY_PROFIT_IMPACT', ascending=False).head(50),
                     use_container_width=True, height=400)

        st.markdown("#### 💰 Profit Impact by Brand")
        if 'BRAND' in pricing_df.columns and 'MONTHLY_PROFIT_IMPACT' in pricing_df.columns:
            brand_profit = pricing_df.groupby('BRAND')['MONTHLY_PROFIT_IMPACT'].sum().reset_index()
            brand_profit = brand_profit.sort_values('MONTHLY_PROFIT_IMPACT', ascending=False).head(15)
            fig_bp = px.bar(brand_profit, x='BRAND', y='MONTHLY_PROFIT_IMPACT', text_auto='.0f',
                            color_discrete_sequence=['#10b981'])
            fig_bp.update_layout(paper_bgcolor='rgba(0,0,0,0)', plot_bgcolor='rgba(0,0,0,0)',
                                 margin=dict(t=20,b=20))
            st.plotly_chart(fig_bp, use_container_width=True)
    else:
        st.info("No pricing recommendations generated yet. Run the pricing procedure first.")

# ============================================================================
# TAB 5: MARKET INTELLIGENCE
# ============================================================================
with tab_market:
    st.markdown("### 🌐 Market Intelligence & Competitor Analysis")
    market_df = load_market_intel()
    if not market_df.empty:
        st.markdown("#### 🏢 Brand Competitiveness Ranking")
        fig_comp = px.bar(market_df.sort_values('COMPETITIVENESS_INDEX', ascending=True),
                          x='COMPETITIVENESS_INDEX', y='BRAND', orientation='h',
                          color='COMPETITIVENESS_INDEX',
                          color_continuous_scale=['#f43f5e', '#fbbf24', '#10b981'],
                          color_continuous_midpoint=0)
        fig_comp.update_layout(paper_bgcolor='rgba(0,0,0,0)', plot_bgcolor='rgba(0,0,0,0)',
                               margin=dict(t=20,b=20,l=20,r=20), height=500)
        st.plotly_chart(fig_comp, use_container_width=True)

        st.markdown("#### 📊 Market Summary Table")
        st.dataframe(market_df, use_container_width=True, height=350)

    st.markdown("---")
    st.markdown("#### ⚠️ Active Market Anomalies")
    if not anomalies_df.empty:
        for _, row in anomalies_df.iterrows():
            severity_color = '#fee2e2' if row.get('SEVERITY') == 'HIGH' else '#fef3c7'
            border_color = '#e11d48' if row.get('SEVERITY') == 'HIGH' else '#d97706'
            st.markdown(f"""
            <div style="background:{severity_color}; border-left:4px solid {border_color};
                        border-radius:12px; padding:14px 18px; margin-bottom:12px;">
                <strong>{row.get('SEVERITY','')}: {row.get('ANOMALY_TYPE','')}</strong> — {row.get('BRAND','')}<br>
                <em>{row.get('PRODUCT_NAME','')}</em><br>
                Abt: ${row.get('ABT_PRICE',0):,.2f} | Buy: ${row.get('BUY_PRICE',0):,.2f} | Gap: {row.get('PRICE_GAP_PCT',0):.1f}%<br>
                <strong>Action:</strong> {row.get('RECOMMENDED_ACTION','')}
            </div>
            """, unsafe_allow_html=True)
    else:
        st.success("No active anomalies detected.")

# ============================================================================
# TAB 6: CORTEX AGENT CHAT
# ============================================================================
with tab_agents:
    st.markdown("### 🤖 Cortex Autonomous Agent Chat")
    st.markdown("Chat with **real Snowflake Cortex Agents** powered by Semantic Views and Cortex Search.")

    agent_choice = st.radio("Select Agent", [
        "🔬 Product Matching Agent",
        "💰 Price Optimization Agent",
        "🌐 Market Intelligence Agent"
    ], horizontal=True)

    agent_map = {
        "🔬 Product Matching Agent": "RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.PRODUCT_MATCHING_AGENT",
        "💰 Price Optimization Agent": "RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.PRICE_OPTIMIZATION_AGENT",
        "🌐 Market Intelligence Agent": "RETAIL_INTELLIGENCE_V2_DB.CORTEX_AI.MARKET_INTELLIGENCE_AGENT"
    }
    agent_fqn = agent_map[agent_choice]

    # Chat state
    if "agent_messages" not in st.session_state:
        st.session_state.agent_messages = []
    if "current_agent" not in st.session_state:
        st.session_state.current_agent = agent_choice

    # Reset on agent switch
    if st.session_state.current_agent != agent_choice:
        st.session_state.agent_messages = []
        st.session_state.current_agent = agent_choice

    # Display history
    for msg in st.session_state.agent_messages:
        with st.chat_message(msg["role"]):
            st.markdown(msg["content"])

    # Chat input
    if prompt := st.chat_input(f"Ask the {agent_choice.split(' ', 1)[1]}..."):
        st.session_state.agent_messages.append({"role": "user", "content": prompt})
        with st.chat_message("user"):
            st.markdown(prompt)

        with st.chat_message("assistant"):
            with st.spinner("Agent reasoning..."):
                try:
                    # Build message payload for agent
                    messages = []
                    for msg in st.session_state.agent_messages:
                        messages.append({
                            "role": msg["role"],
                            "content": [{"type": "text", "text": msg["content"]}]
                        })

                    payload = json.dumps({"messages": messages})
                    escaped_payload = payload.replace("'", "''")

                    result = session.sql(f"""
                        SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
                            '{agent_fqn}',
                            '{escaped_payload}',
                            TRUE
                        ) AS RESPONSE
                    """).collect()

                    if result:
                        response_json = json.loads(result[0]['RESPONSE'])
                        # Extract text from agent response
                        agent_text = ""
                        if 'choices' in response_json:
                            for choice in response_json['choices']:
                                delta = choice.get('delta', {})
                                content_parts = delta.get('content', [])
                                for part in content_parts:
                                    if part.get('type') == 'text':
                                        agent_text += part.get('text', '')
                        elif 'message' in response_json:
                            content = response_json['message'].get('content', [])
                            for part in content:
                                if isinstance(part, dict) and part.get('type') == 'text':
                                    agent_text += part.get('text', '')
                                elif isinstance(part, str):
                                    agent_text += part

                        if not agent_text:
                            agent_text = str(response_json)

                        st.markdown(agent_text)
                        st.session_state.agent_messages.append({"role": "assistant", "content": agent_text})
                    else:
                        st.error("No response from agent.")
                except Exception as e:
                    error_msg = f"Agent error: {str(e)}"
                    st.error(error_msg)
                    st.session_state.agent_messages.append({"role": "assistant", "content": error_msg})

# ============================================================================
# TAB 7: ARCHITECTURE
# ============================================================================
with tab_arch:
    st.markdown("### ⚡ Snowflake Architecture & Features Used")

    st.markdown("""
    #### 🏗️ System Architecture
    ```
    RAW_ABT_CATALOG / RAW_BUY_CATALOG
            │
            ▼ Dynamic Tables (auto-refresh)
    DT_CLEAN_ABT / DT_CLEAN_BUY
            │
            ├──▶ Cortex Search Service (hybrid vector + keyword)
            ├──▶ Cortex Embeddings (EMBED_TEXT_768 → arctic-embed-m)
            │         │
            │         ▼ Streams + Tasks (incremental)
            │    FINAL_PRODUCT_MATCHES (with LLM verification)
            │         │
            │         ├──▶ Pricing Recommendations
            │         └──▶ Market Intelligence Views
            │
            ▼ 3 Semantic Views
    SV_PRODUCT_MATCHING / SV_PRICING_INTELLIGENCE / SV_MARKET_INTELLIGENCE
            │
            ▼ 3 Cortex Agents
    PRODUCT_MATCHING_AGENT / PRICE_OPTIMIZATION_AGENT / MARKET_INTELLIGENCE_AGENT
            │
            ├──▶ Snowflake Intelligence (AI & ML → Agents)
            └──▶ This Streamlit Dashboard
    ```
    """)

    st.markdown("#### 🛠️ Snowflake Features Checklist")
    features = [
        ("Cortex EMBED_TEXT_768", "snowflake-arctic-embed-m", "Vector embeddings for semantic product matching"),
        ("VECTOR_COSINE_SIMILARITY", "Native vector operations", "Cosine similarity on 768-dim embeddings"),
        ("CORTEX.COMPLETE", "llama3.1-70b", "LLM match verification and error analysis"),
        ("Cortex Search Service", "PRODUCT_SEARCH_SERVICE", "Hybrid vector+keyword search over product catalogs"),
        ("Cortex Agents (3x)", "CREATE AGENT ... FROM SPECIFICATION", "Product Matching, Price Optimization, Market Intelligence"),
        ("Semantic Views (3x)", "CREATE SEMANTIC VIEW", "Structured data layer with dimensions, metrics, VQRs"),
        ("Cortex Analyst", "text_to_sql tool", "Natural language to SQL via semantic views"),
        ("Dynamic Tables (2x)", "TARGET_LAG = '1 hour'", "Auto-refreshing cleaned product catalogs"),
        ("Streams (2x)", "APPEND_ONLY", "CDC on raw catalog tables for new products"),
        ("Tasks (3x)", "Stream-triggered + chained", "Embedding refresh → Entity resolution → LLM verify"),
        ("JavaScript UDFs", "Token overlap + Model similarity", "Jaccard and Levenshtein scoring functions"),
        ("Stored Procedures", "Entity resolution + Pricing + Eval", "Multi-step pipeline orchestration"),
        ("Snowflake Intelligence", "Agent Playground", "All 3 agents accessible in AI & ML → Agents"),
        ("Streamlit in Snowflake", "This dashboard", "Full production dashboard querying Snowflake directly"),
        ("Data Metric Functions", "F1 quality monitoring", "Evaluation history tracking"),
    ]

    for name, detail, desc in features:
        st.markdown(f"✅ **{name}** — `{detail}` — {desc}")

    st.markdown("---")
    st.markdown("#### 📁 Database Structure")
    st.code("""
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
│   ├── FINAL_PRODUCT_MATCHES (AI matches + LLM reasoning)
│   ├── PRODUCT_SEARCH_SERVICE (Cortex Search)
│   ├── SV_PRODUCT_MATCHING (Semantic View)
│   ├── PRODUCT_MATCHING_AGENT (Cortex Agent)
│   ├── PRICE_OPTIMIZATION_AGENT (Cortex Agent)
│   ├── MARKET_INTELLIGENCE_AGENT (Cortex Agent)
│   └── Tasks: REFRESH_EMBEDDINGS → RESOLVE_MATCHES → LLM_VERIFY
└── ANALYTICS
    ├── PRICING_STRATEGY_CONFIG
    ├── PRICING_RECOMMENDATIONS
    ├── V_COMPETITIVE_PRICE_INDEX
    ├── V_MARKET_INTELLIGENCE
    ├── V_MARKET_ANOMALIES
    ├── V_BENCHMARK_METRICS (Precision/Recall/F1)
    ├── V_ACCURACY_BY_STRATEGY
    ├── V_ACCURACY_BY_BRAND
    ├── EVALUATION_HISTORY
    ├── SV_PRICING_INTELLIGENCE (Semantic View)
    └── SV_MARKET_INTELLIGENCE (Semantic View)
    """, language="text")

-- =========================================================
-- 1. CREATE DATABASE
-- =========================================================

CREATE DATABASE IF NOT EXISTS fpna_project;

-- =========================================================
-- 2. FACT TABLE: fact_transactions
-- =========================================================

CREATE TABLE IF NOT EXISTS fact_transactions (
    date DATE,
    customer_id INT,
    region VARCHAR(50),
    plan VARCHAR(50),
    revenue NUMERIC(12,2),
    cost NUMERIC(12,2),
    profit NUMERIC(12,2)
);

-- =========================================================
-- 3. FACT TABLE: fact_budget
-- =========================================================

CREATE TABLE IF NOT EXISTS fact_budget (
    month DATE,
    budget_revenue NUMERIC(12,2),
    budget_cost NUMERIC(12,2),
    budget_profit NUMERIC(12,2)
);

-- =========================================================
-- 4. DIMENSION TABLES
-- =========================================================

CREATE TABLE IF NOT EXISTS dim_date AS
SELECT DISTINCT DATE_TRUNC('month', date)::date AS month
FROM fact_transactions;

CREATE TABLE IF NOT EXISTS dim_region AS
SELECT DISTINCT region
FROM fact_transactions;

CREATE TABLE IF NOT EXISTS dim_plan AS
SELECT DISTINCT plan
FROM fact_transactions;

-- =========================================================
-- 5. MONTHLY ACTUAL KPI (FACT → MONTHLY AGGREGATION)
-- =========================================================

CREATE OR REPLACE VIEW v_monthly_actual AS
SELECT
    DATE_TRUNC('month', date)::date AS month,
    SUM(revenue) AS actual_revenue,
    SUM(cost) AS actual_cost,
    SUM(profit) AS actual_profit,
    COUNT(DISTINCT customer_id) AS active_customers
FROM fact_transactions
GROUP BY 1
ORDER BY 1;

-- =========================================================
-- 6. BUDGET VIEW
-- =========================================================

CREATE OR REPLACE VIEW v_monthly_budget AS
SELECT
    month,
    budget_revenue,
    budget_cost,
    budget_profit
FROM fact_budget;

-- =========================================================
-- 7. BUDGET VS ACTUAL ANALYSIS
-- =========================================================

CREATE OR REPLACE VIEW v_budget_vs_actual AS
select
    a.month,
    a.actual_revenue,
    b.budget_revenue,
    a.actual_cost,
    b.budget_cost,
    a.actual_profit,
    b.budget_profit,
    (a.actual_revenue - b.budget_revenue) AS revenue_variance,
    ROUND(
        (a.actual_revenue - b.budget_revenue)
        / NULLIF(b.budget_revenue, 0),
        4
    ) AS revenue_variance_pct
FROM v_monthly_actual a
JOIN v_monthly_budget b
    ON a.month = b.month;

-- =========================================================
-- 8. ROLLING 3-MONTH REVENUE
-- =========================================================

CREATE OR REPLACE VIEW v_revenue_trend AS
SELECT
    month,
    actual_revenue,
    ROUND(
    	AVG(actual_revenue) OVER (
        	ORDER BY month
        	ROWS BETWEEN 2 PRECEDING AND CURRENT row
		), 2        	
    ) AS revenue_3m_moving_avg
FROM v_monthly_actual;

-- =========================================================
-- 9. CUSTOMER GROWTH
-- =========================================================

CREATE OR REPLACE VIEW v_customer_growth AS
SELECT
    month,
    active_customers,
    LAG(active_customers) OVER (
        ORDER BY month
    ) AS prev_customers,
    ROUND(
        CASE 
            WHEN LAG(active_customers) OVER (ORDER BY month) IS NULL THEN NULL
            ELSE (
                active_customers - LAG(active_customers) OVER (ORDER BY month)
            ) * 1.0 /
            LAG(active_customers) OVER (ORDER BY month)
        END,
        4
    ) AS customer_growth_pct
FROM v_monthly_actual;

-- =========================================================
-- 10. FPNA DATA MART
-- =========================================================

CREATE OR REPLACE VIEW v_fpna_mart AS
select
    v.month,
    v.actual_revenue,
    v.actual_cost,
    v.actual_profit,
    b.budget_revenue,
    b.budget_cost,
    b.budget_profit,
    v.revenue_variance,
    v.revenue_variance_pct,
    r.revenue_3m_moving_avg
FROM v_budget_vs_actual v
LEFT JOIN v_revenue_trend r
    ON v.month = r.month
LEFT JOIN v_monthly_budget b
    ON v.month = b.month
ORDER BY v.month;

-- =========================================================
-- 11. CUSTOMER ANALYSIS
-- =========================================================

CREATE OR REPLACE VIEW v_customer_analysis AS
SELECT
    customer_id,
    region,
    plan,
    SUM(revenue) AS revenue,
    SUM(cost) AS cost,
    SUM(profit) AS profit
FROM fact_transactions
GROUP BY customer_id, region, plan;

-- =========================================================
-- 12. PLAN PERFORMANCE
-- =========================================================

CREATE OR REPLACE VIEW v_plan_performance AS
SELECT
    plan,
    SUM(revenue) AS revenue,
    SUM(cost) AS cost,
    SUM(profit) AS profit,
    ROUND(SUM(profit) / NULLIF(SUM(revenue), 0), 4) AS margin_pct
FROM fact_transactions
GROUP BY plan;

-- =========================================================
-- 13. REGION PERFORMANCE
-- =========================================================

CREATE OR REPLACE VIEW v_region_performance AS
SELECT
    region,
    SUM(revenue) AS revenue,
    SUM(cost) AS cost,
    SUM(profit) AS profit
FROM fact_transactions
GROUP BY region;
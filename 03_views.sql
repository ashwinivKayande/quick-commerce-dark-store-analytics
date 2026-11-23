-- =====================================================
-- STEP 5: Power BI ke liye Views (Quick Commerce Dark Store Project)
-- Is file me sirf views banti hain, koi data delete nahi hota.
-- Isliye is file me pehla ⚡ (Run All) dabana SAFE hai.
-- =====================================================
USE dark_store_db;

-- ----------------------------------------------------
-- 0. Rent calibration (sirf ek baar chalta hai, dobara chalane se kuch nahi bigadta)
-- Reason: real dark store me ~20,000 orders/month hote hain, hamare synthetic data
-- me ~900. Isliye rent ko 1/10 kiya taaki profit/loss ka analysis realistic aaye.
-- ----------------------------------------------------
UPDATE dark_stores
SET monthly_rent = monthly_rent / 10
WHERE store_id > 0 AND monthly_rent >= 100000;

-- ----------------------------------------------------
-- 1. vw_orders: ek row = ek order (delivery, SLA, baarish, revenue)
-- ----------------------------------------------------
CREATE OR REPLACE VIEW vw_orders AS
SELECT o.order_id,
       o.customer_id,
       o.store_id,
       s.city                                   AS store_city,
       s.area                                   AS store_area,
       o.partner_id,
       o.order_time,
       DATE(o.order_time)                       AS order_date,
       HOUR(o.order_time)                       AS order_hour,
       DAYNAME(o.order_time)                    AS day_name,
       WEEKDAY(o.order_time)                    AS weekday_no,
       DATE_FORMAT(o.order_time, '%Y-%m')       AS order_month,
       o.status,
       o.payment_mode,
       o.is_rainy_day,
       o.delivery_fee,
       o.delivery_time_min,
       CASE WHEN o.delivery_time_min IS NULL THEN NULL
            WHEN o.delivery_time_min > 10 THEN 1
            ELSE 0 END                          AS is_late,
       t.items_count,
       t.order_revenue,
       t.order_cost
FROM orders o
JOIN dark_stores s ON o.store_id = s.store_id
LEFT JOIN (
    SELECT oi.order_id,
           SUM(oi.quantity)                      AS items_count,
           SUM(oi.quantity * oi.selling_price)   AS order_revenue,
           SUM(oi.quantity * p.cost_price)       AS order_cost
    FROM order_items oi
    JOIN products p ON oi.product_id = p.product_id
    GROUP BY oi.order_id
) t ON o.order_id = t.order_id;

-- ----------------------------------------------------
-- 2. vw_sales_detail: ek row = order ka ek product (category / product analysis)
-- ----------------------------------------------------
CREATE OR REPLACE VIEW vw_sales_detail AS
SELECT oi.order_item_id,
       oi.order_id,
       DATE(o.order_time)                        AS order_date,
       o.store_id,
       s.city                                    AS store_city,
       s.area                                    AS store_area,
       p.product_name,
       p.category,
       oi.quantity,
       oi.selling_price,
       oi.quantity * oi.selling_price            AS revenue,
       oi.quantity * p.cost_price                AS product_cost,
       oi.quantity * (oi.selling_price - p.cost_price) AS gross_profit
FROM order_items oi
JOIN orders o       ON oi.order_id = o.order_id
JOIN dark_stores s  ON o.store_id = s.store_id
JOIN products p     ON oi.product_id = p.product_id
WHERE o.status = 'Delivered';

-- ----------------------------------------------------
-- 3. vw_inventory: ek row = ek store + ek product + ek din (stock-out analysis)
-- ----------------------------------------------------
CREATE OR REPLACE VIEW vw_inventory AS
SELECT i.inventory_id,
       i.`date`           AS stock_date,
       i.store_id,
       s.city             AS store_city,
       s.area             AS store_area,
       p.product_name,
       p.category,
       i.stockout_flag,
       i.opening_stock,
       i.closing_stock,
       i.units_wasted
FROM inventory_daily i
JOIN dark_stores s ON i.store_id = s.store_id
JOIN products p    ON i.product_id = p.product_id;

-- ----------------------------------------------------
-- 4. vw_customer_rfm: ek row = ek customer (RFM segmentation, NTILE window function)
-- Recency = 30 June 2026 se last order kitne din pehle
-- ----------------------------------------------------
CREATE OR REPLACE VIEW vw_customer_rfm AS
SELECT sc.customer_id,
       cu.city,
       cu.segment,
       sc.first_order_date,
       sc.last_order_date,
       sc.recency_days,
       sc.frequency,
       sc.monetary,
       sc.r_score,
       sc.f_score,
       sc.m_score,
       CASE WHEN sc.r_score >= 4 AND sc.f_score >= 4 THEN 'Champions'
            WHEN sc.r_score >= 3 AND sc.f_score >= 3 THEN 'Loyal'
            WHEN sc.r_score >= 4 AND sc.f_score <= 2 THEN 'New / Promising'
            WHEN sc.r_score <= 2 AND sc.f_score >= 3 THEN 'At Risk'
            WHEN sc.r_score <= 2 AND sc.f_score <= 2 THEN 'Lost'
            ELSE 'Need Attention' END AS rfm_segment
FROM (
    SELECT c.*,
           NTILE(5) OVER (ORDER BY c.recency_days DESC) AS r_score,
           NTILE(5) OVER (ORDER BY c.frequency)         AS f_score,
           NTILE(5) OVER (ORDER BY c.monetary)          AS m_score
    FROM (
        SELECT o.customer_id,
               MIN(DATE(o.order_time))                         AS first_order_date,
               MAX(DATE(o.order_time))                         AS last_order_date,
               DATEDIFF('2026-06-30', MAX(DATE(o.order_time))) AS recency_days,
               COUNT(*)                                        AS frequency,
               ROUND(SUM(t.order_revenue), 2)                  AS monetary
        FROM orders o
        JOIN (
            SELECT order_id, SUM(quantity * selling_price) AS order_revenue
            FROM order_items
            GROUP BY order_id
        ) t ON o.order_id = t.order_id
        WHERE o.status = 'Delivered'
        GROUP BY o.customer_id
    ) c
) sc
JOIN customers cu ON sc.customer_id = cu.customer_id;

-- ----------------------------------------------------
-- 5. vw_store_pnl: ek row = ek store ka 6 mahine ka profit & loss
-- Assumptions: rider cost = Rs 30 per delivered order, rent = monthly_rent x 6
-- ----------------------------------------------------
CREATE OR REPLACE VIEW vw_store_pnl AS
SELECT s.store_id,
       s.city,
       s.area,
       COUNT(*)                                              AS delivered_orders,
       ROUND(SUM(o.order_revenue))                           AS revenue,
       ROUND(SUM(o.order_revenue - o.order_cost))            AS gross_profit,
       SUM(o.delivery_fee)                                   AS delivery_fee_income,
       COUNT(*) * 30                                         AS rider_cost,
       s.monthly_rent * 6                                    AS rent_6m,
       ROUND(SUM(o.order_revenue - o.order_cost)
             + SUM(o.delivery_fee) - COUNT(*) * 30 - s.monthly_rent * 6) AS net_profit
FROM vw_orders o
JOIN dark_stores s ON o.store_id = s.store_id
WHERE o.status = 'Delivered'
GROUP BY s.store_id, s.city, s.area, s.monthly_rent;

-- ----------------------------------------------------
-- Check: views ban gayi? (7 + 5 = 12 rows me naye views dikhne chahiye)
-- ----------------------------------------------------
SHOW FULL TABLES IN dark_store_db WHERE Table_type = 'VIEW';

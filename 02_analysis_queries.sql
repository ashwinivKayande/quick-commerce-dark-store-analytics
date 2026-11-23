-- =====================================================
-- STEP 4: SQL Analysis (Quick Commerce Dark Store Project)
-- Har query ko alag-alag chalao: cursor query ke andar rakho
-- aur Ctrl + Enter dabao (ya hara circle wala icon).
-- =====================================================
USE dark_store_db;

-- ----------------------------------------------------
-- Q0. Sanity check: sab tables me data aaya?
-- Expected: 12, 55, 20000, 90, 60000, ~170977, 119460
-- ----------------------------------------------------
SELECT 'dark_stores' AS tbl, COUNT(*) AS total_rows FROM dark_stores
UNION ALL SELECT 'products',          COUNT(*) FROM products
UNION ALL SELECT 'customers',         COUNT(*) FROM customers
UNION ALL SELECT 'delivery_partners', COUNT(*) FROM delivery_partners
UNION ALL SELECT 'orders',            COUNT(*) FROM orders
UNION ALL SELECT 'order_items',       COUNT(*) FROM order_items
UNION ALL SELECT 'inventory_daily',   COUNT(*) FROM inventory_daily;

-- ----------------------------------------------------
-- Q1. Har store ka revenue aur orders (JOIN + GROUP BY)
-- Sawal: Kaunsa store sabse zyada kama raha hai?
-- ----------------------------------------------------
SELECT s.store_id, s.city, s.area,
       COUNT(DISTINCT o.order_id)                   AS orders,
       ROUND(SUM(oi.quantity * oi.selling_price))   AS revenue
FROM orders o
JOIN dark_stores s  ON o.store_id = s.store_id
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.status = 'Delivered'
GROUP BY s.store_id, s.city, s.area
ORDER BY revenue DESC;

-- ----------------------------------------------------
-- Q2. Hour-wise orders (peak hour analysis)
-- Sawal: Kaunse ghante me sabse zyada orders aate hain?
-- ----------------------------------------------------
SELECT HOUR(order_time) AS order_hour,
       COUNT(*)         AS orders
FROM orders
GROUP BY HOUR(order_time)
ORDER BY order_hour;

-- ----------------------------------------------------
-- Q3. SLA breach: 10 minute se zyada late orders, store-wise
-- Sawal: Kaunse stores pe delivery sabse zyada late hoti hai?
-- ----------------------------------------------------
SELECT s.store_id, s.area,
       COUNT(*)                                        AS delivered_orders,
       SUM(o.delivery_time_min > 10)                   AS late_orders,
       ROUND(100 * SUM(o.delivery_time_min > 10) / COUNT(*), 1) AS late_pct,
       ROUND(AVG(o.delivery_time_min), 1)              AS avg_delivery_min
FROM orders o
JOIN dark_stores s ON o.store_id = s.store_id
WHERE o.status = 'Delivered'
GROUP BY s.store_id, s.area
ORDER BY late_pct DESC;

-- ----------------------------------------------------
-- Q4. Baarish ka delivery pe asar
-- Sawal: Baarish wale din delivery kitni slow hoti hai?
-- ----------------------------------------------------
SELECT CASE WHEN is_rainy_day = 1 THEN 'Rainy day' ELSE 'Dry day' END AS day_type,
       COUNT(*)                          AS orders,
       ROUND(AVG(delivery_time_min), 1)  AS avg_delivery_min,
       ROUND(100 * SUM(delivery_time_min > 10) / COUNT(*), 1) AS late_pct
FROM orders
WHERE status = 'Delivered'
GROUP BY is_rainy_day;

-- ----------------------------------------------------
-- Q5. Stock-out % store-wise (CTE)
-- Sawal: Kaunse store me saaman sabse zyada khatam hota hai?
-- ----------------------------------------------------
WITH store_stock AS (
    SELECT store_id,
           COUNT(*)           AS stock_checks,
           SUM(stockout_flag) AS stockouts
    FROM inventory_daily
    GROUP BY store_id
)
SELECT s.store_id, s.area,
       ss.stockouts,
       ss.stock_checks,
       ROUND(100 * ss.stockouts / ss.stock_checks, 1) AS stockout_pct
FROM store_stock ss
JOIN dark_stores s ON ss.store_id = s.store_id
ORDER BY stockout_pct DESC;

-- ----------------------------------------------------
-- Q6. Category-wise stock-out %
-- Sawal: Kaunsi category sabse zyada khatam hoti hai?
-- ----------------------------------------------------
SELECT p.category,
       COUNT(*)                                          AS stock_checks,
       SUM(i.stockout_flag)                              AS stockouts,
       ROUND(100 * SUM(i.stockout_flag) / COUNT(*), 1)   AS stockout_pct
FROM inventory_daily i
JOIN products p ON i.product_id = p.product_id
GROUP BY p.category
ORDER BY stockout_pct DESC;

-- ----------------------------------------------------
-- Q7. Top 10 products by revenue (RANK window function)
-- ----------------------------------------------------
SELECT *
FROM (
    SELECT p.product_name, p.category,
           ROUND(SUM(oi.quantity * oi.selling_price)) AS revenue,
           RANK() OVER (ORDER BY SUM(oi.quantity * oi.selling_price) DESC) AS rnk
    FROM order_items oi
    JOIN products p ON oi.product_id = p.product_id
    JOIN orders o   ON oi.order_id = o.order_id
    WHERE o.status = 'Delivered'
    GROUP BY p.product_id, p.product_name, p.category
) t
WHERE rnk <= 10
ORDER BY rnk;

-- ----------------------------------------------------
-- Q8. Weekly orders aur week-on-week growth (CTE + LAG)
-- Sawal: Pichhle hafte se is hafte growth kitni hai?
-- ----------------------------------------------------
WITH weekly AS (
    SELECT YEARWEEK(order_time, 1)   AS yw,
           MIN(DATE(order_time))     AS week_start,
           COUNT(*)                  AS orders
    FROM orders
    WHERE status = 'Delivered'
    GROUP BY YEARWEEK(order_time, 1)
)
SELECT week_start,
       orders,
       LAG(orders) OVER (ORDER BY yw) AS prev_week_orders,
       ROUND(100 * (orders - LAG(orders) OVER (ORDER BY yw))
                 / LAG(orders) OVER (ORDER BY yw), 1) AS wow_growth_pct
FROM weekly
ORDER BY yw;

-- ----------------------------------------------------
-- Q9. Repeat vs one-time customers
-- Sawal: Kitne customers dobara order karte hain?
-- ----------------------------------------------------
WITH cust_orders AS (
    SELECT customer_id, COUNT(*) AS orders
    FROM orders
    WHERE status = 'Delivered'
    GROUP BY customer_id
)
SELECT CASE WHEN orders = 1 THEN '1 order (one-time)'
            WHEN orders BETWEEN 2 AND 4 THEN '2-4 orders'
            ELSE '5+ orders (loyal)' END AS customer_type,
       COUNT(*) AS customers,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_customers
FROM cust_orders
GROUP BY CASE WHEN orders = 1 THEN '1 order (one-time)'
              WHEN orders BETWEEN 2 AND 4 THEN '2-4 orders'
              ELSE '5+ orders (loyal)' END
ORDER BY MIN(orders);

-- ----------------------------------------------------
-- Q10. Store-wise gross profit (revenue - product cost)
-- ----------------------------------------------------
SELECT s.store_id, s.area,
       ROUND(SUM(oi.quantity * oi.selling_price))                       AS revenue,
       ROUND(SUM(oi.quantity * p.cost_price))                           AS product_cost,
       ROUND(SUM(oi.quantity * (oi.selling_price - p.cost_price)))      AS gross_profit,
       ROUND(100 * SUM(oi.quantity * (oi.selling_price - p.cost_price))
                 / SUM(oi.quantity * oi.selling_price), 1)              AS gross_margin_pct
FROM orders o
JOIN dark_stores s  ON o.store_id = s.store_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p     ON oi.product_id = p.product_id
WHERE o.status = 'Delivered'
GROUP BY s.store_id, s.area
ORDER BY gross_profit DESC;

PRAGMA foreign_keys = ON;

---------------
-- USE CASE 1: CUSTOMER DETAILS AND ORDERS (customer service / CRM)
---------------

-- 5.1 Give the details of every customer (name, e-mail, city, country) together with their number of orders,
--     total spent, date of last order, days since last order, number of failed payments and their spending
--     rank within their country, including customers who never ordered.
-- Constructs: CTEs, LEFT OUTER JOIN (x3), CASE, correlated subquery, view, || , julianday, RANK() OVER (PARTITION BY)
WITH main_address AS (
    SELECT customer_id, MIN(address_id) AS address_id
    FROM Address
    WHERE is_active = 1
    GROUP BY customer_id
),
order_stats AS (
    SELECT customer_id,
           COUNT(*)          AS n_orders,
           SUM(items_total)  AS total_spent,
           MAX(order_date)   AS last_order
    FROM v_order_total
    WHERE status <> 'Cancelled'
    GROUP BY customer_id
),
customer_orders AS (
    SELECT c.customer_id,
           c.first_name || ' ' || c.last_name AS customer,
           c.email,
           a.city,
           a.country,
           CASE WHEN s.n_orders IS NULL THEN 0 ELSE s.n_orders END         AS n_orders,
           CASE WHEN s.total_spent IS NULL THEN 0 ELSE ROUND(s.total_spent, 2) END AS total_spent,
           s.last_order,
           (SELECT COUNT(*)
              FROM Payment AS p
              JOIN CustomerOrder AS o ON o.order_id = p.order_id
             WHERE o.customer_id = c.customer_id AND p.status = 'Failed') AS failed_payments
    FROM Customer AS c
    LEFT JOIN main_address AS m ON m.customer_id = c.customer_id
    LEFT JOIN Address      AS a ON a.address_id  = m.address_id
    LEFT JOIN order_stats  AS s ON s.customer_id = c.customer_id
)
SELECT customer_id, customer, email, city, country, n_orders, total_spent, last_order,
       ROUND(julianday('2026-10-31') - julianday(last_order), 0) AS days_since_last_order,
       failed_payments,
       RANK() OVER (PARTITION BY country ORDER BY total_spent DESC) AS spend_rank_in_country
FROM customer_orders
ORDER BY total_spent DESC, customer_id;

-- 5.2 Give the name, e-mail, number of items, cart value and days idle of customers with at least 500 in cart items left for more than 7 days and not bought since, with a suggested action.
-- Constructs: NOT EXISTS, GROUP BY, HAVING, CASE, julianday
SELECT c.customer_id,
       c.first_name || ' ' || c.last_name                              AS customer,
       c.email,
       COUNT(*)                                                         AS abandoned_items,
       ROUND(SUM(ci.quantity * v.unit_price), 2)                        AS cart_value,
       ROUND(julianday('2026-10-31') - julianday(MAX(ci.created_at)), 0) AS days_idle,
       CASE WHEN SUM(ci.quantity * v.unit_price) >= 1500 THEN 'HIGH value - send offer'
            WHEN SUM(ci.quantity * v.unit_price) >= 1000 THEN 'MEDIUM value - reminder'
            ELSE 'LOWER value - newsletter' END                         AS action
FROM Cart AS ca
JOIN Customer       AS c  ON c.customer_id = ca.customer_id
JOIN CartItem       AS ci ON ci.cart_id    = ca.cart_id
JOIN ProductVariant AS v  ON v.variant_id  = ci.variant_id
WHERE julianday('2026-10-31') - julianday(ci.created_at) > 7
  AND NOT EXISTS (
        SELECT *
        FROM CustomerOrder AS o
        JOIN OrderItem     AS oi ON oi.order_id = o.order_id
        WHERE o.customer_id = ca.customer_id
          AND oi.variant_id = ci.variant_id
          AND o.status <> 'Cancelled'
          AND o.order_date > ci.created_at)
GROUP BY c.customer_id
HAVING SUM(ci.quantity * v.unit_price) >= 500
ORDER BY cart_value DESC;

---------------
-- USE CASE 2: SALES PERFORMANCE: PRODUCT AND MONTHLY REVENUE (merchandising / management)
---------------

-- 5.3 Give the three highest-revenue products in each top-level category, with their revenue, units sold,
--     share of the category's revenue and average rating.
-- Constructs: WITH RECURSIVE (category -> top-level category), CTEs, JOIN, view, SUM() OVER (PARTITION BY), RANK() OVER (PARTITION BY)
-- avg_rating is NULL for products that have no reviews.
WITH RECURSIVE root_of(category_id, root_id) AS (
    SELECT category_id, category_id FROM Category WHERE parent_category_id IS NULL
    UNION ALL
    SELECT c.category_id, r.root_id
    FROM Category AS c JOIN root_of AS r ON c.parent_category_id = r.category_id
),
product_revenue AS (
    SELECT v.product_id,
           SUM(oi.quantity * oi.unit_price_at_purchase) AS revenue,
           SUM(oi.quantity)                             AS units_sold
    FROM OrderItem AS oi
    JOIN ProductVariant AS v ON v.variant_id = oi.variant_id
    JOIN CustomerOrder  AS o ON o.order_id   = oi.order_id
    WHERE o.status <> 'Cancelled'
    GROUP BY v.product_id
),
ranked AS (
    SELECT rc.name AS category,
           p.name  AS product,
           ROUND(pr.revenue, 2) AS revenue,
           pr.units_sold,
           ROUND(100.0 * pr.revenue / SUM(pr.revenue) OVER (PARTITION BY rc.category_id), 1) AS pct_of_category,
           rt.avg_rating,
           RANK() OVER (PARTITION BY rc.category_id ORDER BY pr.revenue DESC) AS rank_in_category
    FROM product_revenue AS pr
    JOIN Product          AS p  ON p.product_id   = pr.product_id
    JOIN root_of          AS r  ON r.category_id  = p.category_id
    JOIN Category         AS rc ON rc.category_id = r.root_id
    JOIN v_product_rating AS rt ON rt.product_id  = p.product_id
)
SELECT category, rank_in_category, product, revenue, units_sold, pct_of_category, avg_rating
FROM ranked
WHERE rank_in_category <= 3
ORDER BY category, rank_in_category;

-- 5.4 Give, for each of the last 12 complete months, the revenue, orders, customers, average order value, growth on the previous month, 3-month moving average and revenue rank.
-- Constructs: WITH RECURSIVE (generates the months), LEAD, LAG, AVG() OVER (ROWS BETWEEN), RANK
WITH RECURSIVE
ym(y, m) AS (                                       -- every (year, month) from 2024-01 to 2026-10
    SELECT 2024, 1
    UNION ALL
    SELECT CASE WHEN m = 12 THEN y + 1 ELSE y END,
           CASE WHEN m = 12 THEN 1 ELSE m + 1 END
    FROM ym WHERE y * 100 + m < 202610
),
month_start AS (
    SELECT y || '-' || CASE WHEN m < 10 THEN '0' ELSE '' END || m || '-01' AS start_d FROM ym
),
bounds AS (                                         -- next_d = start of the following month
    SELECT start_d, LEAD(start_d, 1) OVER (ORDER BY start_d) AS next_d FROM month_start
),
monthly AS (
    SELECT b.start_d                          AS month_start,
           ROUND(SUM(t.items_total), 2)       AS revenue,
           COUNT(t.order_id)                  AS orders,
           COUNT(DISTINCT t.customer_id)      AS customers
    FROM bounds AS b
    JOIN v_order_total AS t ON t.order_date >= b.start_d AND t.order_date < b.next_d
                           AND t.status <> 'Cancelled'
    WHERE b.next_d IS NOT NULL                       -- drops Oct-2026 (incomplete month)
    GROUP BY b.start_d
),
metrics AS (
    SELECT month_start, revenue, orders, customers,
           ROUND(revenue / orders, 2)                                         AS avg_order_value,
           ROUND(100.0 * (revenue - LAG(revenue, 1) OVER (ORDER BY month_start))
                       / LAG(revenue, 1) OVER (ORDER BY month_start), 1)      AS mom_growth_pct,
           ROUND(AVG(revenue) OVER (ORDER BY month_start
                 ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2)                AS moving_avg_3m,
           RANK() OVER (ORDER BY revenue DESC)                                AS revenue_rank_all_time
    FROM monthly
)
SELECT *
FROM metrics
WHERE month_start >= '2025-10-01'
ORDER BY month_start;

---------------
-- USE CASE 3: MARKETING ANALYTICS (marketing)
---------------

-- 5.5 Give the pairs of products bought together in at least 8 orders, with their support, confidence and lift.
-- Constructs: CTEs, self-join, DISTINCT, HAVING. Lift = support(A,B) / (support(A) * support(B))
WITH basket AS (
    SELECT DISTINCT oi.order_id, v.product_id
    FROM OrderItem AS oi
    JOIN ProductVariant AS v ON v.variant_id = oi.variant_id
    JOIN CustomerOrder  AS o ON o.order_id   = oi.order_id
    WHERE o.status <> 'Cancelled'
),
n_orders AS (SELECT COUNT(DISTINCT order_id) AS n FROM basket),
freq AS (SELECT product_id, COUNT(*) AS orders_with FROM basket GROUP BY product_id),
pairs AS (
    SELECT a.product_id AS pa, b.product_id AS pb, COUNT(*) AS pair_orders
    FROM basket AS a
    JOIN basket AS b ON a.order_id = b.order_id AND a.product_id < b.product_id
    GROUP BY a.product_id, b.product_id
    HAVING COUNT(*) >= 8                            -- minimum support count
)
SELECT p1.name                                                   AS product_A,
       p2.name                                                   AS product_B,
       pairs.pair_orders,
       ROUND(100.0 * pairs.pair_orders / n.n, 2)                 AS support_pct,
       ROUND(100.0 * pairs.pair_orders / fa.orders_with, 1)      AS confidence_A_to_B_pct,
       ROUND((1.0 * pairs.pair_orders / n.n) /
             ((1.0 * fa.orders_with / n.n) * (1.0 * fb.orders_with / n.n)), 1) AS lift
FROM pairs
CROSS JOIN n_orders AS n
JOIN freq    AS fa ON fa.product_id = pairs.pa
JOIN freq    AS fb ON fb.product_id = pairs.pb
JOIN Product AS p1 ON p1.product_id = pairs.pa
JOIN Product AS p2 ON p2.product_id = pairs.pb
ORDER BY lift DESC, pair_orders DESC;

-- 5.6 Give the number of customers, average spend, average orders, days since last order and share of revenue for each RFM segment, including customers who never bought.
-- Constructs: LEFT OUTER JOIN, NTILE, CASE, UNION ALL, scalar subquery
WITH cust AS (
    SELECT c.customer_id,
           COUNT(t.order_id)                                              AS frequency,
           CASE WHEN SUM(t.items_total) IS NULL THEN 0
                ELSE SUM(t.items_total) END                               AS monetary,
           ROUND(julianday('2026-10-31') - julianday(MAX(t.order_date)), 0) AS recency_days
    FROM Customer AS c
    LEFT JOIN v_order_total AS t ON t.customer_id = c.customer_id AND t.status <> 'Cancelled'
    GROUP BY c.customer_id
),
scored AS (
    SELECT *,
           NTILE(4) OVER (ORDER BY recency_days DESC)  AS r_score,   -- 4 = most recent
           NTILE(4) OVER (ORDER BY frequency)          AS f_score,   -- 4 = most frequent
           NTILE(4) OVER (ORDER BY monetary)           AS m_score    -- 4 = highest spend
    FROM cust
    WHERE frequency > 0
),
segmented AS (
    SELECT customer_id, monetary, frequency, recency_days,
           CASE WHEN r_score >= 3 AND f_score >= 3 AND m_score >= 3 THEN '1 Champions'
                WHEN f_score >= 3 AND m_score >= 3                  THEN '2 At risk big spenders'
                WHEN r_score >= 3 AND f_score <= 2                  THEN '3 New / promising'
                WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2 THEN '5 Lost / low value'
                ELSE '4 Needs attention' END AS segment
    FROM scored
    UNION ALL
    SELECT customer_id, 0, 0, NULL, '6 Never bought' FROM cust WHERE frequency = 0
)
SELECT segment,
       COUNT(*)                                             AS customers,
       ROUND(AVG(monetary), 2)                              AS avg_spend,
       ROUND(AVG(frequency), 1)                             AS avg_orders,
       ROUND(AVG(recency_days), 0)                          AS avg_days_since_last,
       ROUND(SUM(monetary), 2)                              AS segment_revenue,
       ROUND(100.0 * SUM(monetary) / (SELECT SUM(monetary) FROM segmented), 1) AS revenue_share_pct
FROM segmented
GROUP BY segment
ORDER BY segment;

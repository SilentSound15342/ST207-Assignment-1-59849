PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------
-- PART A - integrity checks (expected: empty result sets)
-- ---------------------------------------------------------------------

-- A1. Foreign-key violations anywhere in the database (SQLite built-in)
PRAGMA foreign_key_check;

-- A2. Orders whose shipping/billing address belongs to ANOTHER customer
SELECT o.order_id
FROM CustomerOrder o
JOIN Address s ON s.address_id = o.shipping_address_id
JOIN Address b ON b.address_id = o.billing_address_id
WHERE s.customer_id <> o.customer_id OR b.customer_id <> o.customer_id;

-- A3. Paid/Shipped/Delivered orders NOT fully covered by completed payments
SELECT order_id, order_total, paid_total
FROM v_order_payment
WHERE order_id IN (SELECT order_id FROM CustomerOrder WHERE status IN ('Paid','Shipped','Delivered'))
  AND ROUND(paid_total - order_total, 2) < 0;

-- A4. Orders with no order lines at all (an order must contain >= 1 item: 1..N)
SELECT order_id FROM CustomerOrder
WHERE order_id NOT IN (SELECT order_id FROM OrderItem);

-- A5. shipped_at present <=> status Shipped/Delivered
SELECT order_id, status, shipped_at
FROM CustomerOrder
WHERE (status IN ('Shipped','Delivered') AND shipped_at IS NULL)
   OR (status NOT IN ('Shipped','Delivered') AND shipped_at IS NOT NULL);

-- A6. Specialisation: every Card payment has a CardPayment row, and no non-card payment has one
SELECT p.payment_id, p.method FROM Payment p
LEFT JOIN CardPayment cp ON cp.payment_id = p.payment_id
WHERE (p.method = 'Card' AND cp.payment_id IS NULL)
   OR (p.method <> 'Card' AND cp.payment_id IS NOT NULL);

-- A7. Reviews written before the customer's first non-cancelled purchase of that product
--     (data should model VERIFIED purchases only)
SELECT r.review_id
FROM Review r
WHERE NOT EXISTS (
    SELECT 1
    FROM CustomerOrder o
    JOIN OrderItem  oi ON oi.order_id = o.order_id
    JOIN ProductVariant v ON v.variant_id = oi.variant_id
    WHERE o.customer_id = r.customer_id AND v.product_id = r.product_id
      AND o.status = 'Delivered' AND o.order_date < r.review_date);

-- A8. Orders placed before the customer registered
SELECT o.order_id FROM CustomerOrder o JOIN Customer c USING (customer_id)
WHERE o.order_date < c.registered_at;

-- A9. Category hierarchy has no cycles (every category reaches a root in <= 5 steps)
WITH RECURSIVE up(category_id, node, depth) AS (
    SELECT category_id, parent_category_id, 1 FROM Category
    UNION ALL
    SELECT up.category_id, c.parent_category_id, up.depth + 1
    FROM up JOIN Category c ON c.category_id = up.node
    WHERE up.depth < 6)
SELECT category_id FROM up WHERE depth >= 6;

-- A10. Refunded payments only on cancelled orders
SELECT p.payment_id FROM Payment p JOIN CustomerOrder o USING (order_id)
WHERE p.status = 'Refunded' AND o.status <> 'Cancelled';

-- The checks A11-A16 independently verify rules that are also declared as UNIQUE and CHECK constraints in the schema.

-- A11. Duplicate e-mails, SKUs or payment references (each must be unique)
SELECT 'email' AS rule, email AS value FROM Customer GROUP BY email HAVING COUNT(*) > 1
UNION ALL
SELECT 'sku', sku FROM ProductVariant GROUP BY sku HAVING COUNT(*) > 1
UNION ALL
SELECT 'transaction_ref', transaction_ref FROM Payment GROUP BY transaction_ref HAVING COUNT(*) > 1;

-- A12. The same variant twice in one order or in one cart
SELECT 'order' AS entity, order_id AS id, variant_id FROM OrderItem GROUP BY order_id, variant_id HAVING COUNT(*) > 1
UNION ALL
SELECT 'cart', cart_id, variant_id FROM CartItem GROUP BY cart_id, variant_id HAVING COUNT(*) > 1;

-- A13. More than one review of the same product by the same customer
SELECT customer_id, product_id, COUNT(*) AS reviews
FROM Review
GROUP BY customer_id, product_id
HAVING COUNT(*) > 1;

-- A14. Ratings outside 1..5
SELECT review_id, rating FROM Review WHERE rating < 1 OR rating > 5;

-- A15. Non-positive quantities or prices, negative stock or shipping fee
SELECT 'OrderItem' AS tbl, order_item_id AS id FROM OrderItem WHERE quantity <= 0 OR unit_price_at_purchase < 0
UNION ALL
SELECT 'CartItem', cart_item_id FROM CartItem WHERE quantity <= 0
UNION ALL
SELECT 'ProductVariant', variant_id FROM ProductVariant WHERE unit_price <= 0 OR stock_quantity < 0
UNION ALL
SELECT 'CustomerOrder', order_id FROM CustomerOrder WHERE shipping_fee < 0
UNION ALL
SELECT 'Payment', payment_id FROM Payment WHERE amount <= 0;

-- A16. Values outside the allowed lists (order status, payment status and method, card network)
SELECT 'order status' AS rule, status AS value FROM CustomerOrder
 WHERE status NOT IN ('Pending', 'Paid', 'Shipped', 'Delivered', 'Cancelled')
UNION ALL
SELECT 'payment status', status FROM Payment
 WHERE status NOT IN ('Pending', 'Completed', 'Failed', 'Refunded')
UNION ALL
SELECT 'payment method', method FROM Payment
 WHERE method NOT IN ('Card', 'PayPal', 'Bank Transfer')
UNION ALL
SELECT 'card network', card_network FROM CardPayment
 WHERE card_network NOT IN ('Visa', 'Mastercard', 'Amex');

-- ---------------------------------------------------------------------
-- PART B - distribution summaries
-- ---------------------------------------------------------------------

-- B1. Row counts per table
SELECT 'Customer' AS tbl, COUNT(*) AS n FROM Customer UNION ALL
SELECT 'Address', COUNT(*) FROM Address UNION ALL
SELECT 'Category', COUNT(*) FROM Category UNION ALL
SELECT 'Product', COUNT(*) FROM Product UNION ALL
SELECT 'ProductVariant', COUNT(*) FROM ProductVariant UNION ALL
SELECT 'Cart', COUNT(*) FROM Cart UNION ALL
SELECT 'CartItem', COUNT(*) FROM CartItem UNION ALL
SELECT 'CustomerOrder', COUNT(*) FROM CustomerOrder UNION ALL
SELECT 'OrderItem', COUNT(*) FROM OrderItem UNION ALL
SELECT 'Payment', COUNT(*) FROM Payment UNION ALL
SELECT 'CardPayment', COUNT(*) FROM CardPayment UNION ALL
SELECT 'Review', COUNT(*) FROM Review;

-- B2. Orders and payments by status (accepted / declined / refunded payments are all present)
SELECT 'order' AS entity, status, COUNT(*) AS n FROM CustomerOrder GROUP BY status
UNION ALL
SELECT 'payment', status, COUNT(*) FROM Payment GROUP BY status;

-- B3. Products per top-level category (incl. the deliberately empty category)
SELECT c.name AS top_category, COUNT(p.product_id) AS n_products
FROM Category c
LEFT JOIN Category sub ON sub.parent_category_id = c.category_id
LEFT JOIN Category sub2 ON sub2.parent_category_id = sub.category_id
LEFT JOIN Product p ON p.category_id IN (c.category_id, sub.category_id, sub2.category_id)
WHERE c.parent_category_id IS NULL
GROUP BY c.category_id;

-- B4. Customer behaviour profile: 0 orders, 1-2, 3-7, 8+ (heavy users)
WITH n AS (SELECT c.customer_id, COUNT(o.order_id) AS orders
           FROM Customer c LEFT JOIN CustomerOrder o USING (customer_id)
           GROUP BY c.customer_id)
SELECT CASE WHEN orders = 0 THEN '0 (never ordered)'
            WHEN orders <= 2 THEN '1-2 (occasional)'
            WHEN orders <= 7 THEN '3-7 (regular)'
            ELSE '8+ (heavy)' END AS profile,
       COUNT(*) AS customers
FROM n GROUP BY profile ORDER BY MIN(orders);

-- B5. Review rating distribution
SELECT rating, COUNT(*) AS reviews FROM Review GROUP BY rating ORDER BY rating;

-- B6. Edge cases present in the data (each should be > 0)
SELECT 'orders with failed-then-successful payment' AS edge_case, COUNT(*) AS n FROM CustomerOrder o
 WHERE EXISTS (SELECT 1 FROM Payment p WHERE p.order_id=o.order_id AND p.status='Failed')
   AND EXISTS (SELECT 1 FROM Payment p WHERE p.order_id=o.order_id AND p.status='Completed')
UNION ALL SELECT 'split payments (2+ completed)', COUNT(*) FROM
 (SELECT order_id FROM Payment WHERE status='Completed' GROUP BY order_id HAVING COUNT(*) > 1)
UNION ALL SELECT 'cancelled & refunded orders', COUNT(DISTINCT order_id) FROM Payment WHERE status='Refunded'
UNION ALL SELECT 'customers with no cart & no order', COUNT(*) FROM Customer c
 WHERE NOT EXISTS (SELECT 1 FROM Cart ca WHERE ca.customer_id=c.customer_id)
   AND NOT EXISTS (SELECT 1 FROM CustomerOrder o WHERE o.customer_id=c.customer_id)
UNION ALL SELECT 'products with no reviews', COUNT(*) FROM v_product_rating WHERE review_count = 0
UNION ALL SELECT 'variants out of stock', COUNT(*) FROM ProductVariant WHERE stock_quantity = 0
UNION ALL SELECT 'categories with no products', COUNT(*) FROM Category c
 WHERE NOT EXISTS (SELECT 1 FROM Product p WHERE p.category_id = c.category_id)
   AND NOT EXISTS (SELECT 1 FROM Category s WHERE s.parent_category_id = c.category_id)
UNION ALL SELECT 'orders billed to a different address', COUNT(*) FROM CustomerOrder WHERE shipping_address_id <> billing_address_id
UNION ALL SELECT 'order lines priced below current list price (promo / older price level)', COUNT(*) FROM OrderItem oi
 JOIN ProductVariant v USING (variant_id) WHERE oi.unit_price_at_purchase < v.unit_price;

-- STEP 0 - check (expected: triggers = 11, orders = 916, shoe_stock = 3)
SELECT (SELECT COUNT(*) FROM sqlite_master WHERE type='trigger') AS triggers, (SELECT COUNT(*) FROM CustomerOrder) AS orders, (SELECT stock_quantity FROM ProductVariant WHERE sku='STR-031-0139') AS shoe_stock;

-- ================= TRIGGER 1: STOCK AVAILABILITY AND STOCK UPDATE =================
-- DEMO 1A (PASSES): add 2 of the 3 units in stock to the pending order 915
-- 1A-1  stock before (3)
SELECT sku, stock_quantity AS stock_before FROM ProductVariant WHERE sku = 'STR-031-0139';
-- 1A-2  accepted: the trigger takes 2 units out of stock
INSERT INTO OrderItem (quantity, unit_price_at_purchase, variant_id, order_id) SELECT 2, unit_price, variant_id, 915 FROM ProductVariant WHERE sku = 'STR-031-0139';
-- 1A-3  stock after (1)
SELECT sku, stock_quantity AS stock_after FROM ProductVariant WHERE sku = 'STR-031-0139';
-- 1A-4  the stock movement written by the trigger (order_id 915, change_qty -2, stock_after 1)
SELECT * FROM inventory_log WHERE log_id = (SELECT MAX(log_id) FROM inventory_log);

-- DEMO 1B (VIOLATION): 5 units requested, only 1 left
-- 1B-1  >>> MUST ERROR <<<  message pane: ERROR: insufficient stock for this product variant
INSERT INTO OrderItem (quantity, unit_price_at_purchase, variant_id, order_id) SELECT 5, unit_price, variant_id, 915 FROM ProductVariant WHERE sku = 'STR-031-0139';
-- 1B-2  stock is unchanged (1)
SELECT sku, stock_quantity AS stock_unchanged FROM ProductVariant WHERE sku = 'STR-031-0139';

-- ================= TRIGGER 2: ORDER LIFECYCLE AND PAYMENT CONSISTENCY =================
-- DEMO 2A (VIOLATION): order 915 has no COMPLETED payment, so it cannot be marked Paid
-- 2A-1  >>> MUST ERROR <<<  message pane: ERROR: completed payments do not cover the order total
UPDATE CustomerOrder SET status = 'Paid' WHERE order_id = 915;

-- DEMO 2B (VIOLATION): skipping the workflow, Pending -> Delivered
-- 2B-1  >>> MUST ERROR <<<  message pane: ERROR: invalid order status transition
UPDATE CustomerOrder SET status = 'Delivered' WHERE order_id = 915;

-- DEMO 2C (PASSES): order 910 is Paid with its payment complete, so it can be Shipped
-- 2C-1  accepted
UPDATE CustomerOrder SET status = 'Shipped' WHERE order_id = 910;
-- 2C-2  status Shipped, and shipped_at filled in BY THE TRIGGER (it was empty before)
SELECT order_id, status, order_date, shipped_at FROM CustomerOrder WHERE order_id = 910;
-- 2C-3  the change recorded by the trigger (order 910, Paid -> Shipped)
SELECT * FROM order_status_log WHERE log_id = (SELECT MAX(log_id) FROM order_status_log);

-- DEMO 2D (EDGE CASE, OPTIONAL): cancelling order 915 returns its stock and voids its pending payment
-- 2D-1  accepted
UPDATE CustomerOrder SET status = 'Cancelled' WHERE order_id = 915;
-- 2D-2  shoe stock back to 3 (the 2 units from demo 1A were returned)
SELECT sku, stock_quantity AS stock_after_cancel FROM ProductVariant WHERE sku = 'STR-031-0139';
-- 2D-3  the pending payment of order 915 is now Failed (voided)
SELECT payment_id, amount, status FROM Payment WHERE order_id = 915;

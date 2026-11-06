PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------
-- Log tables (like EMP_LOG in the seminar). Audit tables, not part of the business ER model.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS inventory_log (
    log_id        INTEGER PRIMARY KEY AUTOINCREMENT,
    variant_id    INTEGER NOT NULL,
    order_id      INTEGER,
    change_qty    INTEGER NOT NULL,          -- negative = stock taken, positive = stock returned
    stock_after   INTEGER NOT NULL,
    description   TEXT,
    logged_at     TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS order_status_log (
    log_id      INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id    INTEGER NOT NULL,
    old_status  TEXT,
    new_status  TEXT,
    logged_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

DROP TRIGGER IF EXISTS bef_insert_orderitem;
DROP TRIGGER IF EXISTS aft_insert_orderitem;
DROP TRIGGER IF EXISTS bef_update_orderitem;
DROP TRIGGER IF EXISTS aft_update_orderitem;
DROP TRIGGER IF EXISTS prevent_delete_paid_line;
DROP TRIGGER IF EXISTS aft_delete_orderitem;
DROP TRIGGER IF EXISTS bef_update_order_status;
DROP TRIGGER IF EXISTS aft_update_order_shipped;
DROP TRIGGER IF EXISTS aft_update_order_cancel;
DROP TRIGGER IF EXISTS aft_update_order_log;
DROP TRIGGER IF EXISTS bef_insert_payment;

-- #####################################################################
-- SITUATION 1: STOCK AVAILABILITY AND STOCK UPDATE (table OrderItem)
-- #####################################################################

-- BEFORE INSERT
-- Actions to be taken before inserting a row in the OrderItem table
CREATE TRIGGER bef_insert_orderitem BEFORE INSERT ON OrderItem
BEGIN
  -- Check the conditions that violate the trigger
  SELECT CASE
    WHEN ((SELECT status FROM CustomerOrder WHERE order_id = NEW.order_id) <> 'Pending')
    THEN RAISE(FAIL, 'ERROR: order lines can only be added to a Pending order')
    WHEN (NEW.quantity > (SELECT stock_quantity FROM ProductVariant WHERE variant_id = NEW.variant_id))
    THEN RAISE(FAIL, 'ERROR: insufficient stock for this product variant')
  END;
END;
-- Testing the trigger
-- INSERT INTO OrderItem (quantity, unit_price_at_purchase, variant_id, order_id) VALUES (50, 10, 139, 915);   -- fails: not enough stock
-- INSERT INTO OrderItem (quantity, unit_price_at_purchase, variant_id, order_id) VALUES (1, 10, 139, 910);    -- fails: order 910 is not Pending

-- AFTER INSERT
-- Actions to be taken after inserting a row in the OrderItem table
CREATE TRIGGER aft_insert_orderitem AFTER INSERT ON OrderItem
BEGIN
  -- take the units out of stock
  UPDATE ProductVariant
     SET stock_quantity = stock_quantity - NEW.quantity
   WHERE variant_id = NEW.variant_id;
  -- log the stock movement
  INSERT INTO inventory_log (variant_id, order_id, change_qty, stock_after, description)
  VALUES (NEW.variant_id, NEW.order_id, -NEW.quantity,
          (SELECT stock_quantity FROM ProductVariant WHERE variant_id = NEW.variant_id), 'Order line placed');
END;
-- Testing the trigger (order 915 is the only Pending order; variant 139 has 3 units in stock)
-- INSERT INTO OrderItem (quantity, unit_price_at_purchase, variant_id, order_id) VALUES (2, 109.99, 139, 915);
-- SELECT * FROM inventory_log;   -- one new row; the stock of variant 139 is now 1

-- BEFORE UPDATE
-- Actions to be taken before changing the quantity of an order line
CREATE TRIGGER bef_update_orderitem BEFORE UPDATE OF quantity ON OrderItem
BEGIN
  SELECT CASE
    WHEN ((SELECT status FROM CustomerOrder WHERE order_id = OLD.order_id) <> 'Pending')
    THEN RAISE(FAIL, 'ERROR: quantities can only be changed on a Pending order')
    WHEN ((NEW.quantity - OLD.quantity) > (SELECT stock_quantity FROM ProductVariant WHERE variant_id = OLD.variant_id))
    THEN RAISE(FAIL, 'ERROR: insufficient stock for the increased quantity')
  END;
END;
-- Testing the trigger
-- UPDATE OrderItem SET quantity = 9999 WHERE order_item_id = 1500;   -- fails: not enough stock for the increase

-- AFTER UPDATE
-- Actions to be taken after changing the quantity: apply only the difference to the stock
CREATE TRIGGER aft_update_orderitem AFTER UPDATE OF quantity ON OrderItem
WHEN NEW.quantity <> OLD.quantity
BEGIN
  UPDATE ProductVariant
     SET stock_quantity = stock_quantity + (OLD.quantity - NEW.quantity)
   WHERE variant_id = OLD.variant_id;
  INSERT INTO inventory_log (variant_id, order_id, change_qty, stock_after, description)
  VALUES (OLD.variant_id, OLD.order_id, OLD.quantity - NEW.quantity,
          (SELECT stock_quantity FROM ProductVariant WHERE variant_id = OLD.variant_id),
          'Update quantity from ' || OLD.quantity || ' to ' || NEW.quantity);
END;
-- Testing the trigger
-- UPDATE OrderItem SET quantity = 1 WHERE order_item_id = 1500;   -- stock goes up by the difference

-- BEFORE DELETE ("safe delete", as in seminar E6)
-- Block the deletion of a line of an order that is already paid, shipped or delivered
CREATE TRIGGER prevent_delete_paid_line
BEFORE DELETE ON OrderItem
FOR EACH ROW
WHEN EXISTS (SELECT 1 FROM CustomerOrder WHERE order_id = OLD.order_id AND status IN ('Paid', 'Shipped', 'Delivered'))
BEGIN
  SELECT RAISE(FAIL, 'ERROR: cannot delete a line of an order that is already paid or shipped');
END;
-- Testing the trigger
-- DELETE FROM OrderItem WHERE order_id = 910;   -- fails: order 910 is Paid

-- AFTER DELETE
-- Actions to be taken after deleting a line of a still-Pending order: give the stock back
-- (cancelled orders are restocked by aft_update_order_cancel, so units are never returned twice)
CREATE TRIGGER aft_delete_orderitem AFTER DELETE ON OrderItem
FOR EACH ROW
WHEN EXISTS (SELECT 1 FROM CustomerOrder WHERE order_id = OLD.order_id AND status = 'Pending')
BEGIN
  UPDATE ProductVariant
     SET stock_quantity = stock_quantity + OLD.quantity
   WHERE variant_id = OLD.variant_id;
  INSERT INTO inventory_log (variant_id, order_id, change_qty, stock_after, description)
  VALUES (OLD.variant_id, OLD.order_id, OLD.quantity,
          (SELECT stock_quantity FROM ProductVariant WHERE variant_id = OLD.variant_id),
          'Deleted on ' || datetime('now', 'localtime'));
END;
-- Testing the trigger
-- DELETE FROM OrderItem WHERE order_item_id = 1500;   -- the units return to stock (order 915 is Pending)

-- #####################################################################
-- SITUATION 2: ORDER LIFECYCLE AND PAYMENT CONSISTENCY (tables CustomerOrder, Payment)
--   Legal flow:  Pending -> Paid -> Shipped -> Delivered
--                Pending -> Cancelled,  Paid -> Cancelled
-- #####################################################################

-- BEFORE UPDATE
-- Actions to be taken before changing the status of an order
CREATE TRIGGER bef_update_order_status BEFORE UPDATE OF status ON CustomerOrder
FOR EACH ROW
WHEN NEW.status <> OLD.status
BEGIN
  SELECT CASE
    WHEN NOT ( (OLD.status = 'Pending' AND NEW.status IN ('Paid', 'Cancelled'))
            OR (OLD.status = 'Paid'    AND NEW.status IN ('Shipped', 'Cancelled'))
            OR (OLD.status = 'Shipped' AND NEW.status = 'Delivered') )
    THEN RAISE(FAIL, 'ERROR: invalid order status transition')
    WHEN (NEW.status = 'Paid' AND NOT EXISTS (SELECT 1 FROM OrderItem WHERE order_id = OLD.order_id))
    THEN RAISE(FAIL, 'ERROR: an order with no items cannot be marked as Paid')
    WHEN (NEW.status = 'Paid'
          AND ((SELECT SUM(amount) FROM Payment WHERE order_id = OLD.order_id AND status = 'Completed') IS NULL
            OR ROUND((SELECT SUM(amount) FROM Payment WHERE order_id = OLD.order_id AND status = 'Completed')
                   - (SELECT SUM(quantity * unit_price_at_purchase) FROM OrderItem WHERE order_id = OLD.order_id)
                   - OLD.shipping_fee, 2) < 0))
    THEN RAISE(FAIL, 'ERROR: completed payments do not cover the order total')
  END;
END;
-- Testing the trigger (order 915 is Pending with no completed payment; order 910 is Paid and fully paid)
-- UPDATE CustomerOrder SET status = 'Delivered' WHERE order_id = 915;   -- fails: invalid status transition
-- UPDATE CustomerOrder SET status = 'Paid' WHERE order_id = 915;        -- fails: no completed payment

-- AFTER UPDATE
-- Actions to be taken after an order is set to Shipped: stamp shipped_at
CREATE TRIGGER aft_update_order_shipped AFTER UPDATE OF status ON CustomerOrder
WHEN NEW.status = 'Shipped' AND NEW.shipped_at IS NULL
BEGIN
  UPDATE CustomerOrder SET shipped_at = datetime('now') WHERE order_id = NEW.order_id;
END;
-- Testing the trigger
-- UPDATE CustomerOrder SET status = 'Shipped' WHERE order_id = 910;
-- SELECT order_id, status, shipped_at FROM CustomerOrder WHERE order_id = 910;   -- shipped_at is filled in

-- AFTER UPDATE
-- Actions to be taken after an order is Cancelled: return the stock, refund completed payments, void pending ones
CREATE TRIGGER aft_update_order_cancel AFTER UPDATE OF status ON CustomerOrder
WHEN NEW.status = 'Cancelled' AND OLD.status <> 'Cancelled'
BEGIN
  UPDATE ProductVariant
     SET stock_quantity = stock_quantity +
         (SELECT oi.quantity FROM OrderItem oi
           WHERE oi.order_id = NEW.order_id AND oi.variant_id = ProductVariant.variant_id)
   WHERE variant_id IN (SELECT variant_id FROM OrderItem WHERE order_id = NEW.order_id);

  INSERT INTO inventory_log (variant_id, order_id, change_qty, stock_after, description)
  SELECT oi.variant_id, NEW.order_id, oi.quantity, v.stock_quantity, 'Restock: order cancelled'
    FROM OrderItem oi JOIN ProductVariant v ON v.variant_id = oi.variant_id
   WHERE oi.order_id = NEW.order_id;

  UPDATE Payment SET status = 'Refunded' WHERE order_id = NEW.order_id AND status = 'Completed';
  UPDATE Payment SET status = 'Failed'   WHERE order_id = NEW.order_id AND status = 'Pending';
END;
-- Testing the trigger
-- UPDATE CustomerOrder SET status = 'Cancelled' WHERE order_id = 915;   -- stock returned, pending payment becomes Failed

-- AFTER UPDATE
-- Actions to be taken after any status change: log it
CREATE TRIGGER aft_update_order_log AFTER UPDATE OF status ON CustomerOrder
WHEN NEW.status <> OLD.status
BEGIN
  INSERT INTO order_status_log (order_id, old_status, new_status)
  VALUES (OLD.order_id, OLD.status, NEW.status);
END;
-- Testing the trigger
-- SELECT * FROM order_status_log;   -- one row for every status change made above

-- BEFORE INSERT
-- Actions to be taken before inserting a payment
CREATE TRIGGER bef_insert_payment BEFORE INSERT ON Payment
BEGIN
  SELECT CASE
    WHEN ((SELECT status FROM CustomerOrder WHERE order_id = NEW.order_id) = 'Cancelled')
    THEN RAISE(FAIL, 'ERROR: cannot take a payment for a cancelled order')
    WHEN (NEW.status = 'Completed'
          AND ROUND(NEW.amount, 2) >
              ROUND((CASE WHEN (SELECT SUM(quantity * unit_price_at_purchase) FROM OrderItem WHERE order_id = NEW.order_id) IS NULL THEN 0
                          ELSE (SELECT SUM(quantity * unit_price_at_purchase) FROM OrderItem WHERE order_id = NEW.order_id) END)
                  + (SELECT shipping_fee FROM CustomerOrder WHERE order_id = NEW.order_id)
                  - (CASE WHEN (SELECT SUM(amount) FROM Payment WHERE order_id = NEW.order_id AND status = 'Completed') IS NULL THEN 0
                          ELSE (SELECT SUM(amount) FROM Payment WHERE order_id = NEW.order_id AND status = 'Completed') END), 2) + 0.001)
    THEN RAISE(FAIL, 'ERROR: payment exceeds the outstanding balance of the order')
  END;
END;
-- Testing the trigger
-- INSERT INTO Payment (amount, method, status, transaction_ref, order_id) VALUES (10, 'PayPal', 'Completed', 'T-1', 910);   -- fails: order 910 is already fully paid

-- Removing a trigger (as in the seminar):  DROP TRIGGER <TRIGGER_NAME>;

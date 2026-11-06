PRAGMA foreign_keys = ON;   -- SQLite does NOT enforce FKs unless this is ON (per connection)

-- ---------- clean slate (children first) ----------
DROP VIEW  IF EXISTS v_order_payment;
DROP VIEW  IF EXISTS v_product_rating;
DROP VIEW  IF EXISTS v_order_total;
DROP TABLE IF EXISTS Review;
DROP TABLE IF EXISTS CardPayment;
DROP TABLE IF EXISTS Payment;
DROP TABLE IF EXISTS OrderItem;
DROP TABLE IF EXISTS CustomerOrder;
DROP TABLE IF EXISTS CartItem;
DROP TABLE IF EXISTS Cart;
DROP TABLE IF EXISTS ProductVariant;
DROP TABLE IF EXISTS Product;
DROP TABLE IF EXISTS Category;
DROP TABLE IF EXISTS Address;
DROP TABLE IF EXISTS Customer;

-- ---------------------------------------------------------------------
-- CUSTOMER  (strong entity)
-- Dates are stored as ISO-8601 TEXT 'YYYY-MM-DD HH:MM:SS' (SQLite has no
-- DATE type).
-- ---------------------------------------------------------------------
CREATE TABLE Customer (
    customer_id    INTEGER      PRIMARY KEY AUTOINCREMENT,
    first_name     TEXT         NOT NULL,
    last_name      TEXT         NOT NULL,
    email          TEXT         NOT NULL UNIQUE,
    registered_at  TEXT         NOT NULL DEFAULT (datetime('now'))
);

-- ---------------------------------------------------------------------
-- ADDRESS  (1 Customer : N Address; mandatory on the Address side)
-- is_active = soft delete (addresses referenced by old orders must stay).
-- ---------------------------------------------------------------------
CREATE TABLE Address (
    address_id   INTEGER  PRIMARY KEY AUTOINCREMENT,
    street       TEXT     NOT NULL,
    city         TEXT     NOT NULL,
    postcode     TEXT     NOT NULL,
    country      TEXT     NOT NULL,
    is_active    INTEGER  NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    customer_id  INTEGER  NOT NULL,
    FOREIGN KEY (customer_id) REFERENCES Customer (customer_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------
-- CATEGORY  (recursive 1:N "parent of"; NULL parent = top-level category)
-- ---------------------------------------------------------------------
CREATE TABLE Category (
    category_id         INTEGER  PRIMARY KEY AUTOINCREMENT,
    name                TEXT     NOT NULL,
    parent_category_id  INTEGER,
    FOREIGN KEY (parent_category_id) REFERENCES Category (category_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------
-- PRODUCT  (what is displayed/reviewed) vs PRODUCTVARIANT (what is sold)
-- ---------------------------------------------------------------------
CREATE TABLE Product (
    product_id   INTEGER  PRIMARY KEY AUTOINCREMENT,
    name         TEXT     NOT NULL,
    description  TEXT     NOT NULL,
    brand        TEXT     NOT NULL,
    category_id  INTEGER  NOT NULL,
    FOREIGN KEY (category_id) REFERENCES Category (category_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE ProductVariant (
    variant_id      INTEGER        PRIMARY KEY AUTOINCREMENT,
    sku             TEXT           NOT NULL UNIQUE,
    unit_price      DECIMAL(10,2)  NOT NULL CHECK (unit_price > 0),
    stock_quantity  INTEGER        NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    size            TEXT,          -- optional: not every product has a size
    colour          TEXT,          -- optional
    product_id      INTEGER        NOT NULL,
    FOREIGN KEY (product_id) REFERENCES Product (product_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------
-- CART (1:0..1 with Customer -> UNIQUE foreign key) and CARTITEM
-- A cart has no meaning without its customer / its items without the cart,
-- so deletes cascade.
-- ---------------------------------------------------------------------
CREATE TABLE Cart (
    cart_id      INTEGER  PRIMARY KEY AUTOINCREMENT,
    created_at   TEXT     NOT NULL DEFAULT (datetime('now')),
    customer_id  INTEGER  NOT NULL UNIQUE,      -- UNIQUE => at most one cart per customer
    FOREIGN KEY (customer_id) REFERENCES Customer (customer_id)
        ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE CartItem (
    cart_item_id  INTEGER  PRIMARY KEY AUTOINCREMENT,
    quantity      INTEGER  NOT NULL CHECK (quantity > 0),
    created_at    TEXT     NOT NULL DEFAULT (datetime('now')),
    cart_id       INTEGER  NOT NULL,
    variant_id    INTEGER  NOT NULL,
    UNIQUE (cart_id, variant_id),
    FOREIGN KEY (cart_id)    REFERENCES Cart (cart_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (variant_id) REFERENCES ProductVariant (variant_id)
        ON UPDATE CASCADE ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- CUSTOMERORDER  (named so to avoid the reserved word ORDER)
-- order_total is a DERIVED attribute -> NOT stored; see view v_order_total.
-- shipped_at is NULL until the order is shipped (optional attribute).
-- ---------------------------------------------------------------------
CREATE TABLE CustomerOrder (
    order_id             INTEGER        PRIMARY KEY AUTOINCREMENT,
    order_date           TEXT           NOT NULL DEFAULT (datetime('now')),
    status               TEXT           NOT NULL DEFAULT 'Pending' CHECK (status IN ('Pending', 'Paid', 'Shipped', 'Delivered', 'Cancelled')),
    shipping_fee         DECIMAL(10,2)  NOT NULL DEFAULT 0 CHECK (shipping_fee >= 0),
    shipped_at           TEXT,
    customer_id          INTEGER        NOT NULL,
    shipping_address_id  INTEGER        NOT NULL,
    billing_address_id   INTEGER        NOT NULL,
    FOREIGN KEY (customer_id) REFERENCES Customer (customer_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (shipping_address_id) REFERENCES Address (address_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (billing_address_id)  REFERENCES Address (address_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------
-- ORDERITEM  (resolves the M:N Order <-> ProductVariant; carries quantity
-- and unit_price_at_purchase = price snapshot so later price changes do
-- not rewrite history).
-- ---------------------------------------------------------------------
CREATE TABLE OrderItem (
    order_item_id          INTEGER        PRIMARY KEY AUTOINCREMENT,
    quantity               INTEGER        NOT NULL CHECK (quantity > 0),
    unit_price_at_purchase DECIMAL(10,2)  NOT NULL CHECK (unit_price_at_purchase >= 0),
    variant_id             INTEGER        NOT NULL,
    order_id               INTEGER        NOT NULL,
    UNIQUE (order_id, variant_id),
    FOREIGN KEY (variant_id) REFERENCES ProductVariant (variant_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (order_id)   REFERENCES CustomerOrder (order_id)
        ON UPDATE CASCADE ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- PAYMENT (1 Order : 0..N Payments -> failed attempts, retries, split pay)
-- CARDPAYMENT = partial, disjoint specialisation; PK is also FK
-- (one-to-one subclass mapping). The rule "method='Card' => has a CardPayment
-- row" is checked in Q4_Data_Validation_FINAL.sql.
-- ---------------------------------------------------------------------
CREATE TABLE Payment (
    payment_id       INTEGER        PRIMARY KEY AUTOINCREMENT,
    amount           DECIMAL(10,2)  NOT NULL CHECK (amount > 0),
    method           TEXT           NOT NULL CHECK (method IN ('Card', 'PayPal', 'Bank Transfer')),
    status           TEXT           NOT NULL CHECK (status IN ('Pending', 'Completed', 'Failed', 'Refunded')),
    attempted_at     TEXT           NOT NULL DEFAULT (datetime('now')),
    transaction_ref  TEXT           NOT NULL UNIQUE,
    order_id         INTEGER        NOT NULL,
    FOREIGN KEY (order_id) REFERENCES CustomerOrder (order_id)
        ON UPDATE CASCADE ON DELETE RESTRICT       -- financial records are never silently deleted
);

CREATE TABLE CardPayment (
    payment_id    INTEGER  PRIMARY KEY,
    card_network  TEXT     NOT NULL CHECK (card_network IN ('Visa', 'Mastercard', 'Amex')),
    card_last4    TEXT     NOT NULL,
    FOREIGN KEY (payment_id) REFERENCES Payment (payment_id)
        ON UPDATE CASCADE ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- REVIEW (Customer N:M Product resolved as an entity with its own key).
-- Assumption: one review per customer per product (checked in file 02b).
-- comment is optional (rating-only reviews).
-- ---------------------------------------------------------------------
CREATE TABLE Review (
    review_id    INTEGER  PRIMARY KEY AUTOINCREMENT,
    rating       INTEGER  NOT NULL CHECK (rating BETWEEN 1 AND 5),
    review_date  TEXT     NOT NULL DEFAULT (datetime('now')),
    comment      TEXT,
    customer_id  INTEGER  NOT NULL,
    product_id   INTEGER  NOT NULL,
    UNIQUE (customer_id, product_id),
    FOREIGN KEY (customer_id) REFERENCES Customer (customer_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (product_id)  REFERENCES Product (product_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------
-- INDEXES on foreign keys / frequent filters (SQLite does not index FKs
-- automatically; UNIQUE constraints above already create their own).
-- ---------------------------------------------------------------------
CREATE INDEX idx_address_customer  ON Address (customer_id);
CREATE INDEX idx_product_category  ON Product (category_id);
CREATE INDEX idx_variant_product   ON ProductVariant (product_id);
CREATE INDEX idx_order_customer    ON CustomerOrder (customer_id, order_date);
CREATE INDEX idx_order_status      ON CustomerOrder (status);
CREATE INDEX idx_orderitem_variant ON OrderItem (variant_id);
CREATE INDEX idx_payment_order     ON Payment (order_id);
CREATE INDEX idx_review_product    ON Review (product_id);
CREATE INDEX idx_category_parent   ON Category (parent_category_id);

-- =====================================================================
-- VIEWS - used for the two DERIVED attributes in the ER model
-- (order_total, avg_rating) plus one helper view for the triggers. A view stores no
-- data, so derived values can never go stale (lecture W4 "View").
-- =====================================================================

-- order_total = SUM(quantity * price snapshot) + shipping_fee
-- LEFT JOIN keeps (empty) orders that have no lines yet -> items_total = 0
CREATE VIEW v_order_total AS
SELECT o.order_id,
       o.customer_id,
       o.order_date,
       o.status,
       CASE WHEN SUM(oi.quantity * oi.unit_price_at_purchase) IS NULL THEN 0
            ELSE SUM(oi.quantity * oi.unit_price_at_purchase) END            AS items_total,
       o.shipping_fee,
       ROUND(CASE WHEN SUM(oi.quantity * oi.unit_price_at_purchase) IS NULL THEN 0
                  ELSE SUM(oi.quantity * oi.unit_price_at_purchase) END
             + o.shipping_fee, 2)                                            AS order_total
FROM CustomerOrder AS o
LEFT JOIN OrderItem AS oi ON oi.order_id = o.order_id
GROUP BY o.order_id;

-- avg_rating (derived attribute of Product); products with no review get 0 reviews / NULL avg
CREATE VIEW v_product_rating AS
SELECT p.product_id,
       p.name,
       p.category_id,
       COUNT(r.review_id)          AS review_count,
       ROUND(AVG(r.rating), 2)     AS avg_rating
FROM Product AS p
LEFT JOIN Review AS r ON r.product_id = p.product_id
GROUP BY p.product_id;

-- money actually received vs. money owed per order (used by trigger 2)
CREATE VIEW v_order_payment AS
SELECT t.order_id,
       t.order_total,
       CASE WHEN (SELECT SUM(p.amount) FROM Payment p
                   WHERE p.order_id = t.order_id AND p.status = 'Completed') IS NULL THEN 0
            ELSE (SELECT SUM(p.amount) FROM Payment p
                   WHERE p.order_id = t.order_id AND p.status = 'Completed') END AS paid_total
FROM v_order_total AS t;

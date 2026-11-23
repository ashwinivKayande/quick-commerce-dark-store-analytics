-- =====================================================
-- STEP 3: Database + Tables (MySQL)
-- MySQL Workbench me poora paste karo aur Run (bijli wala icon) dabao
-- =====================================================

DROP DATABASE IF EXISTS dark_store_db;
CREATE DATABASE dark_store_db;
USE dark_store_db;

-- 1. dark_stores
CREATE TABLE dark_stores (
    store_id        INT PRIMARY KEY,
    city            VARCHAR(50),
    area            VARCHAR(50),
    store_size_sqft INT,
    monthly_rent    INT
);

-- 2. products
CREATE TABLE products (
    product_id      INT PRIMARY KEY,
    product_name    VARCHAR(100),
    category        VARCHAR(50),
    mrp             DECIMAL(10,2),
    cost_price      DECIMAL(10,2),
    shelf_life_days INT
);

-- 3. customers
CREATE TABLE customers (
    customer_id INT PRIMARY KEY,
    city        VARCHAR(50),
    signup_date DATE,
    segment     VARCHAR(50)
);

-- 4. delivery_partners
CREATE TABLE delivery_partners (
    partner_id  INT PRIMARY KEY,
    store_id    INT,
    shift       VARCHAR(20),
    rating      DECIMAL(2,1),
    joined_date DATE,
    FOREIGN KEY (store_id) REFERENCES dark_stores(store_id)
);

-- 5. orders
CREATE TABLE orders (
    order_id          INT PRIMARY KEY,
    customer_id       INT,
    store_id          INT,
    partner_id        INT,
    order_time        DATETIME,
    delivery_time_min DECIMAL(5,1) NULL,   -- Cancelled orders me NULL rahega
    delivery_fee      INT,
    payment_mode      VARCHAR(20),
    is_rainy_day      TINYINT,
    status            VARCHAR(20),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    FOREIGN KEY (store_id)    REFERENCES dark_stores(store_id),
    FOREIGN KEY (partner_id)  REFERENCES delivery_partners(partner_id)
);

-- 6. order_items
CREATE TABLE order_items (
    order_item_id INT PRIMARY KEY,
    order_id      INT,
    product_id    INT,
    quantity      INT,
    selling_price DECIMAL(10,2),
    FOREIGN KEY (order_id)   REFERENCES orders(order_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- 7. inventory_daily
CREATE TABLE inventory_daily (
    inventory_id  INT PRIMARY KEY,
    `date`        DATE,
    store_id      INT,
    product_id    INT,
    stockout_flag TINYINT,
    opening_stock INT,
    closing_stock INT,
    units_wasted  INT,
    FOREIGN KEY (store_id)   REFERENCES dark_stores(store_id),
    FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- Speed ke liye indexes (analysis queries tez chalengi)
CREATE INDEX idx_orders_time     ON orders(order_time);
CREATE INDEX idx_orders_store    ON orders(store_id);
CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_items_order     ON order_items(order_id);
CREATE INDEX idx_inv_store_date  ON inventory_daily(store_id, `date`);

SHOW TABLES;

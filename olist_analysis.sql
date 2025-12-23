CREATE DATABASE olist_store;
SET GLOBAL local_infile = 1;
USE olist_store;

CREATE TABLE orders (
    order_id VARCHAR(50),
    customer_id VARCHAR(50),
    order_status VARCHAR(20),
    order_purchase_timestamp VARCHAR(30),
    order_approved_at VARCHAR(30),
    order_delivered_carrier_date VARCHAR(30),
    order_delivered_customer_date VARCHAR(30),
    order_estimated_delivery_date VARCHAR(30));

/*
  Operation: Bulk Data Ingestion (Correction)
  Fix: Replaced backslashes (\) with forward slashes (/) to prevent 
       escape character errors.
*/

LOAD DATA LOCAL INFILE 'C:/Users/cimma/Desktop/Brazilian E-Commerce Public Dataset by Olist/olist_orders_dataset.csv'
INTO TABLE orders
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

USE olist_store;

-- Table 1: Order Items (The products in each order)
DROP TABLE IF EXISTS order_items;
CREATE TABLE order_items (
    order_id VARCHAR(50),
    order_item_id VARCHAR(10),
    product_id VARCHAR(50),
    seller_id VARCHAR(50),
    shipping_limit_date VARCHAR(30),
    price VARCHAR(20),        -- Storing as text to fix later
    freight_value VARCHAR(20) -- Storing as text to fix later
);

-- Table 2: Customers (Who bought the items)
DROP TABLE IF EXISTS customers;
CREATE TABLE customers (
    customer_id VARCHAR(50),
    customer_unique_id VARCHAR(50),
    customer_zip_code_prefix VARCHAR(10),
    customer_city VARCHAR(50),
    customer_state VARCHAR(5)
);

-- Load Order Items Data
LOAD DATA LOCAL INFILE 'C:/Users/cimma/Desktop/Brazilian E-Commerce Public Dataset by Olist/olist_order_items_dataset.csv'
INTO TABLE order_items
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- Load Customers Data
LOAD DATA LOCAL INFILE 'C:/Users/cimma/Desktop/Brazilian E-Commerce Public Dataset by Olist/olist_customers_dataset.csv'
INTO TABLE customers
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT count(*) FROM order_items;

USE olist_store;

-- 1. FORCE PERMISSION
SET GLOBAL local_infile = 1;

-- 2. RESTORE CUSTOMERS (The missing table)
DROP TABLE IF EXISTS customers;
CREATE TABLE customers (
    customer_id VARCHAR(50),
    customer_unique_id VARCHAR(50),
    customer_zip_code_prefix VARCHAR(10),
    customer_city VARCHAR(50),
    customer_state VARCHAR(5)
);

LOAD DATA LOCAL INFILE 'C:/Users/cimma/Desktop/Brazilian E-Commerce Public Dataset by Olist/olist_customers_dataset.csv'
INTO TABLE customers
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- 3. FIX ORDERS (Remove Duplicates -> The "One" Side)
DROP TABLE IF EXISTS _fact_orders;
CREATE TABLE _fact_orders AS
SELECT DISTINCT 
    order_id,
    customer_id,
    order_status,
    STR_TO_DATE(NULLIF(order_purchase_timestamp, ''), '%Y-%m-%d %H:%i:%s') as purchase_timestamp,
    STR_TO_DATE(NULLIF(order_delivered_customer_date, ''), '%Y-%m-%d %H:%i:%s') as delivery_date,
    STR_TO_DATE(NULLIF(order_estimated_delivery_date, ''), '%Y-%m-%d %H:%i:%s') as estimated_delivery_date
FROM orders;

-- 4. FIX ITEMS (Remove Duplicates -> The "Many" Side)
DROP TABLE IF EXISTS _fact_items;
CREATE TABLE _fact_items AS
SELECT DISTINCT
    order_id,
    product_id,
    seller_id,
    CAST(price AS DECIMAL(10,2)) as price,
    CAST(freight_value AS DECIMAL(10,2)) as freight_value
FROM order_items;

USE olist_store;

-- 1. Create & Load PRODUCTS
DROP TABLE IF EXISTS products;
CREATE TABLE products (
    product_id VARCHAR(50),
    product_category_name VARCHAR(50),
    product_name_lenght VARCHAR(10),
    product_description_lenght VARCHAR(10),
    product_photos_qty VARCHAR(10),
    product_weight_g VARCHAR(10),
    product_length_cm VARCHAR(10),
    product_height_cm VARCHAR(10),
    product_width_cm VARCHAR(10)
);

LOAD DATA LOCAL INFILE 'C:/Users/cimma/Desktop/Brazilian E-Commerce Public Dataset by Olist/olist_products_dataset.csv'
INTO TABLE products
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 ROWS;

-- 2. Create & Load SELLERS
DROP TABLE IF EXISTS sellers;
CREATE TABLE sellers (
    seller_id VARCHAR(50),
    seller_zip_code_prefix VARCHAR(10),
    seller_city VARCHAR(50),
    seller_state VARCHAR(5)
);

LOAD DATA LOCAL INFILE 'C:/Users/cimma/Desktop/Brazilian E-Commerce Public Dataset by Olist/olist_sellers_dataset.csv'
INTO TABLE sellers
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 ROWS;

/*
  Requirement: Create Delivery_Status column
  Logic: IF delivery > estimated THEN 'Late' ELSE 'On Time'
*/

-- 1. Add the empty column
ALTER TABLE _fact_orders ADD COLUMN delivery_status VARCHAR(20);

-- 2. Populate it using CASE
SET SQL_SAFE_UPDATES = 0; -- Turn off safety lock
UPDATE _fact_orders 
SET delivery_status = CASE 
    WHEN delivery_date > estimated_delivery_date THEN 'Late'
    WHEN delivery_date IS NULL THEN 'Undefined' 
    ELSE 'On Time' 
END;
SET SQL_SAFE_UPDATES = 1; -- Turn safety lock back on

SELECT delivery_status, COUNT(*) 
FROM _fact_orders 
GROUP BY delivery_status;

USE olist_store;
SET GLOBAL local_infile = 1;

-- 1. Create a temporary staging table
DROP TABLE IF EXISTS customers_raw;
CREATE TABLE customers_raw (
    customer_id VARCHAR(50),
    customer_unique_id VARCHAR(50),
    customer_zip_code_prefix VARCHAR(10),
    customer_city VARCHAR(50),
    customer_state VARCHAR(5)
);

-- 2. Load the raw data into the staging table
LOAD DATA LOCAL INFILE 'C:/Users/cimma/Desktop/Brazilian E-Commerce Public Dataset by Olist/olist_customers_dataset.csv'
INTO TABLE customers_raw
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 ROWS;

-- 3. Create the FINAL table using ONLY unique rows
DROP TABLE IF EXISTS customers;
CREATE TABLE customers AS
SELECT DISTINCT * FROM customers_raw;

-- 4. Clean up the mess
DROP TABLE customers_raw;

SELECT customer_id, COUNT(*) 
FROM customers 
GROUP BY customer_id 
HAVING COUNT(*) > 1;

/*
  =============================================================================
  PART 2: ANALYTICAL LAYER (The "Why" behind the data)
  -----------------------------------------------------------------------------
  The following queries demonstrate SQL Logic (CTEs, CASE, Joins) used to 
  analyze Logistics Performance and Revenue Impact.
  =============================================================================
*/

-- QUERY 1: State-Level Logistics Performance (CTE + Window Logic)
-- Business Question: Which states have the worst shipping delays?
-- Skills: CTE, JOIN, DATEDIFF, CASE Statement for Categorization

WITH state_logistics AS (
    SELECT 
        c.customer_state,
        o.order_id,
        DATEDIFF(o.delivery_date, o.estimated_delivery_date) AS delay_days,
        -- Categorize each specific order
        CASE 
            WHEN DATEDIFF(o.delivery_date, o.estimated_delivery_date) > 3 THEN 'Major Delay'
            WHEN DATEDIFF(o.delivery_date, o.estimated_delivery_date) > 0 THEN 'Minor Delay'
            ELSE 'On Time'
        END AS shipping_performance
    FROM _fact_orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.delivery_date IS NOT NULL
)
SELECT 
    customer_state,
    COUNT(order_id) AS total_orders,
    AVG(delay_days) AS avg_delay_days,
    -- Calculate the % of orders that were "Major Delays" per state
    SUM(CASE WHEN shipping_performance = 'Major Delay' THEN 1 ELSE 0 END) AS critical_issues_count
FROM state_logistics
GROUP BY customer_state
HAVING total_orders > 100 -- Filter for relevant sample sizes
ORDER BY avg_delay_days DESC;


-- QUERY 2: Revenue Impact of "Fast Shipping" (CTE + Financials)
-- Business Question: How much revenue is generated by orders delivered in under 3 days?
-- Skills: CTE, Subquery, Financial Aggregation

WITH fast_shipping_orders AS (
    SELECT 
        order_id,
        DATEDIFF(delivery_date, purchase_timestamp) AS shipping_days
    FROM _fact_orders
    WHERE DATEDIFF(delivery_date, purchase_timestamp) <= 3 -- The "Fast" definition
)
SELECT 
    'Fast Shipping (< 3 Days)' AS category,
    COUNT(fs.order_id) AS total_orders,
    ROUND(SUM(fi.price), 2) AS total_revenue
FROM fast_shipping_orders fs
JOIN _fact_items fi ON fs.order_id = fi.order_id

UNION ALL

-- Compare against Standard Shipping
SELECT 
    'Standard Shipping (> 3 Days)' AS category,
    COUNT(o.order_id) AS total_orders,
    ROUND(SUM(fi.price), 2) AS total_revenue
FROM _fact_orders o
JOIN _fact_items fi ON o.order_id = fi.order_id
WHERE DATEDIFF(o.delivery_date, o.purchase_timestamp) > 3;
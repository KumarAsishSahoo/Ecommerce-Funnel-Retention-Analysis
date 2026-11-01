--Database Creation

CREATE DATABASE E_commerce_analytics;


--Schema Designing and Tables Creation

CREATE TABLE IF NOT EXISTS customers (
    customer_id VARCHAR(10) PRIMARY KEY,
    signup_date TIMESTAMP NOT NULL,
    country VARCHAR(50),
    acquisition_channel VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS products (
    product_id VARCHAR(10) PRIMARY KEY,
    product_name VARCHAR(100) NOT NULL,
    category VARCHAR(50),
    unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0)
);

CREATE TABLE IF NOT EXISTS events (
    event_id VARCHAR(12) PRIMARY KEY,
    customer_id VARCHAR(10) REFERENCES customers(customer_id),
    event_timestamp TIMESTAMP NOT NULL,
    event_name VARCHAR(30) NOT NULL,
    session_id VARCHAR(20),
    device VARCHAR(20),
    acquisition_channel VARCHAR(50),
    product_id VARCHAR(10) REFERENCES products(product_id)
);

CREATE TABLE IF NOT EXISTS orders (
    order_id VARCHAR(12) PRIMARY KEY,
    customer_id VARCHAR(10) REFERENCES customers(customer_id),
    order_date TIMESTAMP NOT NULL,
    order_value NUMERIC(10,2) NOT NULL CHECK (order_value >= 0),
    order_status VARCHAR(20) NOT NULL
);

CREATE TABLE IF NOT EXISTS order_items (
    order_id VARCHAR(12) REFERENCES orders(order_id),
    product_id VARCHAR(10) REFERENCES products(product_id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    discount_pct NUMERIC(4,2) NOT NULL DEFAULT 0,
    PRIMARY KEY (order_id, product_id)
);


--Data validation 

SELECT 'customers' AS table_name, COUNT(*) AS total_rows
FROM customers
UNION ALL
SELECT 'products', COUNT(*) 
FROM products
UNION ALL
SELECT 'events', COUNT(*) 
FROM events
UNION ALL
SELECT 'orders', COUNT(*) 
FROM orders
UNION ALL
SELECT 'order_items', COUNT(*) 
FROM order_items;



---------------E-commerce funnel analysis------------------



-- Business Question 1: How many customers reach each stage of the purchase funnel?
-- Business objective : Understand how customers move from viewing a product to completing a purchase.
--Business purpose: Identify how many customers engage with each stage and where engagement decreases.

SELECT
    event_name AS funnel_stage,
    COUNT(DISTINCT customer_id) AS unique_customers,
    COUNT(DISTINCT session_id) AS total_sessions
FROM events
WHERE event_name IN (
    'view_item',
    'add_to_cart',
    'begin_checkout',
    'purchase'
)
GROUP BY event_name
ORDER BY
    CASE event_name
        WHEN 'view_item' THEN 1
        WHEN 'add_to_cart' THEN 2
        WHEN 'begin_checkout' THEN 3
        WHEN 'purchase' THEN 4
    END;



--Business Question 2: What percentage of customers move from one funnel stage to the next?
--Business objective: Measure conversion between stages and identify the biggest drop-off.
--Business purpose: Help the business decide which stage needs improvement first.

WITH funnel AS (
    SELECT
        COUNT(DISTINCT customer_id)
            FILTER (WHERE event_name = 'view_item') AS viewers,

        COUNT(DISTINCT customer_id)
            FILTER (WHERE event_name = 'add_to_cart') AS cart_users,

        COUNT(DISTINCT customer_id)
            FILTER (WHERE event_name = 'begin_checkout') AS checkout_users,

        COUNT(DISTINCT customer_id)
            FILTER (WHERE event_name = 'purchase') AS purchasers
    FROM events
)
SELECT
    viewers,
    cart_users,
    checkout_users,
    purchasers,

    ROUND(100.0 * cart_users
        / NULLIF(viewers, 0), 2) AS view_to_cart_pct,

    ROUND(100.0 * checkout_users
        / NULLIF(cart_users, 0), 2) AS cart_to_checkout_pct,

    ROUND(100.0 * purchasers
        / NULLIF(checkout_users, 0), 2) AS checkout_to_purchase_pct,

    ROUND(100.0 * purchasers
        / NULLIF(viewers, 0), 2) AS overall_view_to_purchase_pct
FROM funnel;



--Business Question 3: Which acquisition channel brings the most purchasing customers?
--Business objective: Identify which marketing channels attract customers who purchase.
--Business purpose: Compare acquisition channels by customer purchase rate, rather than just the number of visitors.

SELECT
    c.acquisition_channel,
    COUNT(DISTINCT c.customer_id) AS total_customers,
    COUNT(DISTINCT e.customer_id)
        FILTER (WHERE e.event_name = 'purchase') AS purchasing_customers,
    ROUND(
        100.0 * COUNT(DISTINCT e.customer_id)
            FILTER (WHERE e.event_name = 'purchase')
        / NULLIF(COUNT(DISTINCT c.customer_id), 0),
        2
    ) AS purchase_rate_pct
FROM customers c
LEFT JOIN events e
    ON c.customer_id = e.customer_id
GROUP BY c.acquisition_channel
ORDER BY purchase_rate_pct DESC ;



--Business Question 4: Which acquisition channel generates the highest revenue?
--Business objective: Find out which channels contribute the most completed-order revenue, not just purchasing customers.

SELECT
    c.acquisition_channel,
    COUNT(DISTINCT c.customer_id) AS total_customers,
    COUNT(DISTINCT o.customer_id) AS purchasing_customers,
    COUNT(DISTINCT o.order_id) AS completed_orders,
    ROUND(COALESCE(SUM(o.order_value), 0), 2)
        AS total_revenue,
    ROUND(
        COALESCE(SUM(o.order_value), 0)
        / NULLIF(COUNT(DISTINCT o.order_id), 0),
        2
    ) AS average_order_value
FROM customers c
LEFT JOIN orders o
    ON c.customer_id = o.customer_id
   AND o.order_status = 'Completed'
GROUP BY c.acquisition_channel
ORDER BY total_revenue DESC;



--Business Question 5 — Which product categories generate the highest revenue?
--Business objective: Identify the categories that contribute the most completed-order revenue so the business can make better inventory, marketing, and merchandising decisions.

SELECT
    p.category AS category,
    COUNT(DISTINCT o.order_id) AS completed_orders,
    SUM(oi.quantity) AS units_sold,
    ROUND(SUM(oi.quantity * oi.unit_price
        * (1 - COALESCE(oi.discount_pct, 0) / 100.0)), 2)
        AS estimated_revenue
FROM orders o
JOIN order_items oi
    ON o.order_id = oi.order_id
JOIN products p
    ON oi.product_id = p.product_id
WHERE o.order_status = 'Completed'
GROUP BY p.category
ORDER BY estimated_revenue DESC;



--Business Question 6 — Which are the top 5 revenue-generating products?
--Business objective: Identify the individual products contributing the most revenue.

SELECT
    p.product_id,
    p.product_name,
    p.category,
    SUM(oi.quantity) AS units_sold,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(
        SUM(
            oi.quantity * oi.unit_price *
            (1 - COALESCE(oi.discount_pct, 0) / 100.0)
        ), 2
    ) AS total_revenue
FROM orders o
JOIN order_items oi
    ON o.order_id = oi.order_id
JOIN products p
    ON oi.product_id = p.product_id
WHERE o.order_status = 'Completed'
GROUP BY
    p.product_id,
    p.product_name,
    p.category
ORDER BY total_revenue DESC
LIMIT 5;



--Business Question 7 — Which products have the highest sales volume?
--Business objective: Identify products customers purchase most frequently by quantity.

SELECT
    p.product_name,
    p.category,
    SUM(oi.quantity) AS total_units_sold,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(
        SUM(
            oi.quantity * oi.unit_price *
            (1 - COALESCE(oi.discount_pct, 0) / 100.0)
        ), 2
    ) AS total_revenue
FROM orders o
JOIN order_items oi
    ON o.order_id = oi.order_id
JOIN products p
    ON oi.product_id = p.product_id
WHERE o.order_status = 'Completed'
GROUP BY
    p.product_id,
    p.product_name,
    p.category
ORDER BY total_units_sold DESC
LIMIT 10;



--Business Question 8 — Which products have high sales volume but relatively low revenue?
--Business objective: Identify high-demand, potentially lower-priced products. This can help with pricing, bundling, and cross-selling strategies.

SELECT
    p.product_name,
    p.category,
    SUM(oi.quantity) AS units_sold,
    ROUND(
        SUM(
            oi.quantity * oi.unit_price *
            (1 - COALESCE(oi.discount_pct, 0) / 100.0)
        ), 2
    ) AS total_revenue,
    ROUND(
        SUM(
            oi.quantity * oi.unit_price *
            (1 - COALESCE(oi.discount_pct, 0) / 100.0)
        ) / NULLIF(SUM(oi.quantity), 0),
        2
    ) AS average_selling_price
FROM orders o
JOIN order_items oi
    ON o.order_id = oi.order_id
JOIN products p
    ON oi.product_id = p.product_id
WHERE o.order_status = 'Completed'
GROUP BY
    p.product_id,
    p.product_name,
    p.category
ORDER BY units_sold DESC;




-----------------Customer Analysis-----------------



--Business Question 9: How many customers are repeat customers?
--Business objective: Determine how many customers purchase more than once.

WITH customer_orders AS (
    SELECT
        customer_id,
        COUNT(DISTINCT order_id) AS total_orders,
        SUM(order_value) AS total_spent
    FROM orders
    WHERE order_status = 'Completed'
    GROUP BY customer_id
)
SELECT
    COUNT(*) AS total_purchasing_customers,

    COUNT(*) FILTER (
        WHERE total_orders = 1
    ) AS one_time_customers,

    COUNT(*) FILTER (
        WHERE total_orders > 1
    ) AS repeat_customers,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE total_orders > 1
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS repeat_customer_rate,

    ROUND(AVG(total_spent), 2) AS average_customer_spending
FROM customer_orders;



--Business Question 10 — Who are the top 10 customers by revenue?
--Business objective: Identify high-value customers who contribute the most revenue. Businesses can use this analysis to design VIP programs and personalized offers.

SELECT
    c.customer_id,
    c.acquisition_channel,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(o.order_value), 2) AS total_revenue,
    ROUND(AVG(o.order_value), 2) AS average_order_value
FROM customers c
JOIN orders o
    ON c.customer_id = o.customer_id
WHERE o.order_status = 'Completed'
GROUP BY
    c.customer_id,
    c.acquisition_channel
ORDER BY total_revenue DESC
LIMIT 10;


----------------Month-Month Sales & Revenue Analysis-------------

--Business Question 11 — How is revenue changing month by month?
--Business objective: Understand monthly revenue trends, identify high-performing months, and detect periods of declining sales.

SELECT
    DATE_TRUNC('month', order_date)::DATE AS order_month,
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(DISTINCT customer_id) AS unique_customers,
    ROUND(SUM(order_value), 2) AS monthly_revenue,
    ROUND(AVG(order_value), 2) AS average_order_value
FROM orders
WHERE order_status = 'Completed'
GROUP BY DATE_TRUNC('month', order_date)
ORDER BY order_month;


--Business Question 12 — What is the month-over-month revenue growth?

WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC('month', order_date)::DATE AS order_month,
        SUM(order_value) AS revenue
    FROM orders
    WHERE order_status = 'Completed'
    GROUP BY DATE_TRUNC('month', order_date)
),

revenue_comparison AS (
    SELECT
        order_month,
        revenue,
        LAG(revenue) OVER (
            ORDER BY order_month
        ) AS previous_month_revenue
    FROM monthly_revenue
)

SELECT
    order_month,
    ROUND(revenue, 2) AS current_revenue,
    ROUND(previous_month_revenue, 2) AS previous_month_revenue,
    ROUND( 100.0 * (revenue - previous_month_revenue)
        / NULLIF(previous_month_revenue, 0),2) AS revenue_growth_pct
FROM revenue_comparison
ORDER BY order_month;


--Business Question 13 — Which acquisition channel generates the highest monthly revenue?
--Business objective: Understand which marketing channel contributes the most revenue each month.

SELECT
    DATE_TRUNC('month', o.order_date)::DATE AS order_month,
    c.acquisition_channel,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(o.order_value), 2) AS monthly_revenue
FROM orders o
JOIN customers c
    ON o.customer_id = c.customer_id
WHERE o.order_status = 'Completed'
GROUP BY
    DATE_TRUNC('month', o.order_date),
    c.acquisition_channel
ORDER BY
    order_month,
    monthly_revenue DESC;


----Business Question 14 - Top performing acquisition channel per month
--Business objective: To perform more investment on percular customer acquisition channel

WITH monthly_channel_revenue AS (
    SELECT
        DATE_TRUNC('month', o.order_date)::DATE AS order_month,
        c.acquisition_channel,
        COUNT(DISTINCT o.order_id) AS total_orders,
        ROUND(SUM(o.order_value), 2) AS monthly_revenue
    FROM orders o
    JOIN customers c
        ON o.customer_id = c.customer_id
    WHERE o.order_status = 'Completed'
    GROUP BY
        DATE_TRUNC('month', o.order_date),
        c.acquisition_channel
),
ranked_channels AS (
    SELECT
        *,
        RANK() OVER (
            PARTITION BY order_month
            ORDER BY monthly_revenue DESC
        ) AS channel_rank
    FROM monthly_channel_revenue
)
SELECT
    order_month,
    acquisition_channel,
    total_orders,
    monthly_revenue
FROM ranked_channels
WHERE channel_rank = 1
ORDER BY order_month;



--Business Question 15 — What is the monthly customer acquisition and purchasing trend?
--Business objective: Compare registered customers with purchasing customers for each month.


WITH monthly_customers AS (
    SELECT
        DATE_TRUNC('month', signup_date)::DATE AS month,
        COUNT(DISTINCT customer_id) AS new_customers
    FROM customers
    GROUP BY 1
),

monthly_purchasers AS (
    SELECT
        DATE_TRUNC('month', c.signup_date)::DATE AS month,
        COUNT(DISTINCT o.customer_id) AS purchasing_customers
    FROM customers c
    JOIN orders o
        ON c.customer_id = o.customer_id
    WHERE o.order_status = 'Completed'
    GROUP BY 1
)

SELECT
    mc.month,
    mc.new_customers,
    COALESCE(mp.purchasing_customers, 0) AS purchasing_customers,
    ROUND(
        100.0 * COALESCE(mp.purchasing_customers, 0)
        / NULLIF(mc.new_customers, 0),
        2
    ) AS purchase_rate_pct
FROM monthly_customers mc
LEFT JOIN monthly_purchasers mp
    ON mc.month = mp.month
ORDER BY mc.month;

--Business Question 16 — How many customers make their first purchase, and how long does it take?
--Business objective: Understand customer activation time. This can help businesses decide when to send onboarding emails, reminders, and promotional offers.

WITH first_purchase AS (
    SELECT
        customer_id,
        MIN(order_date) AS first_order_date
    FROM orders
    WHERE order_status = 'Completed'
    GROUP BY customer_id
),

customer_purchase_time AS (
    SELECT
        c.customer_id,
        c.signup_date,
        fp.first_order_date,
        fp.first_order_date::DATE - c.signup_date::DATE
            AS days_to_first_purchase
    FROM customers c
    JOIN first_purchase fp
        ON c.customer_id = fp.customer_id
)

SELECT
    COUNT(*) AS purchasing_customers,
    ROUND(AVG(days_to_first_purchase), 2)
        AS average_days_to_first_purchase,
    MIN(days_to_first_purchase) AS minimum_days,
    MAX(days_to_first_purchase) AS maximum_days,
    COUNT(*) FILTER (
        WHERE days_to_first_purchase = 0
    ) AS same_day_purchases,
    COUNT(*) FILTER (
        WHERE days_to_first_purchase BETWEEN 1 AND 7
    ) AS purchases_within_7_days,
    COUNT(*) FILTER (
        WHERE days_to_first_purchase BETWEEN 8 AND 30
    ) AS purchases_within_30_days
FROM customer_purchase_time;


--Business Question 17 — Which acquisition channel converts customers fastest?
--Business objective: Identify which marketing channel brings customers who make their first purchase quickly.

WITH first_purchase AS (
    SELECT
        customer_id,
        MIN(order_date) AS first_order_date
    FROM orders
    WHERE order_status = 'Completed'
    GROUP BY customer_id
),

customer_conversion AS (
    SELECT
        c.customer_id,
        c.acquisition_channel,
        fp.first_order_date::DATE - c.signup_date::DATE
            AS days_to_first_purchase
    FROM customers c
    JOIN first_purchase fp
        ON c.customer_id = fp.customer_id
)

SELECT
    acquisition_channel,
    COUNT(*) AS purchasing_customers,
    ROUND(
        AVG(days_to_first_purchase), 2
    ) AS avg_days_to_first_purchase,
    MIN(days_to_first_purchase) AS fastest_conversion_days,
    MAX(days_to_first_purchase) AS slowest_conversion_days
FROM customer_conversion
GROUP BY acquisition_channel
ORDER BY avg_days_to_first_purchase;



--Business Question 18 — What is the customer retention rate by signup cohort?
--Business objective: Understand how many customers from each signup month return to make another purchase in subsequent months.

WITH customer_cohort AS (
    SELECT
        customer_id,
        DATE_TRUNC('month', signup_date)::DATE AS cohort_month
    FROM customers
),

customer_orders AS (
    SELECT DISTINCT
        customer_id,
        DATE_TRUNC('month', order_date)::DATE AS purchase_month
    FROM orders
    WHERE order_status = 'Completed'
),

cohort_activity AS (
    SELECT
        cc.cohort_month,
        co.purchase_month,
        (
            EXTRACT(YEAR FROM AGE(
                co.purchase_month,
                cc.cohort_month
            )) * 12
            +
            EXTRACT(MONTH FROM AGE(
                co.purchase_month,
                cc.cohort_month
            ))
        )::INT AS month_number,
        COUNT(DISTINCT cc.customer_id) AS active_customers
    FROM customer_cohort cc
    JOIN customer_orders co
        ON cc.customer_id = co.customer_id
    WHERE co.purchase_month >= cc.cohort_month
    GROUP BY
        cc.cohort_month,
        co.purchase_month
),

cohort_size AS (
    SELECT
        cohort_month,
        COUNT(*) AS total_customers
    FROM customer_cohort
    GROUP BY cohort_month
)

SELECT
    ca.cohort_month,
    cs.total_customers,
    ca.month_number,
    ca.active_customers,
    ROUND(
        100.0 * ca.active_customers
        / NULLIF(cs.total_customers, 0),
        2
    ) AS retention_rate_pct
FROM cohort_activity ca
JOIN cohort_size cs
    ON ca.cohort_month = cs.cohort_month
ORDER BY
    ca.cohort_month,
    ca.month_number;


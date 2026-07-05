-- Admin view za trenutne narudžbe
CREATE OR REPLACE VIEW vw_order_details AS
SELECT 
    o.id AS order_id,
    o.created_at,
    o.status AS order_status,
    o.total_amount,
    up.first_name || ' ' || up.last_name AS customer_name,
    u.email AS customer_email,
    o.p_status AS payment_status,
    o.tracking_number
FROM orders o
JOIN users u ON o.user_id = u.id
JOIN user_profiles up ON u.id = up.user_id;

-- Admin view za novčanice koje nisu "out of stock", ali ih ima 5 ili manje
CREATE OR REPLACE VIEW vw_stock_alerts AS
SELECT 
    p.id AS product_id,
    p.title,
    p.stock_quantity,
    c.name AS category_name,
    p.base_price
FROM products p
LEFT JOIN categories c ON p.category_id = c.id
WHERE p.stock_quantity < 5 
  AND p.status = 'published'
  AND p.deleted_at IS NULL
ORDER BY p.stock_quantity ASC;

-- Admin view samo za novčanice kojih uopće nema na stanju
CREATE OR REPLACE VIEW vw_out_of_stock AS
SELECT 
    p.id AS product_id,
    p.title,
    c.name AS category_name,
    p.base_price,
    p.status
FROM products p
LEFT JOIN categories c ON p.category_id = c.id
WHERE p.stock_quantity = 0 
  OR p.status = 'out_of_stock'
  AND p.deleted_at IS NULL
ORDER BY p.title ASC;

-- Admin view za dobit po danima
CREATE OR REPLACE VIEW vw_daily_revenue AS
SELECT 
    DATE(created_at) AS sale_date,
    COUNT(id) AS number_of_orders,
    SUM(total_amount) AS gross_revenue,
    SUM(discount_amount) AS total_discounts_given,
    SUM(total_amount - discount_amount) AS net_revenue
FROM orders
WHERE status != 'cancelled' AND p_status = 'paid'
GROUP BY DATE(created_at)
ORDER BY sale_date DESC;

-- Admin view za profit po danima // TREVA PREPRAVITI JER "BUY PRICE NIJE SMRZNUT
CREATE OR REPLACE VIEW vw_daily_profit AS
SELECT 
    DATE(o.created_at) AS sale_date,
    SUM(oi.item_total) AS total_revenue,
    SUM(oi.quantity * p.buy_price) AS total_cost,
    SUM(oi.item_total - (oi.quantity * p.buy_price)) AS net_profit
FROM orders o
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id
WHERE o.status != 'cancelled' AND o.p_status = 'paid'
GROUP BY DATE(o.created_at)
ORDER BY sale_date DESC;


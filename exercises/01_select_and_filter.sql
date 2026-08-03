-- Practice: select and filter rows
-- Task: write a query that returns customer_id, customer_name, and order_total for orders above 100

SELECT customer_id, customer_name, order_total
FROM orders
WHERE order_total > 100;

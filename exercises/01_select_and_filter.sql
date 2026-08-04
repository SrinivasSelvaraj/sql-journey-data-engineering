-- Practice: select and filter rows
-- Task: write a query that returns order_id, customer_name, and order_total for paid orders above 150

SELECT order_id, customer_name, order_total
FROM orders
WHERE order_total > 150
	AND payment_status = 'paid';

--- Triggers for "update_at" ---

CREATE TRIGGER trg_user_profiles_updated_at
BEFORE UPDATE ON user_profiles
FOR EACH ROW
EXECUTE FUNCTION fn_update_timestamp();

CREATE TRIGGER trg_products_updated_at
BEFORE UPDATE ON products
FOR EACH ROW
EXECUTE FUNCTION fn_update_timestamp();

CREATE TRIGGER trg_carts_updated_at
BEFORE UPDATE ON carts
FOR EACH ROW
EXECUTE FUNCTION fn_update_timestamp();

CREATE TRIGGER trg_orders_updated_at
BEFORE UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION fn_update_timestamp();

CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION fn_update_timestamp();

CREATE TRIGGER trg_addresses_updated_at
BEFORE UPDATE ON addresses
FOR EACH ROW
EXECUTE FUNCTION fn_update_timestamp();

CREATE TRIGGER trg_coupons_updated_at
BEFORE UPDATE ON coupons
FOR EACH ROW
EXECUTE FUNCTION fn_update_timestamp();

CREATE TRIGGER trg_shipping_methods_updated_at
BEFORE UPDATE ON shipping_methods
FOR EACH ROW
EXECUTE FUNCTION fn_update_timestamp();
----------------------------------------------

-- Trigger za loyality points
CREATE TRIGGER trg_check_loyalty_points
BEFORE UPDATE OF loyalty_points ON user_profiles
FOR EACH ROW
EXECUTE FUNCTION fn_check_loyalty_points();

-- Trigger za smanjivanje zaliha pri kreiranju narudžbe
CREATE TRIGGER trg_reduce_stock
BEFORE INSERT ON order_items
FOR EACH ROW
EXECUTE FUNCTION fn_reduce_stock();

--- Triggeri za automatsko pisanje po audit_log ---
CREATE TRIGGER trg_audit_products
AFTER INSERT OR UPDATE OR DELETE ON products
FOR EACH ROW EXECUTE FUNCTION fn_audit_log_action();

CREATE TRIGGER trg_audit_coupons
AFTER INSERT OR UPDATE OR DELETE ON coupons
FOR EACH ROW EXECUTE FUNCTION fn_audit_log_action();

CREATE TRIGGER trg_audit_users
AFTER INSERT OR UPDATE OR DELETE ON users
FOR EACH ROW EXECUTE FUNCTION fn_audit_log_action();

CREATE TRIGGER trg_audit_user_profiles
AFTER INSERT OR UPDATE OR DELETE ON user_profiles
FOR EACH ROW EXECUTE FUNCTION fn_audit_log_action();

CREATE TRIGGER trg_audit_orders
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW EXECUTE FUNCTION fn_audit_log_action();
----------------------------------------------------








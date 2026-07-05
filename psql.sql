-- Funckija koju poziva okidač za update "update_at"
CREATE OR REPLACE FUNCTION fn_update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Funckija koju poziv okidač da provjeri jesu bodovi ispravno skinuti
CREATE OR REPLACE FUNCTION fn_check_loyalty_points()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.loyalty_points < 0 THEN
        RAISE EXCEPTION 'Greška: Korisnik ne može imati negativne loyalty bodove! (Pokušano: %)', NEW.loyalty_points;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Funkcija koju poziva okidač da provjeri je li stanje nočanica dovoljno i smanji zalihe
CREATE OR REPLACE FUNCTION fn_reduce_stock()
RETURNS TRIGGER AS $$
DECLARE
    v_new_quantity INTEGER;
BEGIN
    --'FOR UPDATE' za zaključavanje reda
    IF (SELECT stock_quantity FROM products WHERE id = NEW.product_id FOR UPDATE) < NEW.quantity THEN
        RAISE EXCEPTION 'Nedovoljno zaliha za proizvod (ID: %). Traženo: %, Dostupno: %', 
            NEW.product_id, 
            NEW.quantity, 
            (SELECT stock_quantity FROM products WHERE id = NEW.product_id);
    END IF;

    -- Ako je sve OK, smanji zalihe
    UPDATE products 
    SET stock_quantity = stock_quantity - NEW.quantity 
    WHERE id = NEW.product_id
	RETURNING stock_quantity INTO v_new_quantity;

	-- Automatkso logiranje u inventory_logs
    INSERT INTO inventory_logs (
        product_id, 
        change_amount, 
        new_quantity, 
        reason, 
        order_id, 
        notes
    ) VALUES (
        NEW.product_id, 
        -NEW.quantity, -- Negativan broj jer skidamo sa stanja
        v_new_quantity, 
        'order', -- Razlog je narudžba
        NEW.order_id, 
        'Automatsko smanjenje pri kreiranju stavke narudžbe.'
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Funckija koju poziva okidač za praćenje audit_log
CREATE OR REPLACE FUNCTION fn_audit_log_action()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        INSERT INTO audit_logs (action_type, table_name, record_id, old_values, new_values)
        VALUES (TG_OP, TG_TABLE_NAME, NULL, to_jsonb(OLD), to_jsonb(NEW));
    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO audit_logs (action_type, table_name, record_id, old_values)
        VALUES (TG_OP, TG_TABLE_NAME, NULL, to_jsonb(OLD));
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO audit_logs (action_type, table_name, record_id, new_values)
        VALUES (TG_OP, TG_TABLE_NAME, NULL, to_jsonb(NEW));
    END IF;
    RETURN NULL; -- jer korisimo ovo sa AFTER trigger pa vraća NULL
END;
$$ LANGUAGE plpgsql;

-- Procedura za finaliziranje narudžbe // TREBA "POPRAVITI" - LOYALITY POINTS SE DODAJU NAKON 14 DANA OD KUPNJE
CREATE OR REPLACE PROCEDURE pr_finalize_order(p_order_id UUID)
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id UUID;
    v_total_amount DECIMAL(12, 2);
    v_points_to_add INTEGER;
BEGIN
    SELECT user_id, total_amount INTO v_user_id, v_total_amount
    FROM orders
    WHERE id = p_order_id AND status = 'pending';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Narudžba % ne postoji ili nije u stanju "pending".', p_order_id;
    END IF;

    UPDATE orders 
    SET status = 'confirmed', updated_at = CURRENT_TIMESTAMP
    WHERE id = p_order_id;

    v_points_to_add := v_total_amount * 10;

    IF v_user_id IS NOT NULL THEN
        UPDATE user_profiles 
        SET loyalty_points = loyalty_points + v_points_to_add
        WHERE user_id = v_user_id;
    END IF;

    RAISE NOTICE 'Narudžba % uspješno potvrđena. Dodijeljeno % bodova.', p_order_id, v_points_to_add;
END;
$$;

-- Funckija za provjeru je li coupon validan
CREATE OR REPLACE FUNCTION fn_is_coupon_valid(p_code TEXT, p_user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_valid BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM coupons
        WHERE code = p_code
          AND is_active = TRUE
          AND (valid_to IS NULL OR valid_to > CURRENT_TIMESTAMP)
          AND (max_uses IS NULL OR used_count < max_uses)
    ) INTO v_valid;

    RETURN v_valid;
END;
$$ LANGUAGE plpgsql;

-- Funckija koja se poziva na trigger da napravi +1 za coupon koji je upisan
CREATE OR REPLACE FUNCTION fn_increment_coupon_usage()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.coupon_id IS NOT NULL THEN
        UPDATE coupons
        SET used_count = used_count + 1
        WHERE id = NEW.coupon_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
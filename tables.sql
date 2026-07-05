-- Omogućavanje generiranja UUID-ova
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Kreiranje Custom tipova
CREATE TYPE user_role AS ENUM ('admin', 'customer');

-- Tablica users - samo za ulaz u sustav
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role user_role NOT NULL DEFAULT 'customer',
    is_active BOOLEAN DEFAULT true, -- ako korisnik želi deaktivirati račun
    
    -- erifikacija emaila
    is_verified BOOLEAN DEFAULT false,
    verified_at TIMESTAMP WITH TIME ZONE,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP WITH TIME ZONE
);
ALTER TABLE users ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

-- Indeks za email jer ćemo po njemu stalno tražiti korisnika kod logina
CREATE INDEX idx_users_email ON users(email);

-- Tablica za tokene za email verifikaciju - kodovi se brišu kad korisnik iskoristi kod (Node.js poziv) ili CronJob na expire
CREATE TABLE email_verifications (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token VARCHAR(128) NOT NULL, 
    
 	-- now() + 24
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indeks na kolonu token - baza će pretraživati ovu tablicu po tokenu svaki put kad netko klikne na link.
CREATE INDEX idx_email_verifications_token ON email_verifications(token);

-- Tablica user_profiles sa podacima o klijentima
CREATE TABLE user_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    phone VARCHAR(50),
    
    loyalty_points INTEGER DEFAULT 0,
    
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
 	-- Nije NOT NULL ako je "kupac-gost"
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    phone_number VARCHAR(50) NOT NULL,
    
    street_address TEXT NOT NULL,
    city VARCHAR(100) NOT NULL,
    postal_code VARCHAR(20) NOT NULL,
    country VARCHAR(100) DEFAULT 'Hrvatska',
    
    -- Koristi se samo za registrirane korisnike da znam koja im je primarna adresa
    is_default BOOLEAN DEFAULT false,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE addresses ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE addresses ADD COLUMN is_visible_to_user BOOLEAN DEFAULT true; -- ako korisnik želi makmuti adresu iz ponudenih - radim soft brisanje jer ne smijem maknuti adresu iz baze

-- Indeks na user_id kako bi baza trenutno pronašla sve adrese jednog korisnika
CREATE INDEX idx_addresses_user_id ON addresses(user_id);


-- Tablica kategorija proizvoda
CREATE TABLE categories (
    id SERIAL PRIMARY KEY,
    
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL, -- URL
    
    parent_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE categories ADD COLUMN deleted_at TIMESTAMP DEFAULT NULL;

-- Indeks za brzu pretragu po URL-u
CREATE INDEX idx_categories_slug ON categories(slug);

-- Tablica products - svi proizvodi su ovdje, metadata služi za trpanje pojedinačnih i specifičnih podataka
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
    
    title VARCHAR(255) NOT NULL,
    slug VARCHAR(255) UNIQUE NOT NULL, -- URL verzija naslova
    
    base_price DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    buy_price DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    
    stock_quantity INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(20) DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'out_of_stock', 'hidden')),
    
    metadata JSONB NOT NULL DEFAULT '{}',
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE products ADD COLUMN deleted_at TIMESTAMP DEFAULT NULL;

-- Indeski za tablicu products
CREATE INDEX idx_products_slug ON products(slug);
CREATE INDEX idx_products_category ON products(category_id);
CREATE INDEX idx_products_metadata ON products USING GIN (metadata);

-- Tablica product_images
CREATE TABLE product_images (
    id SERIAL PRIMARY KEY,
   
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    
    image_url TEXT NOT NULL,
    alt_text VARCHAR(255),
    sort_order INTEGER DEFAULT 0,
    is_main BOOLEAN DEFAULT false,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indeks za brzo dohvaćanje slika
CREATE INDEX idx_product_images_product_id ON product_images(product_id);

-- Tablica carts
CREATE TABLE carts (
    id SERIAL PRIMARY KEY,
    
    -- Vlasnik košarice
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    guest_session_id VARCHAR(255),
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indeksi za brzu provjeru ima li korisnik već aktivnu košaricu
CREATE INDEX idx_carts_user_id ON carts(user_id);
CREATE INDEX idx_carts_guest_session ON carts(guest_session_id);

-- Tablica cart_items
CREATE TABLE cart_items (
    id SERIAL PRIMARY KEY,
    
    cart_id INTEGER NOT NULL REFERENCES carts(id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    
    quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    
    added_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(cart_id, product_id)
);

-- Indeks za brzi dohvat svih stavki jedne košarice
CREATE INDEX idx_cart_items_cart_id ON cart_items(cart_id);

-- Custom tip - statusi narudžbe
CREATE TYPE order_status AS ENUM ('pending', 'confirmed', 'shipped', 'delivered', 'cancelled', 'refunded');

-- Custom tip - statusi plaćanja
CREATE TYPE payment_status AS ENUM ('pending', 'paid', 'failed', 'refunded');

-- Tablica orders
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    address_id UUID REFERENCES addresses(id) ON DELETE RESTRICT,
    
    total_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00, -- Ukupno za platiti
    shipping_fee DECIMAL(12, 2) NOT NULL DEFAULT 0.00, -- Trošak dostave
    discount_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00, -- Koliko je ušteđeno kuponom
    
    status order_status DEFAULT 'pending',
    p_status payment_status DEFAULT 'pending',
    
    tracking_number VARCHAR(100), -- Broj paketa (HP, GLS, itd.)
    admin_notes TEXT, -- Bilješke koje vidi samo admin
    customer_notes TEXT, -- Što je kupac napisao kod kupnje
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
-- Napomena: veza orders -> shipping_methods dodaje se nakon što se ta tablica kreira (v. dno datoteke)

-- Indeksi za Admin Panel (da brzo vidim nove narudžbe ili narudžbe određenog kupca)
CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_orders_status ON orders(status);

-- Tablica order_items
CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id INTEGER REFERENCES products(id) ON DELETE SET NULL,
    
    -- Ovo se automatski puni
    product_title VARCHAR(255) NOT NULL,
    price_at_purchase DECIMAL(12, 2) NOT NULL,
   
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    
    -- Ukupno za ovu stavku (price * quantity)
    item_total DECIMAL(12, 2) NOT NULL
);

-- Indeks za brzi pregled stavki jedne narudžbe
CREATE INDEX idx_order_items_order_id ON order_items(order_id);

-- Custom tip - mjenjanje zaliha
CREATE TYPE inventory_change_reason AS ENUM ('restock', 'order', 'return', 'adjustment', 'damaged', 'other');

-- Tablica inventory_logs
CREATE TABLE inventory_logs (
    id SERIAL PRIMARY KEY,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    
    -- change_amount: npr. +5 (ulaz) ili -3 (izlaz)
    change_amount INTEGER NOT NULL,
    -- new_quantity: koliko ih ima u bazi nakon te promjene (za kontrolu)
    new_quantity INTEGER NOT NULL,
    
    reason inventory_change_reason NOT NULL,
    
    -- Ako je razlog 'order'
    order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
    -- Ako je admin ručno mijenjao
    admin_id UUID REFERENCES users(id) ON DELETE SET NULL,
    -- Ovdje pišem objašnjenje ako je razlog 'other'
    notes TEXT,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indeks da baza brzo pretražuje povijest proizvoda
CREATE INDEX idx_inventory_logs_product_id ON inventory_logs(product_id);

-- Tablica audit_logs
CREATE TABLE audit_logs (
    id SERIAL PRIMARY KEY,
    
    admin_id UUID REFERENCES users(id) ON DELETE SET NULL,
    
    -- Što je radio? (npr. 'UPDATE_PRICE', 'DELETE_USER', 'CHANGE_LOYALTY')
    action_type VARCHAR(100) NOT NULL,
    -- Na kojoj tablici i kojem zapisu?
    table_name VARCHAR(100) NOT NULL,
    record_id UUID,
    
    -- JSONB snimka 'prije' i 'poslije'
    old_values JSONB,
    new_values JSONB,
    
    -- Dodatne informacije
    context JSONB,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE audit_logs ALTER COLUMN record_id TYPE TEXT;

-- Indeks za brzu pretragu po tablici ili adminu
CREATE INDEX idx_audit_logs_admin_id ON audit_logs(admin_id);
CREATE INDEX idx_audit_logs_table_name ON audit_logs(table_name);

-- Table cupons
CREATE TABLE coupons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    code VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    
    discount_type VARCHAR(20) NOT NULL CHECK (discount_type IN ('percentage', 'fixed_amount')),
    discount_value DECIMAL(12, 2) NOT NULL,
    min_order_amount DECIMAL(12, 2) DEFAULT 0.00,
    
    max_uses INTEGER DEFAULT NULL, -- Koliko puta se ukupno može iskoristiti (NULL = beskonačno)
    used_count INTEGER DEFAULT 0,  -- Koliko je puta već iskorišten
    
    valid_from TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    valid_to TIMESTAMP WITH TIME ZONE,
    
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE coupons ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE coupons ADD COLUMN deleted_at TIMESTAMP DEFAULT NULL;

-- Indeks za brzu provjeru koda kad ga kupac unese na checkoutu
CREATE INDEX idx_coupons_code ON coupons(code);

-- Tablica - shipping_methods
CREATE TABLE shipping_methods (
    id SERIAL PRIMARY KEY,
    
    name VARCHAR(100) NOT NULL,
    base_price DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    free_over_amount DECIMAL(12, 2) DEFAULT NULL,
    estimated_delivery VARCHAR(100),
    
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE shipping_methods ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

-- Sada kad shipping_methods postoji, povezujemo narudžbe s načinom dostave
ALTER TABLE orders
ADD COLUMN shipping_method_id INTEGER REFERENCES shipping_methods(id) ON DELETE SET NULL;

































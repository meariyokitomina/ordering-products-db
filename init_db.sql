-- =============================================
-- DATABASE CREATION
-- =============================================
CREATE DATABASE orderingproducts
    WITH
    OWNER = postgres
    TEMPLATE = template1
    ENCODING = 'UTF8'
    LOCALE_PROVIDER = 'libc'
    CONNECTION LIMIT = -1
    IS_TEMPLATE = False;
-- =============================================
-- TABLE: products (Продукты)
-- =============================================
CREATE TABLE products
(
    product_id serial PRIMARY KEY,
    product_name varchar (20) NOT NULL,
    is_available boolean DEFAULT TRUE,
    category varchar (20) NOT NULL CHECK (
    category IN ('мякоть', 'мясокостное', 'мышечное', 'кроветворное', 'другое')
    )
);
-- Начальные данные для таблицы products
INSERT INTO products (product_name, is_available, category) 
    VALUES
    ('сердце свиное', true, 'мышечное'),
    ('желудки куриные', true,'мышечное'),
    ('шейки индейки', true,'мясокостное'),
    ('головы куриные', true,'мясокостное'),
    ('лапы куриные', true,'мясокостное'),
    ('калтык свиной', true,'другое'),
    ('печень куриная', true,'кроветворное'),
    ('свинина', true,'мякоть');
-- Добавляем столбец для эксклюзивных продуктов
ALTER TABLE products ADD COLUMN is_exclusive_for integer REFERENCES animals(animal_id);
-- Назначаем шейки индейки эксклюзивно для Наоми
UPDATE products 
    SET is_exclusive_for = (
    SELECT animal_id 
    FROM animals
    WHERE animal_name = 'Наоми'
    )
WHERE product_name = 'шейки индейки';
-- Добавляем дополнительные продукты (недоступные по умолчанию)
INSERT INTO products (product_name, is_available, category) 
    VALUES
    ('калтык говяжий', false, 'другое'),
    ('мозги говяжьи', false, 'кроветворное'),
    ('шейки куриные', false, 'мясокостное'),
    ('гузки индейки', false, 'мясокостное'),
    ('бычьи семенники', false, 'мышечное');
-- Меняем доступность продуктов
ALTER TABLE products ALTER COLUMN is_available SET DEFAULT FALSE;
UPDATE products SET is_available = FALSE;
-- =============================================
-- TABLE: animals (Животные)
-- =============================================
CREATE TABLE animals
(
    animal_id serial PRIMARY KEY,
    animal_name varchar (10) NOT NULL,
    daily_norm_kg decimal(10,2) NOT NULL,
    monthly_norm_kg decimal(10,2) GENERATED ALWAYS AS (daily_norm_kg*30) STORED,
    meat_percent integer NOT NULL CHECK (meat_percent BETWEEN 0 AND 100),
    bone_percent integer NOT NULL CHECK (bone_percent BETWEEN 0 AND 100),
    muscle_percent integer NOT NULL CHECK (muscle_percent BETWEEN 0 AND 100),
    blood_percent integer NOT NULL CHECK (blood_percent BETWEEN 0 AND 100),
    other_percent integer NOT NULL CHECK (other_percent BETWEEN 0 AND 100),
    CONSTRAINT persent_sum_check CHECK (
    meat_percent + bone_percent + muscle_percent + blood_percent + other_percent = 100
    ) 
);
-- Начальные данные для таблицы animals
INSERT INTO animals (animal_name, daily_norm_kg, meat_percent, bone_percent, muscle_percent, blood_percent, other_percent)
VALUES
    ('Грэг', 0.2, 30, 25, 30, 5, 10),
    ('Наоми', 0.4, 35, 20, 30, 5, 10);
-- =============================================
-- TABLE: product_inventory (Остатки на складе)
-- =============================================
CREATE TABLE product_inventory
(
    product_id integer PRIMARY KEY REFERENCES products(product_id),
    quantity_kg DECIMAL(10,2) NOT NULL DEFAULT 0,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- Начальные остатки продуктов
INSERT INTO product_inventory (product_id, quantity_kg)
VALUES 
    ((SELECT product_id FROM products WHERE product_name = 'лапы куриные'), 0.9),
    ((SELECT product_id FROM products WHERE product_name = 'головы куриные'), 0.8),
    ((SELECT product_id FROM products WHERE product_name = 'шейки индейки'), 2.6)
ON CONFLICT (product_id)
    DO UPDATE SET
    quantity_kg = EXCLUDED.quantity_kg,
    last_updated = CURRENT_TIMESTAMP;
-- =============================================
-- TABLE: product_substitutes (Замены продуктов)
-- =============================================
CREATE TABLE product_substitutes (
    original_id integer REFERENCES products(product_id),
    substitute_id integer REFERENCES products(product_id)
);
-- Данные о заменах продуктов
INSERT INTO product_substitutes
VALUES 
    (6, 17),
    (17,6),
    (1, 2),
    (2, 1),
    (1, 21),
    (2, 21),
    (3, 4),
    (5, 4),
    (4, 5),
    (19, 3),
    (20, 19);
-- =============================================
-- TABLE: orders (Заказы)
-- =============================================
CREATE TABLE orders
(
    order_id serial PRIMARY KEY,
    order_date DATE NOT NULL,
    animal_id integer REFERENCES animals(animal_id),
    product_id integer REFERENCES products(product_id),
    month_date date NOT NULL,
    quantity_kg decimal(10,2) NOT NULL,
    used_from_stock_kg DECIMAL(10,2) DEFAULT 0 CHECK (used_from_stock_kg <= quantity_kg)
);
-- =============================================
-- DEMO QUERIES (Примеры запросов)
-- =============================================
-- Просмотр данных
SELECT * FROM animals;
SELECT * FROM products;
SELECT * FROM orders;
SELECT * FROM product_inventory;
-- Активируем доступные продукты
UPDATE products SET is_available = TRUE 
WHERE product_id IN (1, 2, 3, 4, 5, 6, 7, 8);
-- =============================================
-- COMPLEX QUERY: Расчет заказа на месяц
-- =============================================
WITH animal_needs AS (
    SELECT 
        a.animal_id,
        a.animal_name,
        p.category,
        ROUND(a.monthly_norm_kg * 
            CASE p.category
                WHEN 'мякоть' THEN a.meat_percent/100.0
                WHEN 'мясокостное' THEN a.bone_percent/100.0
                WHEN 'мышечное' THEN a.muscle_percent/100.0
                WHEN 'кроветворное' THEN a.blood_percent/100.0
                WHEN 'другое' THEN a.other_percent/100.0
            END, 2) AS required_kg
    FROM animals a
    CROSS JOIN (SELECT DISTINCT category FROM products WHERE is_available = TRUE) p
),
-- Суммируем потребности по категориям
category_totals AS (
    SELECT 
        category,
        COUNT(*) AS products_in_category
    FROM products
    WHERE is_available = TRUE
    GROUP BY category
),
-- Нормализуем потребности по продуктам
normalized_needs AS (
    SELECT
        an.animal_id,
        an.animal_name,
        an.category,
        ROUND(an.required_kg / ct.products_in_category, 2) AS normalized_kg
    FROM animal_needs an
    JOIN category_totals ct ON an.category = ct.category
)
-- Итоговый отчет для заказа
SELECT 
    p.product_name,
    p.category,
    ROUND(SUM(nn.normalized_kg), 2) AS total_required,
    ROUND(COALESCE(pi.quantity_kg, 0), 2) AS current_stock,
    GREATEST(ROUND(SUM(nn.normalized_kg) - COALESCE(pi.quantity_kg, 0), 2), 0) AS need_to_order_kg,
    CASE 
        WHEN p.is_exclusive_for IS NOT NULL 
        THEN (SELECT animal_name FROM animals WHERE animal_id = p.is_exclusive_for)
        ELSE 'Все'
    END AS exclusive_for
FROM products p
JOIN normalized_needs nn ON p.category = nn.category
LEFT JOIN product_inventory pi ON p.product_id = pi.product_id
WHERE p.is_available = TRUE
GROUP BY p.product_id, p.product_name, p.category, pi.quantity_kg, p.is_exclusive_for
ORDER BY p.category DESC, need_to_order_kg DESC;
-- =============================================
-- END OF FILE
-- =============================================

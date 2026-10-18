-- =====================================================
-- goit-rdb-fp: фінальний проєкт (PostgreSQL)
-- =====================================================

-- -----------------------------------------------------
-- 1. Завантаження даних
-- -----------------------------------------------------
CREATE SCHEMA IF NOT EXISTS pandemic;
SET search_path TO pandemic;

-- Якщо CSV було імпортовано в схему public (DBeaver за замовчуванням),
-- переносимо таблицю в pandemic (порожню таблицю в pandemic видаляємо)
-- і приводимо назву колонки "Year" до нижнього регістру.
DO $$
BEGIN
    IF to_regclass('public.infectious_cases') IS NOT NULL THEN
        DROP TABLE IF EXISTS pandemic.infectious_cases;
        ALTER TABLE public.infectious_cases SET SCHEMA pandemic;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'pandemic'
                 AND table_name = 'infectious_cases'
                 AND column_name = 'Year') THEN
        ALTER TABLE pandemic.infectious_cases RENAME COLUMN "Year" TO year;
    END IF;
END $$;

-- Якщо таблиці ще немає ніде, створюємо її (усі показники як TEXT,
-- бо в CSV є порожні значення) і імпортуємо CSV саме в pandemic.infectious_cases.
CREATE TABLE IF NOT EXISTS infectious_cases (
    Entity                  TEXT,
    Code                    TEXT,
    Year                    INT,
    Number_yaws             TEXT,
    polio_cases             TEXT,
    cases_guinea_worm       TEXT,
    Number_rabies           TEXT,
    Number_malaria          TEXT,
    Number_hiv              TEXT,
    Number_tuberculosis     TEXT,
    Number_smallpox         TEXT,
    Number_cholera_cases    TEXT
);

-- Імпорт: DBeaver -> ПКМ на таблиці -> Import Data -> CSV,
-- або через psql (виконується на клієнті):
-- \copy pandemic.infectious_cases FROM 'infectious_cases.csv' WITH (FORMAT csv, HEADER true);

-- Перегляд даних
SELECT * FROM infectious_cases LIMIT 20;
SELECT COUNT(*) FROM infectious_cases;

-- -----------------------------------------------------
-- 2. Нормалізація до 3НФ
-- -----------------------------------------------------
DROP TABLE IF EXISTS infectious_cases_norm;
DROP TABLE IF EXISTS entities;

-- Таблиця унікальних комбінацій Entity + Code
CREATE TABLE entities (
    id      SERIAL PRIMARY KEY,
    entity  TEXT NOT NULL,
    code    TEXT,
    UNIQUE (entity, code)
);

INSERT INTO entities (entity, code)
SELECT DISTINCT Entity, Code
FROM infectious_cases;

-- Таблиця з показниками, замість Entity/Code використовується entity_id
CREATE TABLE infectious_cases_norm (
    id                      SERIAL PRIMARY KEY,
    entity_id               INT NOT NULL REFERENCES entities(id),
    year                    INT NOT NULL,
    number_yaws             TEXT,
    polio_cases             TEXT,
    cases_guinea_worm       TEXT,
    number_rabies           TEXT,
    number_malaria          TEXT,
    number_hiv              TEXT,
    number_tuberculosis     TEXT,
    number_smallpox         TEXT,
    number_cholera_cases    TEXT
);

INSERT INTO infectious_cases_norm (
    entity_id, year, number_yaws, polio_cases, cases_guinea_worm,
    number_rabies, number_malaria, number_hiv, number_tuberculosis,
    number_smallpox, number_cholera_cases
)
SELECT
    e.id, ic.year, ic.Number_yaws::TEXT, ic.polio_cases::TEXT, ic.cases_guinea_worm::TEXT,
    ic.Number_rabies::TEXT, ic.Number_malaria::TEXT, ic.Number_hiv::TEXT, ic.Number_tuberculosis::TEXT,
    ic.Number_smallpox::TEXT, ic.Number_cholera_cases::TEXT
FROM infectious_cases ic
JOIN entities e
  ON e.entity = ic.Entity
 AND e.code IS NOT DISTINCT FROM ic.Code;

-- Перевірка: кількість рядків має збігатися з вихідною таблицею
SELECT
    (SELECT COUNT(*) FROM infectious_cases)      AS original_rows,
    (SELECT COUNT(*) FROM infectious_cases_norm) AS normalized_rows;

-- -----------------------------------------------------
-- 3. Аналіз Number_rabies
-- -----------------------------------------------------
SELECT
    e.id,
    e.entity,
    e.code,
    AVG(n.number_rabies::NUMERIC) AS avg_rabies,
    MIN(n.number_rabies::NUMERIC) AS min_rabies,
    MAX(n.number_rabies::NUMERIC) AS max_rabies,
    SUM(n.number_rabies::NUMERIC) AS sum_rabies
FROM infectious_cases_norm n
JOIN entities e ON e.id = n.entity_id
WHERE n.number_rabies ~ '^\s*-?\d+(\.\d+)?\s*$'   -- лише числові значення
GROUP BY e.id, e.entity, e.code
ORDER BY avg_rabies DESC
LIMIT 10;

-- -----------------------------------------------------
-- 4. Різниця в роках (вбудовані функції)
-- -----------------------------------------------------
SELECT
    n.year,
    MAKE_DATE(n.year, 1, 1)                                         AS first_jan,
    CURRENT_DATE                                                    AS today,
    DATE_PART('year', AGE(CURRENT_DATE, MAKE_DATE(n.year, 1, 1)))::INT AS year_diff
FROM infectious_cases_norm n;

-- -----------------------------------------------------
-- 5. Власні функції
-- -----------------------------------------------------

-- 5.1 Різниця в роках між поточною датою та 1 січня вказаного року
CREATE OR REPLACE FUNCTION pandemic.year_diff(p_year INT)
RETURNS INT
LANGUAGE SQL
STABLE
AS $$
    SELECT DATE_PART('year', AGE(CURRENT_DATE, MAKE_DATE(p_year, 1, 1)))::INT;
$$;

-- 5.2 Середня кількість захворювань за період (кількість / дільник)
CREATE OR REPLACE FUNCTION pandemic.avg_cases_per_period(p_cases NUMERIC, p_divisor NUMERIC)
RETURNS NUMERIC
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_divisor IS NULL OR p_divisor = 0 THEN NULL
        ELSE ROUND(p_cases / p_divisor, 2)
    END;
$$;

-- Використання year_diff
SELECT
    n.year,
    MAKE_DATE(n.year, 1, 1) AS first_jan,
    CURRENT_DATE            AS today,
    pandemic.year_diff(n.year) AS year_diff
FROM infectious_cases_norm n
LIMIT 20;

-- Використання avg_cases_per_period (лише числові значення Number_rabies)
SELECT
    e.entity,
    e.code,
    n.year,
    n.number_rabies::NUMERIC                                      AS cases_per_year,
    pandemic.avg_cases_per_period(n.number_rabies::NUMERIC, 12)   AS per_month,
    pandemic.avg_cases_per_period(n.number_rabies::NUMERIC, 4)    AS per_quarter,
    pandemic.avg_cases_per_period(n.number_rabies::NUMERIC, 2)    AS per_half_year,
    pandemic.year_diff(n.year)                                    AS year_diff
FROM infectious_cases_norm n
JOIN entities e ON e.id = n.entity_id
WHERE n.number_rabies ~ '^\s*-?\d+(\.\d+)?\s*$'
ORDER BY e.entity, n.year
LIMIT 30;

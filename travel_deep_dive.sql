-- ============================================================
-- Углублённый анализ: продукт Travel
-- Данные: insurance_policies_claims_2018_2025_clean.txt (очищенный)
-- СУБД: DuckDB
-- Оконные функции: SUM() OVER, LAG(), RANK(), кумулятивная SUM() OVER
-- ============================================================

-- Запрос 1. Доля Travel в общих премиях по годам
SELECT
  year("Дата начала полиса") AS policy_year,
  SUM(CASE WHEN "Тип страхования" = 'Travel' THEN "Страховая премия" ELSE 0 END) AS travel_premium,
  SUM("Страховая премия") AS total_premium,
  ROUND(
    100.0 * SUM(CASE WHEN "Тип страхования" = 'Travel' THEN "Страховая премия" ELSE 0 END)
          / SUM("Страховая премия"),
    2
  ) AS travel_share_pct
FROM insurance_clean
GROUP BY policy_year
ORDER BY policy_year;

-- Запрос 2. YoY-прирост премий и убытков внутри Travel
WITH yearly AS (
  SELECT
    year("Дата начала полиса") AS policy_year,
    ROUND(SUM("Страховая премия"), 2) AS premium,
    ROUND(SUM(CASE WHEN "Статус убытка" = 'paid' THEN "Сумма убытка" ELSE 0 END), 2) AS claims
  FROM insurance_clean
  WHERE "Тип страхования" = 'Travel'
  GROUP BY policy_year
)
SELECT
  policy_year,
  premium,
  claims,
  ROUND(100.0 * (premium - LAG(premium) OVER (ORDER BY policy_year))
        / LAG(premium) OVER (ORDER BY policy_year), 2) AS premium_yoy_pct,
  ROUND(100.0 * (claims - LAG(claims) OVER (ORDER BY policy_year))
        / LAG(claims) OVER (ORDER BY policy_year), 2) AS claims_yoy_pct
FROM yearly
ORDER BY policy_year;

-- Запрос 3. Топ-3 города по премиям Travel в каждом году
WITH city_premium AS (
  SELECT
    year("Дата начала полиса") AS policy_year,
    "Город" AS city,
    ROUND(SUM("Страховая премия"), 2) AS premium
  FROM insurance_clean
  WHERE "Тип страхования" = 'Travel'
  GROUP BY policy_year, "Город"
),
ranked AS (
  SELECT
    policy_year,
    city,
    premium,
    RANK() OVER (PARTITION BY policy_year ORDER BY premium DESC) AS city_rank
  FROM city_premium
)
SELECT *
FROM ranked
WHERE city_rank <= 3
ORDER BY policy_year, city_rank;

-- Запрос 4. ABC-анализ клиентов внутри Travel (кумулятивная доля)
WITH client_premium AS (
  SELECT
    "Код клиента" AS customer_id,
    ROUND(SUM("Страховая премия"), 2) AS premium
  FROM insurance_clean
  WHERE "Тип страхования" = 'Travel'
  GROUP BY "Код клиента"
),
ranked AS (
  SELECT
    customer_id,
    premium,
    SUM(premium) OVER (ORDER BY premium DESC) AS cum_premium,
    SUM(premium) OVER () AS total_premium
  FROM client_premium
)
SELECT
  COUNT(*) AS total_clients,
  SUM(CASE WHEN cum_premium / total_premium <= 0.80 THEN 1 ELSE 0 END) AS clients_A,
  SUM(CASE WHEN cum_premium / total_premium > 0.80
            AND cum_premium / total_premium <= 0.95 THEN 1 ELSE 0 END) AS clients_B,
  SUM(CASE WHEN cum_premium / total_premium > 0.95 THEN 1 ELSE 0 END) AS clients_C,
  ROUND(100.0 * SUM(CASE WHEN cum_premium / total_premium <= 0.80 THEN 1 ELSE 0 END) / COUNT(*), 2) AS share_A_pct
FROM ranked;
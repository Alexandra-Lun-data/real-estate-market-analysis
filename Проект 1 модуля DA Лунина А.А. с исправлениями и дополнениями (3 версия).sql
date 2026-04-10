/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 *
 * Автор: Лунина Александра Александровна
 * Дата:12.02.2026
*/



-- Задача 1: Время активности объявлений
WITH flat_limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений по квартирам, которые не содержат выбросы:
flats_filtered_id AS (
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM flat_limits)
        AND (rooms < (SELECT rooms_limit FROM flat_limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM flat_limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM flat_limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM flat_limits)) OR ceiling_height IS NULL)
),
-- Выведем объявления по квартирам без выбросов:
filtered_flats AS (
    SELECT *
    FROM real_estate.flats
    WHERE id IN (SELECT id FROM flats_filtered_id)
),
-- Добавим необходимые характеристики для расчета
-- Убрала фильтрацию выбросов по объявлениям
flats_filtered AS (
    SELECT 
        f.id,
        a.last_price/f.total_area AS price_per_m2,
        f.total_area,
        f.rooms,
        f.balcony,
        f.floor,
        a.first_day_exposition,
        a.days_exposition,
        a.last_price,
        f.airports_nearest,
        f.parks_around3000,
        f.ponds_around3000,
        f.is_apartment,
        CASE 
            WHEN c.city = 'Санкт-Петербург' THEN 'СПБ'
            ELSE 'ЛенОбл'
        END AS region,
        CASE 
            WHEN a.days_exposition BETWEEN 1 AND 30 THEN 'до месяца'
            WHEN a.days_exposition BETWEEN 31 AND 90 THEN 'до 3 месяцев'
            WHEN a.days_exposition BETWEEN 91 AND 180 THEN 'до полугода'
            WHEN a.days_exposition > 181 THEN 'более полугода'
            ELSE 'non category'
        END AS exposition_period
    FROM filtered_flats AS f
    LEFT JOIN real_estate.city AS c ON f.city_id = c.city_id
    LEFT JOIN real_estate.advertisement AS a ON f.id = a.id
    LEFT JOIN real_estate.type AS t ON f.type_id = t.type_id
    WHERE a.id IN (SELECT id FROM filtered_flats)
        AND t.type = 'город'
        AND EXTRACT(YEAR FROM a.first_day_exposition) BETWEEN 2015 AND 2018
),
-- Добавляем CTE для расчета статистики по регионам
region_stats AS (
    SELECT 
        region,
        COUNT(*) AS total_in_region,
        COUNT(CASE WHEN exposition_period != 'non category' THEN 1 END) AS stil_in_region
    FROM flats_filtered
    GROUP BY region
)
-- Итоговый запрос для вывода таблицы:
SELECT 
    f.region,
    f.exposition_period,
    -- Характеристики квартир:
    ROUND(AVG(f.price_per_m2)::NUMERIC, 2) AS avg_price_per_m2,
    ROUND(AVG(f.total_area)::NUMERIC, 2) AS avg_total_area,
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY f.rooms) AS med_rooms,
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY f.balcony) AS med_balkony,
    PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY f.floor) AS med_floor,
    -- Характеристики объявлений:
    COUNT(f.id) AS total_adv,
    MAX(r.total_in_region) AS total_in_region,
    MAX(r.stil_in_region) AS stil_in_region,
    ROUND(MAX(r.stil_in_region)::NUMERIC / NULLIF(MAX(r.total_in_region), 0) * 100, 2) AS perc_stil_in_region,
    -- Статистика по апартаментам
    COUNT(CASE WHEN f.is_apartment = 1 THEN f.id END) AS total_apartments,
    COUNT(CASE WHEN f.exposition_period != 'non category' AND f.is_apartment = 1 THEN f.id END) AS sold_apartments,
    ROUND(COUNT(CASE WHEN f.exposition_period != 'non category' AND f.is_apartment = 1 THEN f.id END)::NUMERIC / 
        NULLIF(COUNT(CASE WHEN f.is_apartment = 1 THEN f.id END), 0) * 100, 2) AS perc_sold_apartments,
    -- Статистика по близости к аэропорту
    COUNT(CASE WHEN f.airports_nearest IS NOT NULL THEN f.id END) AS total_near_airport,
    COUNT(CASE WHEN f.exposition_period != 'non category' AND f.airports_nearest IS NOT NULL THEN f.id END) AS sold_near_airport,
    ROUND(COUNT(CASE WHEN f.exposition_period != 'non category' AND f.airports_nearest IS NOT NULL THEN f.id END)::NUMERIC / 
        NULLIF(COUNT(CASE WHEN f.airports_nearest IS NOT NULL THEN f.id END), 0) * 100, 2) AS perc_sold_near_airport,
    -- Статистика по близости к парку
    COUNT(CASE WHEN f.parks_around3000 > 0 THEN f.id END) AS total_near_park,
    COUNT(CASE WHEN f.exposition_period != 'non category' AND f.parks_around3000 > 0 THEN f.id END) AS sold_near_park,
    ROUND(COUNT(CASE WHEN f.exposition_period != 'non category' AND f.parks_around3000 > 0 THEN f.id END)::NUMERIC / 
        NULLIF(COUNT(CASE WHEN f.parks_around3000 > 0 THEN f.id END), 0) * 100, 2) AS perc_sold_near_park,
    -- Статистика по близости к водоему
    COUNT(CASE WHEN f.ponds_around3000 > 0 THEN f.id END) AS total_near_pond,
    COUNT(CASE WHEN f.exposition_period != 'non category' AND f.ponds_around3000 > 0 THEN f.id END) AS sold_near_pond,
    ROUND(COUNT(CASE WHEN f.exposition_period != 'non category' AND f.ponds_around3000 > 0 THEN f.id END)::NUMERIC / 
        NULLIF(COUNT(CASE WHEN f.ponds_around3000 > 0 THEN f.id END), 0) * 100, 2) AS perc_sold_near_pond
FROM flats_filtered f
LEFT JOIN region_stats r ON f.region = r.region
GROUP BY f.region, f.exposition_period
ORDER BY f.region, f.exposition_period;

-- Задача 2: Сезонность объявлений
WITH flat_limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений по квартирам, которые не содержат выбросы:
flats_filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM flat_limits)
        AND (rooms < (SELECT rooms_limit FROM flat_limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM flat_limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM flat_limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM flat_limits)) OR ceiling_height IS NULL)
    ),
-- Выведем объявления по квартирам без выбросов:
filtered_flats AS (
SELECT *
FROM real_estate.flats
WHERE id IN (SELECT * FROM flats_filtered_id)),
--Исправила оператор where
month_stats AS (
 SELECT a.id,
    a.last_price / NULLIF(f.total_area, 0) AS price_per_m2,
    f.total_area,
        EXTRACT(MONTH FROM a.first_day_exposition) AS month_beg,
        EXTRACT(MONTH FROM a.first_day_exposition + a.days_exposition::integer) AS month_end        
FROM filtered_flats AS f
LEFT JOIN real_estate.city AS c ON f.city_id = c.city_id
LEFT JOIN real_estate.advertisement AS a ON f.id = a.id
LEFT JOIN real_estate.type AS t ON f.type_id=t.type_id
WHERE a.id IN (SELECT id FROM filtered_flats)
AND t.TYPE='город'
AND EXTRACT(YEAR FROM a.first_day_exposition) BETWEEN 2015 AND 2018),
--СТЕ для начала публикации объявления
published_stats AS ( 
SELECT 
        month_beg AS month_number,
        COUNT(id) AS published_count,
        ROUND(AVG(price_per_m2)::NUMERIC, 2) AS published_avg_price,
        ROUND(AVG(total_area)::NUMERIC, 2) AS published_avg_area,
        ROUND(MIN(price_per_m2)::NUMERIC, 2) AS published_min_price,
        ROUND(MAX(price_per_m2)::NUMERIC, 2) AS published_max_price,
        ROUND(MIN(total_area)::NUMERIC, 2) AS published_min_area,
        ROUND(MAX(total_area)::NUMERIC, 2) AS published_max_area
    FROM month_stats
    GROUP BY month_beg),
 --СТЕ для снятия с продажи
 sold_stats AS (
    SELECT 
        month_end AS month_number,
        COUNT(id) AS sold_count,
        ROUND(AVG(price_per_m2)::NUMERIC, 2) AS sold_avg_price,
        ROUND(AVG(total_area)::NUMERIC, 2) AS sold_avg_area,
        ROUND(MIN(price_per_m2)::NUMERIC, 2) AS sold_min_price,
        ROUND(MAX(price_per_m2)::NUMERIC, 2) AS sold_max_price,
        ROUND(MIN(total_area)::NUMERIC, 2) AS sold_min_area,
        ROUND(MAX(total_area)::NUMERIC, 2) AS sold_max_area
    FROM month_stats
    WHERE month_end IS NOT NULL
    GROUP BY month_end),
  --СТЕ для соединения номеров месяцев
    all_months AS (
    SELECT DISTINCT month_number FROM published_stats
    UNION
    SELECT DISTINCT month_number FROM sold_stats)
   --Итоговая таблица
    SELECT 
          TO_CHAR(TO_DATE(am.month_number::TEXT, 'MM'), 'Month') AS month_name,
    am.month_number,
          COALESCE(ps.published_count, 0) AS published_ads_count,
          COALESCE(ps.published_avg_price, 0) AS published_avg_price_per_m2,
          COALESCE(ps.published_avg_area, 0) AS published_avg_total_area,
          COALESCE(ps.published_min_price, 0) AS published_min_price_per_m2,
          COALESCE(ps.published_max_price, 0) AS published_max_price_per_m2,
          COALESCE(ps.published_min_area, 0) AS published_min_total_area,
          COALESCE(ps.published_max_area, 0) AS published_max_total_area,
          COALESCE(ss.sold_count, 0) AS sold_ads_count,
          COALESCE(ss.sold_avg_price, 0) AS sold_avg_price_per_m2,
          COALESCE(ss.sold_avg_area, 0) AS sold_avg_total_area,
          COALESCE(ss.sold_min_price, 0) AS sold_min_price_per_m2,
          COALESCE(ss.sold_max_price, 0) AS sold_max_price_per_m2,
          COALESCE(ss.sold_min_area, 0) AS sold_min_total_area,
          COALESCE(ss.sold_max_area, 0) AS sold_max_total_area
    FROM all_months am
    LEFT JOIN published_stats ps ON am.month_number = ps.month_number
    LEFT JOIN sold_stats ss ON am.month_number = ss.month_number
    ORDER BY am.month_number;

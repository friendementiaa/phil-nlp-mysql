-- =============================================================
-- 03_queries.sql  —  Аналитические запросы
-- =============================================================
USE phil_nlp;


-- -------------------------------------------------------------
-- ЗАПРОС 1. Простой SELECT с фильтрацией и сортировкой
-- Смысл: найти самые длинные предложения в базе.
-- Использует составной индекс idx_sent_work_len.
-- -------------------------------------------------------------
SELECT
    a.name                  AS author,
    w.title                 AS work,
    s.sentence_length,
    s.token_count,
    LEFT(s.sentence, 120)   AS preview
FROM sentences s
JOIN works    w ON w.id = s.work_id
JOIN authors  a ON a.id = w.author_id
WHERE s.sentence_length > 400
ORDER BY s.sentence_length DESC
LIMIT 20;


-- -------------------------------------------------------------
-- ЗАПРОС 2. JOIN трёх таблиц с условием
-- Смысл: все произведения аналитических философов
-- с количеством предложений и средней длиной.
-- -------------------------------------------------------------
SELECT
    a.name          AS author,
    w.title         AS work,
    a.school,
    COUNT(s.id)     AS sentence_count,
    ROUND(AVG(s.sentence_length), 1) AS avg_len
FROM authors  a
JOIN works    w ON w.author_id = a.id
JOIN sentences s ON s.work_id  = w.id
WHERE a.school = 'analytic'
GROUP BY a.id, a.name, w.id, w.title, a.school
ORDER BY sentence_count DESC;


-- -------------------------------------------------------------
-- ЗАПРОС 3. Подзапрос в HAVING
-- Смысл: авторы, у которых средняя длина предложения
-- превышает общую среднюю по всей базе.
-- -------------------------------------------------------------
SELECT
    a.name   AS author,
    a.school,
    ROUND(AVG(s.sentence_length), 1) AS avg_len
FROM authors  a
JOIN works    w ON w.author_id = a.id
JOIN sentences s ON s.work_id  = w.id
GROUP BY a.id, a.name, a.school
HAVING AVG(s.sentence_length) > (
    SELECT AVG(sentence_length) FROM sentences
)
ORDER BY avg_len DESC;


-- -------------------------------------------------------------
-- ЗАПРОС 4. GROUP BY + оконная функция RANK
-- Смысл: ранжирование авторов внутри каждой школы
-- по общему числу предложений.
-- -------------------------------------------------------------
SELECT
    school,
    author_name,
    total_sentences,
    RANK() OVER (
        PARTITION BY school
        ORDER BY total_sentences DESC
    ) AS rank_in_school
FROM author_stats_cache
ORDER BY school, rank_in_school;


-- -------------------------------------------------------------
-- ЗАПРОС 5а. JSON — извлечение через -> и ->>
-- Смысл: посмотреть токены и лемматизацию для коротких предложений Платона.
-- -> возвращает JSON-тип, ->> возвращает строку без кавычек.
-- -------------------------------------------------------------
SELECT
    a.name,
    s.sentence,
    s.nlp_json ->> '$.lowered'            AS lowered,
    JSON_LENGTH(s.nlp_json -> '$.tokens') AS token_count_json,
    s.nlp_json ->> '$.lemmatized'         AS lemmatized
FROM sentences s
JOIN works   w ON w.id = s.work_id
JOIN authors a ON a.id = w.author_id
WHERE s.sentence_length < 40
  AND a.name = 'Plato'
LIMIT 10;


-- -------------------------------------------------------------
-- ЗАПРОС 5б. JSON_TABLE — разворачивание массива токенов
-- Смысл: топ-10 самых частых токенов у Канта.
-- JSON_TABLE превращает JSON-массив в реляционные строки.
-- -------------------------------------------------------------
SELECT
    jt.token,
    COUNT(*) AS freq
FROM sentences s
JOIN works    w ON w.id = s.work_id
JOIN authors  a ON a.id = w.author_id,
JSON_TABLE(
    s.nlp_json,
    '$.tokens[*]' COLUMNS (token VARCHAR(100) PATH '$')
) AS jt
WHERE a.name = 'Kant'
  AND LENGTH(jt.token) > 3
GROUP BY jt.token
ORDER BY freq DESC
LIMIT 10;


-- -------------------------------------------------------------
-- ЗАПРОС 5в. JSON_OBJECTAGG
-- Смысл: собрать в один JSON среднее число токенов по каждой школе.
-- -------------------------------------------------------------
SELECT
    JSON_OBJECTAGG(school, avg_tokens) AS school_token_stats
FROM (
    SELECT
        a.school,
        ROUND(AVG(s.token_count), 1) AS avg_tokens
    FROM authors  a
    JOIN works    w ON w.author_id = a.id
    JOIN sentences s ON s.work_id  = w.id
    GROUP BY a.school
) AS school_agg;


-- -------------------------------------------------------------
-- ЗАПРОС 6. Полнотекстовый поиск MATCH ... AGAINST
-- Смысл: найти предложения, релевантные "mind consciousness",
-- отсортированные по релевантности.
-- -------------------------------------------------------------
SELECT
    a.name AS author,
    ROUND(
        MATCH(s.sentence) AGAINST ('mind consciousness' IN NATURAL LANGUAGE MODE),
        4
    ) AS relevance,
    LEFT(s.sentence, 150) AS preview
FROM sentences s
JOIN works   w ON w.id = s.work_id
JOIN authors a ON a.id = w.author_id
WHERE MATCH(s.sentence) AGAINST ('mind consciousness' IN NATURAL LANGUAGE MODE)
ORDER BY relevance DESC
LIMIT 15;


-- -------------------------------------------------------------
-- ЗАПРОС 7 (бонус). ROW_NUMBER + подзапрос в FROM
-- Смысл: для каждого произведения вывести первое предложение
-- и общее количество предложений.
-- -------------------------------------------------------------
SELECT
    a.name  AS author,
    w.title,
    r.total_sents,
    r.first_sentence
FROM works w
JOIN authors a ON a.id = w.author_id
JOIN (
    SELECT
        work_id,
        COUNT(*)                                                    AS total_sents,
        FIRST_VALUE(LEFT(sentence, 100))
            OVER (PARTITION BY work_id ORDER BY id)                AS first_sentence,
        ROW_NUMBER() OVER (PARTITION BY work_id ORDER BY id)       AS rn
    FROM sentences
) r ON r.work_id = w.id AND r.rn = 1
ORDER BY a.school, a.name;

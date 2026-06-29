-- =============================================================
-- 04_explain.sql  —  Оптимизация и планы выполнения
-- =============================================================
USE phil_nlp;


-- =============================================================
-- ДЕМОНСТРАЦИЯ 1: фильтрация по sentence_length
-- =============================================================

-- ДО: без индекса (временно сбрасываем)
-- ALTER TABLE sentences DROP INDEX idx_sent_work_len;

EXPLAIN
SELECT id, sentence_length, LEFT(sentence, 80)
FROM sentences
WHERE sentence_length > 400
ORDER BY sentence_length DESC;
-- Ожидаем: type=ALL (full scan), rows ≈ 16 000

-- ПОСЛЕ: с составным индексом idx_sent_work_len(work_id, sentence_length)
-- (индекс уже создан в 01_schema.sql)
-- Восстанавливаем, если удаляли:
-- CREATE INDEX idx_sent_work_len ON sentences(work_id, sentence_length);

EXPLAIN
SELECT id, work_id, sentence_length, LEFT(sentence, 80)
FROM sentences
WHERE work_id = 3 AND sentence_length > 400
ORDER BY sentence_length DESC;
-- Ожидаем: type=range, key=idx_sent_work_len, rows значительно меньше


-- =============================================================
-- ДЕМОНСТРАЦИЯ 2: полнотекстовый поиск
-- =============================================================

-- БЕЗ fulltext: LIKE вынуждает full scan
EXPLAIN
SELECT id, LEFT(sentence, 80)
FROM sentences
WHERE sentence LIKE '%consciousness%';
-- type=ALL, rows ≈ 16 000

-- С FULLTEXT-индексом ft_sentence
EXPLAIN
SELECT id, LEFT(sentence, 80)
FROM sentences
WHERE MATCH(sentence) AGAINST ('consciousness' IN NATURAL LANGUAGE MODE);
-- type=fulltext, key=ft_sentence — быстрее на больших объёмах


-- =============================================================
-- ТРИГГЕР: автоматическое обновление кеша при вставке предложения
-- =============================================================

DELIMITER $$

DROP TRIGGER IF EXISTS trg_after_insert_sentence$$

CREATE TRIGGER trg_after_insert_sentence
AFTER INSERT ON sentences
FOR EACH ROW
BEGIN
    DECLARE v_author_id INT;
    DECLARE v_author_name VARCHAR(100);
    DECLARE v_school VARCHAR(50);

    -- Находим автора по work_id нового предложения
    SELECT w.author_id, a.name, a.school
    INTO v_author_id, v_author_name, v_school
    FROM works w
    JOIN authors a ON a.id = w.author_id
    WHERE w.id = NEW.work_id
    LIMIT 1;

    -- Обновляем (или вставляем) строку в MEMORY-кеш
    INSERT INTO author_stats_cache (author_id, author_name, school, total_sentences, avg_length)
    SELECT
        v_author_id,
        v_author_name,
        v_school,
        COUNT(*),
        AVG(s.sentence_length)
    FROM sentences s
    JOIN works w ON w.id = s.work_id
    WHERE w.author_id = v_author_id
    ON DUPLICATE KEY UPDATE
        school          = VALUES(school),
        total_sentences = VALUES(total_sentences),
        avg_length      = VALUES(avg_length);
END$$

DELIMITER ;


-- =============================================================
-- ХРАНИМАЯ ПРОЦЕДУРА: топ-N авторов по школе
-- =============================================================

DELIMITER $$

DROP PROCEDURE IF EXISTS GetTopAuthorsBySchool$$

CREATE PROCEDURE GetTopAuthorsBySchool(
    IN  p_school VARCHAR(50),
    IN  p_limit  INT
)
BEGIN
    SELECT
        a.name          AS author,
        COUNT(s.id)     AS total_sentences,
        ROUND(AVG(s.sentence_length), 1) AS avg_sentence_len,
        ROUND(AVG(s.token_count), 1)     AS avg_tokens
    FROM authors  a
    JOIN works    w ON w.author_id = a.id
    JOIN sentences s ON s.work_id  = w.id
    WHERE a.school = p_school
    GROUP BY a.id, a.name
    ORDER BY total_sentences DESC
    LIMIT p_limit;
END$$

DELIMITER ;

-- Пример вызова:
-- CALL GetTopAuthorsBySchool('analytic', 5);
-- CALL GetTopAuthorsBySchool('phenomenology', 3);


-- =============================================================
-- JSON vs. нормализация: сравнение подходов
-- =============================================================

-- Подход A (текущий): читаем token_count из генерируемого столбца — быстро
EXPLAIN
SELECT work_id, AVG(token_count)
FROM sentences
GROUP BY work_id;
-- key=idx_sent_token_count, нет обращения к JSON

-- Подход B: считаем длину массива напрямую из JSON — медленнее
EXPLAIN
SELECT work_id, AVG(JSON_LENGTH(nlp_json->'$.tokens'))
FROM sentences
GROUP BY work_id;
-- type=ALL, каждый раз парсим JSON-документ
-- Вывод: генерируемый столбец + индекс решает проблему без денормализации

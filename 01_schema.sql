CREATE DATABASE IF NOT EXISTS phil_nlp;
USE phil_nlp;

-- Авторы и их философская школа.
-- bio_json хранит дополнительные гибкие данные: век рождения, национальность, эпоху.
CREATE TABLE authors (
    id       INT PRIMARY KEY AUTO_INCREMENT,
    name     VARCHAR(100) NOT NULL,
    school   VARCHAR(50) NOT NULL,
    bio_json JSON,
    UNIQUE KEY uq_authors_name (name)
);

-- Произведения. Каждое произведение принадлежит одному автору.
CREATE TABLE works (
    id        INT PRIMARY KEY AUTO_INCREMENT,
    author_id INT NOT NULL,
    title     VARCHAR(255) NOT NULL,
    CONSTRAINT fk_works_author
        FOREIGN KEY (author_id) REFERENCES authors(id),
    UNIQUE KEY uq_works_author_title (author_id, title),
    INDEX idx_works_author (author_id)
);

-- Предложения из произведений с NLP-разметкой.
-- nlp_json хранит токены, лемматизацию и текст в нижнем регистре.
CREATE TABLE sentences (
    id              INT PRIMARY KEY AUTO_INCREMENT,
    work_id         INT NOT NULL,
    sentence        TEXT NOT NULL,
    sentence_length INT NOT NULL,
    nlp_json        JSON,
    token_count     INT GENERATED ALWAYS AS (
        JSON_LENGTH(JSON_EXTRACT(nlp_json, '$.tokens'))
    ) STORED,
    CONSTRAINT fk_sentences_work
        FOREIGN KEY (work_id) REFERENCES works(id),
    INDEX idx_sent_work_len (work_id, sentence_length),
    INDEX idx_sent_token_count (work_id, token_count),
    FULLTEXT INDEX ft_sentence (sentence)
);

-- Быстрый кеш статистики по авторам.
-- Он нужен для запросов с рейтингами и обновляется после импорта/триггером.
CREATE TABLE author_stats_cache (
    author_id       INT PRIMARY KEY,
    author_name     VARCHAR(100) NOT NULL,
    school          VARCHAR(50) NOT NULL,
    total_sentences INT NOT NULL,
    avg_length      DECIMAL(10, 2)
) ENGINE = MEMORY;

"""
02_import.py
Импорт данных философского NLP-датасета в MySQL.

Требования:
    pip install mysql-connector-python pandas

Запуск:
    python 02_import.py

Перед запуском убедитесь, что схема уже создана (01_schema.sql выполнен).
"""

import json
import ast
import os
import pandas as pd
import mysql.connector

# --- Настройки подключения ---
DB_CONFIG = {
    "host":     os.getenv("MYSQL_HOST", "localhost"),
    "port":     int(os.getenv("MYSQL_PORT", "3306")),
    "user":     os.getenv("MYSQL_USER", "root"),
    "password": os.getenv("MYSQL_PASSWORD", ""),
    "database": "phil_nlp",
    "charset":  "utf8mb4",
}

CSV_PATH = os.getenv("CSV_PATH", "phil_nlp.csv")

# --- Биографические данные авторов (хранятся в JSON-столбце) ---
BIO_DATA = {
    "Plato":         {"birth_century": -5, "nationality": "Greek",    "era": "Ancient"},
    "Aristotle":     {"birth_century": -4, "nationality": "Greek",    "era": "Ancient"},
    "Descartes":     {"birth_century": 17, "nationality": "French",   "era": "Early Modern"},
    "Spinoza":       {"birth_century": 17, "nationality": "Dutch",    "era": "Early Modern"},
    "Leibniz":       {"birth_century": 17, "nationality": "German",   "era": "Early Modern"},
    "Malebranche":   {"birth_century": 17, "nationality": "French",   "era": "Early Modern"},
    "Locke":         {"birth_century": 17, "nationality": "British",  "era": "Early Modern"},
    "Hume":          {"birth_century": 18, "nationality": "Scottish", "era": "Enlightenment"},
    "Berkeley":      {"birth_century": 18, "nationality": "Irish",    "era": "Enlightenment"},
    "Kant":          {"birth_century": 18, "nationality": "German",   "era": "Enlightenment"},
    "Fichte":        {"birth_century": 18, "nationality": "German",   "era": "German Idealism"},
    "Hegel":         {"birth_century": 18, "nationality": "German",   "era": "German Idealism"},
    "Marx":          {"birth_century": 19, "nationality": "German",   "era": "Modern"},
    "Lenin":         {"birth_century": 19, "nationality": "Russian",  "era": "Modern"},
    "Smith":         {"birth_century": 18, "nationality": "Scottish", "era": "Enlightenment"},
    "Ricardo":       {"birth_century": 18, "nationality": "British",  "era": "Modern"},
    "Keynes":        {"birth_century": 19, "nationality": "British",  "era": "Modern"},
    "Russell":       {"birth_century": 19, "nationality": "British",  "era": "Analytic"},
    "Moore":         {"birth_century": 19, "nationality": "British",  "era": "Analytic"},
    "Wittgenstein":  {"birth_century": 19, "nationality": "Austrian", "era": "Analytic"},
    "Lewis":         {"birth_century": 20, "nationality": "American", "era": "Analytic"},
    "Quine":         {"birth_century": 20, "nationality": "American", "era": "Analytic"},
    "Popper":        {"birth_century": 20, "nationality": "Austrian", "era": "Analytic"},
    "Kripke":        {"birth_century": 20, "nationality": "American", "era": "Analytic"},
    "Foucault":      {"birth_century": 20, "nationality": "French",   "era": "Continental"},
    "Derrida":       {"birth_century": 20, "nationality": "French",   "era": "Continental"},
    "Deleuze":       {"birth_century": 20, "nationality": "French",   "era": "Continental"},
    "Husserl":       {"birth_century": 19, "nationality": "German",   "era": "Phenomenology"},
    "Heidegger":     {"birth_century": 19, "nationality": "German",   "era": "Phenomenology"},
    "Merleau-Ponty": {"birth_century": 20, "nationality": "French",   "era": "Phenomenology"},
}

BATCH_SIZE = 500   # строк за один INSERT


def make_nlp_json(row) -> str:
    """Собирает NLP-данные в JSON-строку для хранения в nlp_json."""
    try:
        tokens = ast.literal_eval(row["tokenized_txt"]) if isinstance(row["tokenized_txt"], str) else []
    except Exception:
        tokens = []
    return json.dumps(
        {
            "tokens":    tokens,
            "lemmatized": str(row["lemmatized_str"]).strip(),
            "lowered":    str(row["sentence_lowered"]).strip(),
        },
        ensure_ascii=False,
    )


def load_csv(path: str) -> pd.DataFrame:
    return pd.read_csv(path)


def insert_authors(cursor, df: pd.DataFrame) -> dict:
    """Вставляет авторов, возвращает словарь name → id."""
    authors = df[["author", "school"]].drop_duplicates()
    rows = []
    for _, row in authors.iterrows():
        bio = json.dumps(BIO_DATA.get(row["author"], {}), ensure_ascii=False)
        rows.append((row["author"], row["school"], bio))

    cursor.executemany(
        "INSERT IGNORE INTO authors (name, school, bio_json) VALUES (%s, %s, %s)",
        rows,
    )
    cursor.execute("SELECT id, name FROM authors")
    return {name: aid for aid, name in cursor.fetchall()}


def insert_works(cursor, df: pd.DataFrame, author_map: dict) -> dict:
    """Вставляет произведения, возвращает словарь (author, title) → work_id."""
    works = df[["author", "title"]].drop_duplicates()
    rows = [(author_map[row["author"]], row["title"]) for _, row in works.iterrows()]

    cursor.executemany(
        "INSERT IGNORE INTO works (author_id, title) VALUES (%s, %s)",
        rows,
    )
    cursor.execute("SELECT id, author_id, title FROM works")
    # строим обратный маппинг через author_id → author name
    aid_to_name = {v: k for k, v in author_map.items()}
    return {
        (aid_to_name[author_id], title): wid
        for wid, author_id, title in cursor.fetchall()
    }


def insert_sentences(cursor, df: pd.DataFrame, work_map: dict) -> int:
    """Вставляет предложения батчами, возвращает общее число вставленных строк."""
    total = 0
    batch = []

    for _, row in df.iterrows():
        work_id = work_map.get((row["author"], row["title"]))
        if work_id is None:
            continue
        nlp_json = make_nlp_json(row)
        batch.append((work_id, str(row["sentence"]), int(row["sentence_length"]), nlp_json))

        if len(batch) >= BATCH_SIZE:
            cursor.executemany(
                "INSERT INTO sentences (work_id, sentence, sentence_length, nlp_json) "
                "VALUES (%s, %s, %s, %s)",
                batch,
            )
            total += len(batch)
            batch = []
            print(f"  вставлено {total} предложений...")

    if batch:
        cursor.executemany(
            "INSERT INTO sentences (work_id, sentence, sentence_length, nlp_json) "
            "VALUES (%s, %s, %s, %s)",
            batch,
        )
        total += len(batch)

    return total


def fill_cache(cursor):
    """Заполняет MEMORY-таблицу агрегированной статистикой."""
    cursor.execute("TRUNCATE TABLE author_stats_cache")
    cursor.execute("""
        INSERT INTO author_stats_cache (author_id, author_name, school, total_sentences, avg_length)
        SELECT
            a.id,
            a.name,
            a.school,
            COUNT(s.id)             AS total_sentences,
            AVG(s.sentence_length)  AS avg_length
        FROM authors a
        JOIN works    w ON w.author_id = a.id
        JOIN sentences s ON s.work_id  = w.id
        GROUP BY a.id, a.name, a.school
    """)
    print("  MEMORY-кеш заполнен.")


def main():
    print("Загружаем CSV...")
    # Сэмпл: ~350 предложений на произведение
    df_full = load_csv(CSV_PATH)
    pieces = []
    for (_, _), grp in df_full.groupby(["author", "title"]):
        pieces.append(grp.sample(min(len(grp), 350), random_state=42))
    df = pd.concat(pieces, ignore_index=True)
    print(f"  строк для импорта: {len(df)} | авторов: {df['author'].nunique()} | произведений: {df['title'].nunique()}")

    print("Подключаемся к MySQL...")
    conn = mysql.connector.connect(**DB_CONFIG)
    conn.autocommit = False
    cursor = conn.cursor()

    try:
        print("Вставляем авторов...")
        author_map = insert_authors(cursor, df)
        print(f"  авторов в БД: {len(author_map)}")

        print("Вставляем произведения...")
        work_map = insert_works(cursor, df, author_map)
        print(f"  произведений в БД: {len(work_map)}")

        print("Вставляем предложения...")
        total = insert_sentences(cursor, df, work_map)
        print(f"  итого предложений: {total}")

        print("Заполняем кеш статистики...")
        fill_cache(cursor)

        conn.commit()
        print("\nИмпорт завершён успешно.")

    except Exception as exc:
        conn.rollback()
        print(f"Ошибка: {exc}")
        raise
    finally:
        cursor.close()
        conn.close()


if __name__ == "__main__":
    main()

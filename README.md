# Philosophy NLP Database Project

Небольшой учебный проект по базам данных. Проект создает MySQL-базу для анализа NLP-датасета философских текстов с Kaggle.

## Что внутри

- `01_schema.sql` - создание базы, таблиц, связей, индексов и кеша статистики.
- `02_import.py` - импорт данных из `phil_nlp.csv` в MySQL.
- `03_queries.sql` - аналитические SQL-запросы.
- `04_explain.sql` - примеры `EXPLAIN`, триггер и хранимая процедура.

## Датасет

Датасет `phil_nlp.csv` взят с Kaggle: https://www.kaggle.com/code/vanvalkenberg/nlp-what-the-philosopher-said

Ожидаемые колонки:

- `title`
- `author`
- `school`
- `sentence_spacy`
- `sentence`
- `sentence_length`
- `sentence_lowered`
- `tokenized_txt`
- `lemmatized_str`

## Запуск

1. Создать базу и таблицы в MySQL:

```sql
SOURCE 01_schema.sql;
```

2. Установить зависимости:

```bash
pip install -r requirements.txt
```

3. Указать пароль от MySQL через переменную окружения:

```bash
export MYSQL_PASSWORD="your_password"
```

Если пользователь MySQL не `root`, можно также указать:

```bash
export MYSQL_USER="your_user"
```

4. Запустить импорт:

```bash
python 02_import.py
```

5. Выполнить дополнительные SQL-файлы:

```sql
SOURCE 04_explain.sql;
SOURCE 03_queries.sql;
```

## Идея проекта

Основные таблицы:

- `authors` - авторы и философские школы.
- `works` - произведения авторов.
- `sentences` - предложения из произведений с NLP-разметкой в JSON.
- `author_stats_cache` - кеш статистики по авторам.

Проект показывает нормализацию, связи между таблицами, работу с JSON в MySQL, полнотекстовый поиск, оконные функции, индексы, `EXPLAIN`, триггер и хранимую процедуру.

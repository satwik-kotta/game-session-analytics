-- Cleaning, with every decision logged. One row per game in games_clean.
--
-- Two data problems found while profiling:
--  1. 945 rows repeat a game_id. 429 are exact copies; for the other 516 only start_time and end_time differ.
--  2. 46% of rows have timestamps rounded to the nearest 10,000 seconds (both times are multiples of 10^7 ms),
--     so they cannot say when in the day a game was played. They are fine for match analysis and are
--     excluded from session analysis, which needs minute level timing.
DROP TABLE IF EXISTS quality_log CASCADE;
CREATE TABLE quality_log (step serial PRIMARY KEY, check_name text, rows_affected integer, action text);

INSERT INTO quality_log (check_name, rows_affected, action)
SELECT 'raw rows', COUNT(*), 'start' FROM raw_games;

INSERT INTO quality_log (check_name, rows_affected, action)
SELECT 'rows repeating a game_id (extra copies)', COUNT(*) - COUNT(DISTINCT game_id),
       'keep one copy per game_id, preferring the copy with minute level timestamps'
FROM raw_games;

INSERT INTO quality_log (check_name, rows_affected, action)
SELECT 'games where white and black are the same account', COUNT(*) FILTER (WHERE white_id = black_id),
       'drop (cannot be two players)'
FROM (SELECT DISTINCT game_id, white_id, black_id FROM raw_games) d;

DROP TABLE IF EXISTS games_clean CASCADE;
CREATE TABLE games_clean AS
WITH flagged AS (
    SELECT g.*,
           NOT (start_time % 10000000 = 0 AND end_time % 10000000 = 0) AS ts_precise
    FROM raw_games g
), ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY game_id ORDER BY ts_precise DESC, start_time, end_time) AS rn
    FROM flagged
), kept AS (
    SELECT * FROM ranked WHERE rn = 1 AND white_id <> black_id
), parsed AS (
    SELECT k.*,
           split_part(time_increment, '+', 1)::int AS base_minutes,
           split_part(time_increment, '+', 2)::int AS increment_seconds
    FROM kept k
)
SELECT game_id, rated, turns, victory_status, winner, time_increment,
       white_id, white_rating, black_id, black_rating, opening_eco, opening_name, opening_ply,
       ts_precise,
       to_timestamp(start_time / 1000.0) AT TIME ZONE 'UTC' AS started_at,
       to_timestamp(end_time   / 1000.0) AT TIME ZONE 'UTC' AS ended_at,
       (end_time - start_time) / 60000.0                    AS duration_min,
       base_minutes, increment_seconds,
       -- Lichess speed classes use estimated duration = base + 40 x increment
       CASE WHEN base_minutes * 60 + increment_seconds * 40 < 180  THEN 'Bullet'
            WHEN base_minutes * 60 + increment_seconds * 40 < 480  THEN 'Blitz'
            WHEN base_minutes * 60 + increment_seconds * 40 < 1500 THEN 'Rapid'
            ELSE 'Classical' END                             AS speed,
       white_rating - black_rating                           AS white_rating_diff,
       ABS(white_rating - black_rating)                      AS rating_gap,
       (white_rating + black_rating) / 2.0                   AS avg_rating,
       CASE WHEN white_rating > black_rating THEN 'white'
            WHEN black_rating > white_rating THEN 'black' END AS stronger_color,
       CASE winner WHEN 'white' THEN 1.0 WHEN 'draw' THEN 0.5 ELSE 0.0 END AS white_score
FROM parsed;

ALTER TABLE games_clean ADD PRIMARY KEY (game_id);

INSERT INTO quality_log (check_name, rows_affected, action)
SELECT 'games kept', COUNT(*), 'games_clean' FROM games_clean;
INSERT INTO quality_log (check_name, rows_affected, action)
SELECT 'kept games with minute level timestamps', COUNT(*) FILTER (WHERE ts_precise),
       'used for session analysis' FROM games_clean;
INSERT INTO quality_log (check_name, rows_affected, action)
SELECT 'kept games with rounded timestamps', COUNT(*) FILTER (WHERE NOT ts_precise),
       'match analysis only' FROM games_clean;
INSERT INTO quality_log (check_name, rows_affected, action)
SELECT 'games between equally rated players', COUNT(*) FILTER (WHERE rating_gap = 0),
       'no stronger player, left out of the stronger player view' FROM games_clean;

SELECT * FROM quality_log ORDER BY step;

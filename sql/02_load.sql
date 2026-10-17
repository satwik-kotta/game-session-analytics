-- Run from the repository root so the relative path resolves.
\copy raw_games FROM 'data/chess_games.csv' WITH (FORMAT csv, HEADER true)
SELECT COUNT(*) AS raw_rows, COUNT(DISTINCT game_id) AS distinct_game_ids FROM raw_games;

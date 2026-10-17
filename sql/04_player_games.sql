-- One row per player per game (two rows per game), from each player's point of view.
DROP VIEW IF EXISTS player_games CASCADE;
CREATE VIEW player_games AS
SELECT game_id, white_id AS player, black_id AS opponent, 'white'::text AS color,
       white_rating AS rating, black_rating AS opp_rating, white_rating - black_rating AS rating_diff,
       CASE winner WHEN 'white' THEN 1.0 WHEN 'draw' THEN 0.5 ELSE 0.0 END AS score,
       rated, speed, turns, victory_status, ts_precise, started_at, ended_at, duration_min
FROM games_clean
UNION ALL
SELECT game_id, black_id, white_id, 'black',
       black_rating, white_rating, black_rating - white_rating,
       CASE winner WHEN 'black' THEN 1.0 WHEN 'draw' THEN 0.5 ELSE 0.0 END,
       rated, speed, turns, victory_status, ts_precise, started_at, ended_at, duration_min
FROM games_clean;

-- Player level facts, from games with minute level timestamps only.
DROP TABLE IF EXISTS player_activity CASCADE;
CREATE TABLE player_activity AS
SELECT player,
       COUNT(*)                                         AS games_in_sample,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY rating) AS median_rating,
       CASE WHEN percentile_cont(0.5) WITHIN GROUP (ORDER BY rating) < 1300 THEN '<1300'
            WHEN percentile_cont(0.5) WITHIN GROUP (ORDER BY rating) < 1600 THEN '1300-1599'
            WHEN percentile_cont(0.5) WITHIN GROUP (ORDER BY rating) < 1900 THEN '1600-1899'
            ELSE '1900+' END                            AS rating_band,
       COUNT(*) >= 10                                   AS active   -- 10+ games: treated as a fully observed user
FROM player_games
WHERE ts_precise
GROUP BY player;

SELECT active, COUNT(*) AS players, SUM(games_in_sample) AS player_games
FROM player_activity GROUP BY active ORDER BY active DESC;

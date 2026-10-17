-- Match level metrics, all 19,111 deduplicated games.

-- 1. Does the higher rated player win? Score of the stronger player by rating gap.
--    Expected score uses the Elo formula 1 / (1 + 10^(-gap / 400)).
WITH g AS (
    SELECT *,
           CASE WHEN rating_gap < 50  THEN '1-49'
                WHEN rating_gap < 100 THEN '50-99'
                WHEN rating_gap < 200 THEN '100-199'
                WHEN rating_gap < 400 THEN '200-399'
                ELSE '400+' END AS gap_bucket,
           CASE WHEN winner = stronger_color THEN 1.0 WHEN winner = 'draw' THEN 0.5 ELSE 0.0 END AS stronger_score
    FROM games_clean
    WHERE rating_gap > 0
)
SELECT gap_bucket,
       COUNT(*)                                                        AS games,
       ROUND(AVG(stronger_score)::numeric, 3)                          AS stronger_score,
       ROUND(AVG(1.0 / (1 + POWER(10, -rating_gap / 400.0)))::numeric, 3) AS elo_expected,
       ROUND(100.0 * AVG((winner = 'draw')::int), 1)                   AS pct_draw,
       ROUND(AVG(turns), 1)                                            AS avg_turns
FROM g
GROUP BY gap_bucket
ORDER BY MIN(rating_gap);

-- 2. How games end, by speed class, with each class's share of games and the 90th percentile length (window functions).
SELECT speed, victory_status, games,
       ROUND(100.0 * games / SUM(games) OVER (PARTITION BY speed), 1) AS pct_of_speed,
       p90_turns
FROM (
    SELECT speed, victory_status, COUNT(*) AS games,
           percentile_cont(0.9) WITHIN GROUP (ORDER BY turns) AS p90_turns
    FROM games_clean GROUP BY speed, victory_status
) s
ORDER BY speed, games DESC;

-- 3. Openings played at least 150 times: white's score and rank by popularity.
SELECT RANK() OVER (ORDER BY games DESC) AS popularity_rank, opening, games, white_score
FROM (
    SELECT split_part(opening_name, ':', 1) AS opening, COUNT(*) AS games,
           ROUND(AVG(white_score)::numeric, 3) AS white_score
    FROM games_clean GROUP BY 1 HAVING COUNT(*) >= 150
) o
ORDER BY popularity_rank LIMIT 12;

-- 4. White's edge between near equal opponents (gap under 50).
SELECT COUNT(*) AS games, ROUND(AVG(white_score)::numeric, 3) AS white_score
FROM games_clean WHERE rating_gap < 50;

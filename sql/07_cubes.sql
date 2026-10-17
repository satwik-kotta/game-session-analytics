-- Pre-aggregated cubes for the dashboard. The dashboard is a static page, so its filters
-- re-sum these cubes in the browser; every cell keeps raw counts so rates and intervals
-- are computed from counts, never averaged.

DROP TABLE IF EXISTS cube_match CASCADE;
CREATE TABLE cube_match AS
SELECT speed,
       CASE WHEN rated THEN 'Rated' ELSE 'Casual' END AS rated,
       CASE WHEN avg_rating < 1300 THEN '<1300' WHEN avg_rating < 1600 THEN '1300-1599'
            WHEN avg_rating < 1900 THEN '1600-1899' ELSE '1900+' END AS band,
       CASE WHEN rating_gap < 50  THEN '1-49'  WHEN rating_gap < 100 THEN '50-99'
            WHEN rating_gap < 200 THEN '100-199' WHEN rating_gap < 400 THEN '200-399'
            ELSE '400+' END AS gap_bucket,
       victory_status AS status,
       COUNT(*)                                                         AS games,
       COUNT(*) FILTER (WHERE winner = stronger_color)                  AS stronger_wins,
       COUNT(*) FILTER (WHERE winner = 'draw')                          AS draws,
       COUNT(*) FILTER (WHERE winner <> 'draw' AND winner <> stronger_color) AS weaker_wins,
       SUM(turns)                                                       AS turns_sum,
       SUM(1.0 / (1 + POWER(10, -rating_gap / 400.0)))                  AS expected_sum
FROM games_clean
WHERE rating_gap > 0
GROUP BY 1, 2, 3, 4, 5;

DROP TABLE IF EXISTS cube_continuation CASCADE;
CREATE TABLE cube_continuation AS
SELECT speed,
       CASE WHEN rated THEN 'Rated' ELSE 'Casual' END AS rated,
       rating_band AS band,
       CASE WHEN active THEN 'Active (10+ games)' ELSE 'Occasional' END AS tier,
       CASE WHEN rating_diff <= -50 THEN 'Underdog' WHEN rating_diff >= 50 THEN 'Favorite' ELSE 'Even' END AS matchup,
       CASE score WHEN 1 THEN 'Win' WHEN 0.5 THEN 'Draw' ELSE 'Loss' END AS result,
       COUNT(*)                                          AS games,
       COUNT(*) FILTER (WHERE continued)                 AS continued,
       SUM(next_score) FILTER (WHERE continued)          AS next_score_sum
FROM player_game_sessions
WHERE has_next
GROUP BY 1, 2, 3, 4, 5, 6;

DROP TABLE IF EXISTS cube_sessions CASCADE;
CREATE TABLE cube_sessions AS
SELECT rating_band AS band,
       CASE WHEN active THEN 'Active (10+ games)' ELSE 'Occasional' END AS tier,
       CASE WHEN games >= 10 THEN '10+' WHEN games >= 6 THEN '6-9' ELSE games::text END AS length,
       COUNT(*)           AS sessions,
       SUM(games)         AS games,
       SUM(play_minutes)  AS minutes_sum,
       SUM(points)        AS points_sum
FROM sessions
GROUP BY 1, 2, 3;

SELECT 'cube_match' AS cube, COUNT(*) AS cells, SUM(games) AS games FROM cube_match
UNION ALL SELECT 'cube_continuation', COUNT(*), SUM(games) FROM cube_continuation
UNION ALL SELECT 'cube_sessions', COUNT(*), SUM(sessions) FROM cube_sessions;

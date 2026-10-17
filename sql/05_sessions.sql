-- Sessionization with window functions: a new session starts when a player's next game begins
-- more than 30 minutes after their previous game ended (gaps and islands).
DROP TABLE IF EXISTS player_game_sessions CASCADE;
CREATE TABLE player_game_sessions AS
WITH ordered AS (
    SELECT pg.*,
           LAG(ended_at)     OVER w AS prev_ended_at,
           LEAD(started_at)  OVER w AS next_started_at,
           LEAD(score)       OVER w AS next_score,
           LEAD(rating_diff) OVER w AS next_rating_diff,
           LEAD(speed)       OVER w AS next_speed,
           LEAD(rated)       OVER w AS next_rated
    FROM player_games pg
    WHERE ts_precise
    WINDOW w AS (PARTITION BY player ORDER BY started_at, game_id)
), flagged AS (
    SELECT *, CASE WHEN prev_ended_at IS NULL OR started_at - prev_ended_at > INTERVAL '30 minutes'
                   THEN 1 ELSE 0 END AS new_session
    FROM ordered
), numbered AS (
    SELECT *, SUM(new_session) OVER (PARTITION BY player ORDER BY started_at, game_id) AS session_no
    FROM flagged
)
SELECT n.*,
       ROW_NUMBER() OVER (PARTITION BY player, session_no ORDER BY started_at, game_id) AS game_no,
       COUNT(*)     OVER (PARTITION BY player, session_no)                              AS session_games,
       next_started_at IS NOT NULL                                                       AS has_next,
       (next_started_at IS NOT NULL AND next_started_at - ended_at <= INTERVAL '30 minutes') AS continued,
       a.rating_band, a.active, a.games_in_sample
FROM numbered n
JOIN player_activity a USING (player);

DROP TABLE IF EXISTS sessions CASCADE;
CREATE TABLE sessions AS
SELECT player, session_no, rating_band, active,
       MIN(started_at)                                        AS session_start,
       MAX(ended_at)                                          AS session_end,
       COUNT(*)                                               AS games,
       SUM(duration_min)                                      AS play_minutes,
       SUM(score)                                             AS points,
       (ARRAY_AGG(score ORDER BY game_no DESC))[1]            AS last_game_score,
       (ARRAY_AGG(rating ORDER BY game_no))[1]                AS first_rating,
       (ARRAY_AGG(rating ORDER BY game_no DESC))[1]           AS last_rating
FROM player_game_sessions
GROUP BY player, session_no, rating_band, active;

-- A sanity view: how many sessions, and how long are they?
SELECT COUNT(*)                                             AS sessions,
       COUNT(DISTINCT player)                               AS players,
       ROUND(AVG(games), 2)                                 AS mean_games,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY games)   AS median_games,
       ROUND(AVG(play_minutes)::numeric, 1)                 AS mean_play_minutes,
       ROUND(100.0 * AVG((games = 1)::int), 1)              AS pct_single_game
FROM sessions;

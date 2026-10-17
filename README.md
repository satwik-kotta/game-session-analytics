# Multiplayer Game Match and Session Analytics

Do ratings predict who wins a match, and does losing make a player stop for the session? This project answers both on a public sample of 20,058 Lichess games, using PostgreSQL for the data layer, Python for the models and a static dashboard for the results.

**Dashboard:** https://satwik-kotta.github.io/game-session-analytics/dashboard/

## What the data says

| Question | Result |
|---|---|
| Does the stronger player win as often as Elo predicts? | No. They win less often at every gap, and the shortfall grows with the gap: 400+ points gives 85.0% observed against 95.3% expected (2,017 games). |
| How should the rating gap be scaled? | A fitted logistic slope of 0.672 (95% CI 0.643 to 0.702) against 1.0 for Elo, so one rating point is worth about two thirds of what Elo assumes in this sample. On a chronological 30% holdout, log loss falls from 0.637 (Elo) to 0.628 (fitted); a coin flip scores 0.693. |
| White advantage | About 22 rating points. |
| Do players quit after a loss? | Raw: 51.9% of active players' games continue after a loss against 54.5% after a win. With player fixed effects and rating gap, game number, rated and speed controls, a loss changes continuation by -2.0 points (95% CI -4.9 to +1.0). That is not distinguishable from zero. |
| Does a loss hurt the next game? | No detectable effect: next game score changes by +0.1 points (95% CI -3.4 to +3.6) after a loss, once player fixed effects are included. The raw gap (0.403 after a loss against 0.597 after a win) is mostly that weaker players lose more often. |
| How long are sessions? | 79.1% of 14,477 sessions are a single game (mean 1.43 games). Active players (10+ games in the sample) average 2.04. |

The headline is that raw differences are large and mostly vanish once each player is compared with themselves. The test `test_player_fixed_effects_remove_between_player_confounding` demonstrates this on synthetic data.

## Method

1. `sql/01` to `sql/03` load and clean the data: 945 duplicate game ids removed (the precise timestamp copy is kept), 2 self play games dropped, giving 19,111 games. Game speed follows the Lichess rule (base time plus 40 times the increment).
2. `sql/04` and `sql/05` build one row per player and game, then sessionize with window functions: a new session starts when the gap since the player's previous game ended is over 30 minutes.
3. `sql/06` compares the stronger player's score with the Elo expectation by rating gap bucket, victory status and opening.
4. `sql/07` writes small aggregate cubes. The dashboard re-sums these counts in the browser when filters change and computes Wilson intervals from the raw counts.
5. `analysis/model.py` fits the logistic calibration (70/30 split by start time) and the continuation models (linear probability model with player fixed effects and standard errors clustered by player, plus a logistic check). Sensitivity: requiring 5, 10 or 20 or more games per player gives -1.8, -2.0 and -1.8 points, all with intervals that include zero.

## Limits

- Association, not causation. Players choose when to play, and nothing here is randomized.
- Sessions need minute level timestamps. 46% of games in the source file carry timestamps rounded to the nearest 10^7 ms, so they are kept for match analysis but excluded from sessions and continuation. That leaves 10,357 games.
- The sample is not every game a player played. "Continued" means another game appears in the sample within 30 minutes, so some continuation is unseen. Each player's last game has no next game and is excluded, which limits right censoring bias but does not remove it. Active players (10+ games) are a proxy for players seen often.
- Almost all games are Rapid or Classical, so Blitz and Bullet results are not covered.

## Run it

```bash
pip install -r requirements.txt
export PGDATABASE=game          # needs a running PostgreSQL and createdb game
./run_sql.sh                    # schema, load, clean, sessions, metrics, cubes
python analysis/model.py        # writes outputs/results.json and outputs/cubes.json
python analysis/build_dashboard.py
python -m pytest
```

Data: Lichess games from TidyTuesday 2024-10-01 (`data/chess_games.csv`). Continuous integration runs the full pipeline against a PostgreSQL service.

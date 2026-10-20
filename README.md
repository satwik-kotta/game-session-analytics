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
| Does the effect at least concentrate in favourites? | No. Raw, a favourite who loses continues 6.6 points less often than one who wins (50.1% against 56.7%), while underdogs are flat (-0.2 points). With player fixed effects the three matchups are indistinguishable: Even -1.3, Favourite -2.2, Underdog -2.4 points, every interval crossing zero and the interaction nowhere near significant (p = 0.76 and 0.72). |
| How long are sessions? | 79.1% of 14,477 sessions are a single game (mean 1.43 games). Active players (10+ games in the sample) average 2.04, and 56.7% of their sessions are still a single game. |

The headline is that raw differences are large and mostly vanish once each player is compared with themselves. The test `test_player_fixed_effects_remove_between_player_confounding` demonstrates this on synthetic data.

The favourite cut is the cleanest example. "Favourites tilt, underdogs shrug" is a tidy story, the raw numbers appear to support it, and it is wrong: favourites are favourites because they are stronger players, and stronger players continue more often whatever just happened. `test_by_matchup_isolates_a_favorite_only_effect` plants exactly that effect in synthetic data and confirms the model would find it if it were there.

## What a product team should do with this

Ranked by what the evidence actually supports, not by how interesting the story is.

**1. Recalibrate the rating-to-win-probability curve. Strongest evidence, directly actionable.**
A third of games (31.8%) are played at a 200+ point gap and 10.7% at 400+, and those are exactly where the Elo curve is worst: it overstates the favourite by 6.7 points at 200-399 and 10.4 points at 400+. Refitting the slope (0.672 against Elo's 1.0) improves holdout log loss from 0.637 to 0.628 and Brier from 0.2209 to 0.2195 on 5,467 unseen games. Any system that consumes a predicted win probability - matchmaking targets, "close game" detection, post-match rating updates - is currently being handed numbers that are biased in a known direction by a known amount. This is a correction with a measured size, not a hypothesis.

**2. Do not build loss-streak protection on this evidence. A kill recommendation.**
The obvious feature here is to detect a losing player and intervene. The raw data appears to justify it. The data does not: the after-loss effect is -2.0 points with a 95% interval of -4.9 to +1.0, it is stable at -1.8 to -2.0 across minimum-activity cutoffs of 5, 10 and 20 games, it does not concentrate in favourites, and a loss has no detectable effect on how the next game goes (+0.1 points, -3.4 to +3.6). Shipping against this would be spending a team on an effect this sample cannot distinguish from zero. The honest next step is an experiment, not a feature.

**3. Treat the first-game-to-second-game step as the engagement question. Largest opportunity, least evidence.**
56.7% of active players' sessions are a single game, and 89.4% of occasional players' are. Whatever decides whether a session reaches a second game matters far more than what happens after a loss. Mechanically, moving 10% of active players' single-game sessions to two games takes games per session from 2.04 to 2.09, about 2.8% more games played; at 5% it is 1.4%. That is arithmetic on this sample, not a forecast, and nothing here identifies a cause. It sizes the prize and says where to point the first experiment.

**What would change my mind.** On (1), a holdout from a different time period or a faster time control: the sample is almost entirely Rapid and Classical, and the slope may not transfer. On (2), a randomised intervention, or an observational sample large enough to rule out an effect of about 2 points - this one cannot. On (3), any data on what players did instead of playing a second game, which this sample does not contain.

## Method

1. `sql/01` to `sql/03` load and clean the data: 945 duplicate game ids removed (the precise timestamp copy is kept), 2 self play games dropped, giving 19,111 games. Game speed follows the Lichess rule (base time plus 40 times the increment).
2. `sql/04` and `sql/05` build one row per player and game, then sessionize with window functions: a new session starts when the gap since the player's previous game ended is over 30 minutes.
3. `sql/06` compares the stronger player's score with the Elo expectation by rating gap bucket, victory status and opening.
4. `sql/07` writes small aggregate cubes. The dashboard re-sums these counts in the browser when filters change and computes Wilson intervals from the raw counts.
5. `analysis/model.py` fits the logistic calibration (70/30 split by start time) and the continuation models (linear probability model with player fixed effects and standard errors clustered by player, plus a logistic check). `by_matchup` adds a loss x matchup interaction and reports the marginal effect of a loss within each matchup. Sensitivity: requiring 5, 10 or 20 or more games per player gives -1.8, -2.0 and -1.8 points, all with intervals that include zero.

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

import os, sys
import numpy as np, pandas as pd, pytest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from analysis.model import elo_expected, calibration, after_loss, prep


def test_elo_expected_known_values():
    assert elo_expected(0) == pytest.approx(0.5)
    assert elo_expected(400) == pytest.approx(10 / 11)
    assert elo_expected(-100) + elo_expected(100) == pytest.approx(1.0)


def synthetic_games(n=6000, slope=0.5, seed=0):
    rng = np.random.default_rng(seed)
    gap = rng.normal(0, 200, n)
    p = 1 / (1 + np.exp(-slope * gap * np.log(10) / 400))
    return pd.DataFrame({"white_rating_diff": gap, "winner": np.where(rng.random(n) < p, "white", "black"),
                         "started_at": pd.date_range("2020-01-01", periods=n, freq="min")})


def test_calibration_recovers_a_known_slope():
    r = calibration(synthetic_games(slope=0.5))
    assert r["slope_ci"][0] < 0.5 < r["slope_ci"][1]
    assert r["logloss_fitted"] < r["logloss_elo"] < r["logloss_coin"] + 0.2   # fitted beats Elo when Elo is too steep


def test_calibration_split_is_chronological_and_sized():
    r = calibration(synthetic_games())
    assert r["n_train"] + r["n_test"] == r["n_decisive"]
    assert r["n_train"] == int(r["n_decisive"] * 0.7)


def synthetic_sessions(effect, n_players=150, per=40, seed=1):
    rng = np.random.default_rng(seed)
    rows = []
    for p in range(n_players):
        base = rng.uniform(0.35, 0.7)                      # player level continuation rate
        for g in range(per):
            score = rng.choice([0, 0.5, 1], p=[.45, .1, .45])
            cont = rng.random() < base + (effect if score == 0 else 0)
            rows.append(dict(player=f"p{p}", score=score, continued=cont, rating_diff=rng.normal(0, 100),
                             game_no=g % 5 + 1, rated=bool(rng.random() < .6), speed=rng.choice(["Rapid", "Classical"])))
    return prep(pd.DataFrame(rows))


def test_after_loss_model_finds_a_planted_effect():
    r = after_loss(synthetic_sessions(-0.15))
    assert r["fe_loss_ci"][1] < -0.08


def test_after_loss_model_finds_nothing_when_there_is_nothing():
    r = after_loss(synthetic_sessions(0.0))
    assert r["fe_loss_ci"][0] < 0 < r["fe_loss_ci"][1]


def test_player_fixed_effects_remove_between_player_confounding():
    # Weak players both lose more and quit more; without fixed effects losses look harmful, with them the effect is ~0.
    rng = np.random.default_rng(3)
    rows = []
    for p in range(200):
        weak = p % 2
        for g in range(40):
            u = rng.random(); lp = 0.6 if weak else 0.3
            score = 0 if u < lp else (0.5 if u < lp + 0.1 else 1)
            rows.append(dict(player=f"p{p}", score=score, continued=rng.random() < (0.35 if weak else 0.65),
                             rating_diff=rng.normal(0, 100), game_no=g % 5 + 1, rated=bool(rng.random() < .6), speed=rng.choice(["Rapid", "Classical"])))
    r = after_loss(prep(pd.DataFrame(rows)))
    assert r["rate_after_loss"] < r["rate_after_win"] - 0.05      # raw gap is large
    assert abs(r["fe_loss"]) < 0.04                                # fixed effects remove it

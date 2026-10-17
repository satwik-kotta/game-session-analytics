"""Match calibration and after-loss continuation models. Reads PostgreSQL, writes outputs/results.json and outputs/cubes.json."""
import json, os, warnings
import numpy as np, pandas as pd, psycopg2, statsmodels.api as sm, statsmodels.formula.api as smf

warnings.filterwarnings("ignore")
OUT = os.path.join(os.path.dirname(__file__), "..", "outputs")


def elo_expected(gap):
    return 1 / (1 + 10 ** (-np.asarray(gap, float) / 400))


def calibration(g):
    """Logistic fit of white winning on rating difference, 70/30 split by start time."""
    d = g[g.winner != "draw"].sort_values("started_at").copy()
    d["y"] = (d.winner == "white").astype(int)
    d["x"] = d.white_rating_diff * np.log(10) / 400
    cut = int(len(d) * 0.7)
    tr, te = d.iloc[:cut], d.iloc[cut:]
    m = sm.Logit(tr.y, sm.add_constant(tr[["x"]])).fit(disp=0)
    a, b = m.params
    p_fit = 1 / (1 + np.exp(-(a + b * te.x)))
    p_elo = elo_expected(te.white_rating_diff)
    ll = lambda p: float(-np.mean(te.y * np.log(p) + (1 - te.y) * np.log(1 - p)))
    brier = lambda p: float(np.mean((te.y - p) ** 2))
    full = sm.Logit(d.y, sm.add_constant(d[["x"]])).fit(disp=0)
    ci = full.conf_int().loc["x"].tolist()
    return {
        "n_decisive": int(len(d)), "n_train": int(len(tr)), "n_test": int(len(te)),
        "slope": float(full.params["x"]), "slope_ci": ci,
        "white_edge_points": float(full.params["const"] * 400 / (full.params["x"] * np.log(10))),
        "logloss_elo": ll(p_elo), "logloss_fitted": ll(p_fit), "logloss_coin": ll(np.full(len(te), .5)),
        "brier_elo": brier(p_elo), "brier_fitted": brier(p_fit),
    }


def prep(s):
    s = s.copy()
    s["loss"] = (s.score == 0).astype(int); s["draw"] = (s.score == .5).astype(int)
    s["cont"] = s.continued.astype(int); s["rd"] = s.rating_diff / 100
    s["lg"] = np.log(s.game_no); s["rt"] = s.rated.astype(int); s["rapid"] = (s.speed == "Rapid").astype(int)
    return s


def after_loss(s):
    f = smf.ols("cont ~ loss + draw + rd + lg + rt + rapid + C(player)", s).fit(
        cov_type="cluster", cov_kwds={"groups": pd.factorize(s.player)[0]})
    l = smf.logit("cont ~ loss + draw + rd + lg + rt + rapid", s).fit(
        disp=0, cov_type="cluster", cov_kwds={"groups": pd.factorize(s.player)[0]})
    return {"n": int(len(s)), "players": int(s.player.nunique()),
            "rate_after_win": float(s[s.score == 1].cont.mean()), "rate_after_loss": float(s[s.score == 0].cont.mean()),
            "fe_loss": float(f.params.loss), "fe_loss_ci": f.conf_int().loc["loss"].tolist(),
            "odds_ratio_loss": float(np.exp(l.params.loss)), "odds_ratio_ci": np.exp(l.conf_int().loc["loss"]).tolist()}


def next_score(s):
    a = s[s.cont == 1].copy()
    a["ns"] = a.next_score; a["nrd"] = a.next_rating_diff / 100
    a["nrt"] = a.next_rated.astype(int); a["nr"] = (a.next_speed == "Rapid").astype(int)
    f = smf.ols("ns ~ loss + draw + nrd + nrt + nr + C(player)", a).fit(
        cov_type="cluster", cov_kwds={"groups": pd.factorize(a.player)[0]})
    return {"n": int(len(a)), "raw_after_loss": float(a[a.score == 0].ns.mean()), "raw_after_win": float(a[a.score == 1].ns.mean()),
            "fe_loss": float(f.params.loss), "fe_loss_ci": f.conf_int().loc["loss"].tolist()}


def main():
    con = psycopg2.connect()
    g = pd.read_sql("select * from games_clean", con)
    s = prep(pd.read_sql("select * from player_game_sessions where has_next", con))
    res = {"calibration": calibration(g), "after_loss_active": after_loss(s[s.active]),
           "after_loss_all": after_loss(s), "next_game_score": next_score(s[s.active])}
    sens = {}
    for k in (5, 10, 20):
        c = pd.read_sql(f"select player from player_activity where games_in_sample >= {k}", con).player
        sub = s[s.player.isin(c)]
        r = after_loss(sub); sens[str(k)] = {"players": r["players"], "n": r["n"], "fe_loss": r["fe_loss"], "fe_loss_ci": r["fe_loss_ci"]}
    res["sensitivity_min_games"] = sens
    res["data"] = {k: int(v) for k, v in pd.read_sql(
        "select (select count(*) from raw_games) raw_games,(select count(*) from games_clean) games,"
        "(select count(*) from sessions) sessions,(select count(distinct player) from player_game_sessions) players,"
        "(select count(*) from player_activity where active) active_players", con).iloc[0].items()}
    cubes = {n: pd.read_sql(f"select * from {n}", con).to_dict("list") for n in ("cube_match", "cube_continuation", "cube_sessions")}
    os.makedirs(OUT, exist_ok=True)
    json.dump(res, open(os.path.join(OUT, "results.json"), "w"), indent=1)
    json.dump(cubes, open(os.path.join(OUT, "cubes.json"), "w"))
    print(json.dumps(res, indent=1))


if __name__ == "__main__":
    main()

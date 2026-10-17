"""Integration checks on the PostgreSQL layer. Skipped when no database is configured (set PGDATABASE)."""
import os, warnings, pandas as pd, pytest
warnings.filterwarnings('ignore', category=UserWarning)

psycopg2 = pytest.importorskip("psycopg2")
pytestmark = pytest.mark.skipif(not os.environ.get("PGDATABASE"), reason="no PostgreSQL database configured")


@pytest.fixture(scope="module")
def q():
    con = psycopg2.connect()
    yield lambda sql: pd.read_sql_query(sql, con)
    con.close()


def test_no_duplicate_games_and_no_self_play(q):
    assert q("select count(*)-count(distinct game_id) d from games_clean").d[0] == 0
    assert q("select count(*) c from games_clean where white_id = black_id").c[0] == 0


def test_every_game_appears_twice_in_player_games(q):
    assert q("select count(*) c from player_games").c[0] == 2 * q("select count(*) c from games_clean").c[0]


def test_sessions_partition_player_games(q):
    n = q("select count(*) c from player_game_sessions").c[0]
    s = q("select sum(games) s from sessions").s[0]
    assert n == s
    assert q("select count(*) c from player_game_sessions where game_no < 1").c[0] == 0


def test_sessions_do_not_hide_long_gaps(q):
    bad = q("""select count(*) c from (select start_time_ts - lag(end_time_ts) over (partition by player, session_no order by game_no) gap
               from (select player, session_no, game_no, started_at start_time_ts, ended_at end_time_ts from player_game_sessions) t) x
             where gap > interval '30 minutes'""").c[0]
    assert bad == 0


def test_cubes_conserve_counts(q):
    assert q("select sum(games) s from cube_match").s[0] == q("select count(*) c from games_clean where rating_gap > 0").c[0]
    assert q("select sum(sessions) s from cube_sessions").s[0] == q("select count(*) c from sessions").c[0]
    assert q("select sum(games) s from cube_continuation").s[0] == q("select count(*) c from player_game_sessions where has_next").c[0]

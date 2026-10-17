-- Raw table, same columns and order as data/chess_games.csv.
DROP TABLE IF EXISTS raw_games CASCADE;
CREATE TABLE raw_games (
    game_id         text,
    rated           boolean,
    start_time      bigint,      -- Unix time in milliseconds
    end_time        bigint,
    turns           integer,
    victory_status  text,        -- mate, resign, outoftime, draw
    winner          text,        -- white, black, draw
    time_increment  text,        -- 'minutes+seconds', e.g. 15+2
    white_id        text,
    white_rating    integer,
    black_id        text,
    black_rating    integer,
    moves           text,
    opening_eco     text,
    opening_name    text,
    opening_ply     integer
);

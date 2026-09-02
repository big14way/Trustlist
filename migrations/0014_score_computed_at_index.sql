-- The stats endpoint counts answering agents per category by filtering
-- agent_scores on computed_at. With 27 million rows and no index on that
-- column the query scanned the table on every homepage load, about four
-- seconds, against the web app's eight second fetch timeout. One busy
-- moment tipped it over and the homepage reported the API as unreachable.
create index if not exists agent_scores_computed_at_status
    on agent_scores (computed_at, status);

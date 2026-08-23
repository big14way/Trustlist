-- agent_scores is append only and versioned by computed_at, so it grows by
-- one row per agent per scoring run. Every read wants the newest row per
-- agent, which without this index means sorting millions of rows.
create index if not exists agent_scores_agent_latest
  on agent_scores (agent_id, computed_at desc);

-- The stats page counts jobs by state on every load.
create index if not exists jobs_state_chain on jobs (chain_id, state);

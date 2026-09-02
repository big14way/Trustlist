-- The newest score per agent, as a table the site can read directly.
--
-- Every listing joined agent_scores laterally to find each agent's latest
-- row: one index probe per agent, 327,000 of them, then a sort. On the
-- hosted database that took 17 seconds, past the web app's 8 second fetch
-- timeout, so the public marketplace showed "Nothing to show yet" while
-- holding thousands of live agents. The same rows here, one per agent,
-- indexed by status and rank, answer the default listing in milliseconds.
--
-- The trust engine rebuilds this after every scoring pass, the way it
-- rebuilds the probe rollups. This migration fills it once from what is
-- already scored so no deployment ever serves an empty table.
create table if not exists agent_latest (like agent_scores including defaults);
alter table agent_latest add primary key (agent_id);
create index if not exists agent_latest_status_rank
    on agent_latest (status, rank_score desc, agent_id desc);
create index if not exists agent_latest_uptime
    on agent_latest (uptime_7d desc nulls last, agent_id desc);

insert into agent_latest
select distinct on (agent_id) *
from agent_scores
order by agent_id, computed_at desc
on conflict (agent_id) do nothing;

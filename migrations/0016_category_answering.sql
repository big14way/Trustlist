-- Answering agents per category, precomputed.
--
-- The stats endpoint counted these on every request by joining the scored
-- agents to the agents table for their categories: 6,726 index lookups at
-- half a millisecond each on the hosted database, three seconds on the
-- homepage's first call. The numbers change once a scoring pass, so the
-- trust engine writes them here next to agent_latest and the endpoint reads
-- seven rows. Filled once so no deployment serves it empty.
create table if not exists category_answering (
  category text primary key,
  answering bigint not null,
  computed_at timestamptz not null default now()
);

insert into category_answering (category, answering)
select c, count(*)
from agent_latest s
join agents a on a.agent_id = s.agent_id
cross join lateral unnest(a.categories) as c
where s.status in ('live', 'flaky')
group by c
on conflict (category) do update set answering = excluded.answering, computed_at = now();

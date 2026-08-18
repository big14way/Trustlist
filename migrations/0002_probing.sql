-- M2: probe scheduling and scoring support.

-- One row per (agent, endpoint) to probe. Refreshed from agents.endpoints;
-- next_due drives the cadence: 30 minutes for service and unknown kinds,
-- daily for web endpoints on bulk hosts (metadata farms), 30 minutes for
-- web endpoints elsewhere.
create table probe_schedule (
  agent_id     numeric not null,
  endpoint_url text not null,
  kind         text not null,
  host         text,
  cadence_secs int not null default 1800,
  next_due     timestamptz not null default now(),
  primary key (agent_id, endpoint_url)
);
create index probe_schedule_due on probe_schedule (next_due);

create index probe_results_url_time on probe_results (endpoint_url, probed_at desc);

-- Status and measurement basis computed with each scoring run.
alter table agent_scores add column status text;
alter table agent_scores add column probes_7d int not null default 0;
alter table agent_scores add column min_probes int not null default 24;

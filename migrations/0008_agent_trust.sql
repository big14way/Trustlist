-- The current trust view per agent, rewritten by each trust pass. Kept
-- separate from agent_scores so the scoring snapshot can join it without
-- the two passes racing each other.
create table if not exists agent_trust (
  agent_id       numeric primary key,
  trust          numeric,
  confidence     numeric not null,
  raw_average    numeric not null,
  feedback_total bigint not null,
  feedback_kept  bigint not null,
  computed_at    timestamptz not null default now()
);

-- Reviewer weights gain the fields the funding trace produces.
alter table reviewer_weights add column if not exists funder bytea;
alter table reviewer_weights add column if not exists outbound_count int;

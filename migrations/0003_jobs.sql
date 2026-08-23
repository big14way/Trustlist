-- M3: jobs opened through our hire rail.
-- The kernel is the source of truth for job state; we mirror it so the UI
-- can render history without an archive node, and so a judge can see the
-- whole lifecycle without trusting a live RPC call.

alter table jobs add column if not exists provider bytea;
alter table jobs add column if not exists spec text;
alter table jobs add column if not exists chain_id bigint not null default 56;
alter table jobs add column if not exists rail bytea;
alter table jobs add column if not exists refunded numeric;
alter table jobs add column if not exists submitted_at timestamptz;
alter table jobs add column if not exists deliverable bytea;
alter table jobs add column if not exists kernel_status int;
alter table jobs add column if not exists last_synced_at timestamptz;

create index if not exists jobs_agent on jobs (agent_id);
create index if not exists jobs_hirer on jobs (hirer);
create index if not exists jobs_state on jobs (state);

-- Resume point for the hire rail log follower, separate from the registry
-- followers because the rail may live on a different chain during
-- development.
create table if not exists rail_state (
  rail            bytea primary key,
  chain_id        bigint not null,
  last_block      bigint not null,
  updated_at      timestamptz not null default now()
);

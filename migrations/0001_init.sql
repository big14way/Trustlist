-- Initial schema, SPEC.md Section 10 with the verified feedback event shape.
-- Addresses are stored as bytea (20 bytes) and formatted at the edge.

create table agents (
  agent_id            numeric primary key,
  owner               bytea not null,
  token_uri           text,
  card_fetched_at     timestamptz,
  card_status         text,
  card_raw            jsonb,
  name                text,
  description         text,
  categories          text[] not null default '{}',
  declared_skills     jsonb,
  endpoints           jsonb,
  trust_models        text[] not null default '{}',
  registered_block    bigint not null,
  registered_at       timestamptz not null,
  last_seen_block     bigint not null
);

-- Every probe attempt, append only. Never pruned during the competition.
create table probe_results (
  id            bigserial primary key,
  agent_id      numeric not null references agents(agent_id),
  endpoint_url  text not null,
  probed_at     timestamptz not null default now(),
  ok            boolean not null,
  http_status   int,
  latency_ms    int,
  failure_kind  text,
  body_hash     bytea
);
create index probe_results_agent_time on probe_results (agent_id, probed_at desc);

-- Raw feedback mirrored from the Reputation Registry. The on chain event
-- carries a signed int128 value with a per event decimals field, two string
-- tags, an endpoint string, a URI, and a hash. Revocations flip the flag.
create table feedback (
  id             bigserial primary key,
  agent_id       numeric not null,
  reviewer       bytea not null,
  feedback_index numeric not null,
  value          numeric not null,
  value_decimals int not null,
  tags           text[] not null default '{}',
  endpoint       text,
  uri            text,
  feedback_hash  bytea,
  revoked        boolean not null default false,
  revoked_tx     bytea,
  tx_hash        bytea not null,
  log_index      int not null,
  block_number   bigint not null,
  block_time     timestamptz not null,
  unique (tx_hash, log_index)
);
create index feedback_agent on feedback (agent_id);
create index feedback_reviewer on feedback (reviewer);

create table reviewer_weights (
  reviewer          bytea primary key,
  weight            numeric not null,
  cluster_id        bigint,
  first_funder      bytea,
  first_tx_at       timestamptz,
  external_tx_count int,
  flags             text[] not null default '{}',
  computed_at       timestamptz not null default now()
);

create table agent_scores (
  agent_id         numeric not null,
  computed_at      timestamptz not null,
  liveness         numeric not null,
  uptime_7d        numeric,
  median_latency   int,
  trust            numeric,
  trust_confidence numeric,
  raw_star_avg     numeric,
  feedback_total   int not null default 0,
  feedback_kept    int not null default 0,
  jobs_completed   int not null default 0,
  jobs_disputed    int not null default 0,
  rank_score       numeric not null,
  primary key (agent_id, computed_at)
);

create table snapshots (
  id           bigserial primary key,
  merkle_root  bytea not null,
  agent_count  int not null,
  computed_at  timestamptz not null,
  tx_hash      bytea,
  block_number bigint,
  payload_uri  text
);

create table jobs (
  job_id        numeric primary key,
  agent_id      numeric not null,
  hirer         bytea not null,
  token         bytea not null,
  budget        numeric not null,
  spec_hash     bytea,
  state         text not null,
  created_at    timestamptz not null,
  deadline      timestamptz,
  settled_at    timestamptz,
  create_tx     bytea,
  settle_tx     bytea
);

-- Indexer resume state, one row per registry contract.
create table indexer_state (
  registry        bytea primary key,
  last_block      bigint not null,
  last_block_hash bytea not null,
  updated_at      timestamptz not null default now()
);

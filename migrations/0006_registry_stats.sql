-- A single row snapshot of the registry, refreshed by the trust engine after
-- each scoring pass. Counting six million score rows and three hundred
-- thousand agents on every page load took fifty seconds; these numbers only
-- change when a scoring pass runs, so they are computed once and read cheaply.
-- computed_at is exposed so the UI can say how fresh the figures are rather
-- than implying they are live to the second.
create table if not exists registry_stats (
  id             int primary key default 1,
  registered     bigint not null,
  cards_fetched  bigint not null,
  cards_ok       bigint not null,
  with_endpoints bigint not null,
  feedback       bigint not null,
  reviewers      bigint not null,
  live           bigint not null,
  flaky          bigint not null,
  down           bigint not null,
  measuring      bigint not null,
  probes_total   bigint not null,
  computed_at    timestamptz not null default now(),
  constraint registry_stats_single_row check (id = 1)
);

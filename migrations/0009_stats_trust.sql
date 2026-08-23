-- The registry wide reputation picture, refreshed with the rest of the
-- snapshot. These are the numbers the stats page leads with, so they are
-- computed once by the engine that already has them rather than counted
-- again on every page load.
alter table registry_stats add column if not exists agents_rated bigint not null default 0;
alter table registry_stats add column if not exists agents_scored bigint not null default 0;
alter table registry_stats add column if not exists reviews_kept bigint not null default 0;
alter table registry_stats add column if not exists reviewers_independent bigint not null default 0;
alter table registry_stats add column if not exists largest_cluster_reviewers bigint not null default 0;
alter table registry_stats add column if not exists largest_cluster_reviews bigint not null default 0;

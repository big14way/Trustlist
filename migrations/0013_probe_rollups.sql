-- Pre-aggregate the probe history the site actually draws.
--
-- Everything the UI shows from probe_results is already an aggregate. The
-- probe strip collapses probes into 168 hourly buckets, and the endpoint
-- panel shows the most recent probe per endpoint plus a 7 day count. The raw
-- rows behind those answers are 2.0 million for a 7 day window, about 740 MB,
-- which does not fit the hosted database alongside everything else. Copying a
-- shorter window instead would mean the hosted strip silently showed fewer
-- than the 168 hours it claims.
--
-- These tables hold the same answers in roughly a fifth of the space, so the
-- hosted copy can serve the full 7 days and the claim stays true. The raw
-- table stays the source of truth locally and is what these are rebuilt from.

-- One row per agent per hour that had at least one probe. Counts rather than
-- an average, because an average of averages is wrong when buckets are later
-- combined, and the API needs to divide anyway.
create table if not exists probe_hourly (
  agent_id numeric not null references agents(agent_id),
  hour timestamptz not null,
  probes integer not null,
  ok_count integer not null,
  primary key (agent_id, hour)
);

-- Hours where almost every probe failed at once are our own outage, not the
-- agents' downtime, and the strip blanks them. Storing the verdict means the
-- hosted copy blanks exactly the same hours as local rather than recomputing
-- it from raw rows it no longer holds.
create table if not exists probe_observer_outage (
  hour timestamptz primary key
);

-- The endpoint panel: latest probe per endpoint, plus its 7 day totals.
-- One row per scheduled endpoint, so this is small however long we keep.
create table if not exists probe_endpoint_recent (
  agent_id numeric not null references agents(agent_id),
  endpoint_url text not null,
  probed_at timestamptz,
  ok boolean,
  http_status integer,
  latency_ms integer,
  failure_kind text,
  probes_7d bigint not null default 0,
  ok_7d bigint not null default 0,
  primary key (agent_id, endpoint_url)
);

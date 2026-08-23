-- The leaf set behind each snapshot. Kept so the API can hand out a proof
-- for any agent without rebuilding the tree, and so a reader can compare
-- what we serve against the payload we published.
create table if not exists snapshot_leaves (
  snapshot_id bigint not null references snapshots(id) on delete cascade,
  agent_id    numeric not null,
  position    int not null,
  liveness    int not null,
  trust       int not null,
  confidence  int not null,
  leaf        bytea not null,
  primary key (snapshot_id, agent_id)
);
create index if not exists snapshot_leaves_lookup on snapshot_leaves (snapshot_id, position);

-- Where the payload was written, and the root as text for easy comparison.
alter table snapshots add column if not exists root_hex text;
alter table snapshots add column if not exists published boolean not null default false;

-- The rebuildable payload: root, encoding rule, and every leaf. Stored next
-- to the root so what we serve and what we published cannot drift apart.
alter table snapshots add column if not exists payload jsonb;

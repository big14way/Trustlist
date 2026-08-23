-- Which entry in the on chain register a snapshot became. Guessing this from
-- the database id is wrong: the trust engine builds a snapshot every cycle,
-- and only some of them are ever published.
alter table snapshots add column if not exists onchain_index int;
alter table snapshots add column if not exists contract bytea;
create index if not exists snapshots_published on snapshots (published, computed_at desc);

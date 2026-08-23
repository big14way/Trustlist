-- Who paid for each reviewer's first transaction, and how much that address
-- does besides leaving feedback. Reviewer independence is the product's
-- central claim, and a shared funder is the cleanest evidence that two
-- reviewers are one operator.
create table if not exists reviewer_funding (
  reviewer       bytea primary key,
  funder         bytea,
  first_block    bigint,
  outbound_count int not null default 0,
  traced_at      timestamptz not null default now()
);
create index if not exists reviewer_funding_funder on reviewer_funding (funder);

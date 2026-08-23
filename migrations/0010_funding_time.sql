-- When the funding transfer happened, not just which block it was in. The
-- fresh_address signal compares this against a reviewer's first review, and
-- without the timestamp that rule was published but never firing.
alter table reviewer_funding add column if not exists first_funded_at timestamptz;

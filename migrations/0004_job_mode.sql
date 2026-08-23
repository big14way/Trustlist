-- Which settlement mode a job was opened under. 'direct' means the hirer
-- releases the escrow themselves and payout is same block; 'protected'
-- means the ERC-8183 router and its dispute policy decide. The difference
-- is a promise to the user, so it is stored rather than inferred.
alter table jobs add column if not exists mode text not null default 'direct';

-- Dues Ledger: database setup. Run this whole file once in the Supabase SQL editor.
-- BEFORE RUNNING: change the passcode on the line marked CHANGE THIS near the bottom.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.ledger_docs (
  col        text not null check (col in ('players','trips','payments','config')),
  id         text not null check (char_length(id) between 1 and 80),
  body       jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (col, id)
);

create table if not exists public.ledger_meta (
  k         int primary key default 1 check (k = 1),
  pass_hash text not null,
  rev       bigint not null default 0
);

-- Lock both tables. With row level security on and no policies, the public
-- anon key cannot read or write them directly. All access goes through the
-- three functions below, and each one checks the passcode first.
alter table public.ledger_docs enable row level security;
alter table public.ledger_meta enable row level security;
revoke all on public.ledger_docs from anon, authenticated;
revoke all on public.ledger_meta from anon, authenticated;

create or replace function public.ledger_check(p_code text)
returns void language plpgsql security definer
set search_path = public, extensions as $$
declare h text;
begin
  select pass_hash into h from public.ledger_meta where k = 1;
  if h is null or p_code is null or crypt(p_code, h) <> h then
    perform pg_sleep(0.5);  -- slows down guessing
    raise exception 'bad_passcode';
  end if;
end $$;

create or replace function public.ledger_get(p_code text, p_rev bigint default -1)
returns jsonb language plpgsql security definer
set search_path = public, extensions as $$
declare r bigint;
begin
  perform public.ledger_check(p_code);
  select rev into r from public.ledger_meta where k = 1;
  if r = p_rev then
    return jsonb_build_object('rev', r, 'unchanged', true);
  end if;
  return jsonb_build_object('rev', r, 'docs', coalesce(
    (select jsonb_agg(jsonb_build_object('col', col, 'id', id, 'body', body)) from public.ledger_docs),
    '[]'::jsonb));
end $$;

create or replace function public.ledger_put(p_code text, p_col text, p_id text, p_body jsonb)
returns bigint language plpgsql security definer
set search_path = public, extensions as $$
declare r bigint;
begin
  perform public.ledger_check(p_code);
  if jsonb_typeof(p_body) <> 'object' or pg_column_size(p_body) > 200000 then
    raise exception 'bad_body';
  end if;
  insert into public.ledger_docs (col, id, body) values (p_col, p_id, p_body)
  on conflict (col, id) do update set body = excluded.body, updated_at = now();
  update public.ledger_meta set rev = rev + 1 where k = 1 returning rev into r;
  return r;
end $$;

create or replace function public.ledger_del(p_code text, p_col text, p_id text)
returns bigint language plpgsql security definer
set search_path = public, extensions as $$
declare r bigint;
begin
  perform public.ledger_check(p_code);
  delete from public.ledger_docs where col = p_col and id = p_id;
  update public.ledger_meta set rev = rev + 1 where k = 1 returning rev into r;
  return r;
end $$;

revoke all on function public.ledger_check(text) from public, anon, authenticated;
revoke all on function public.ledger_get(text, bigint) from public;
revoke all on function public.ledger_put(text, text, text, jsonb) from public;
revoke all on function public.ledger_del(text, text, text) from public;
grant execute on function public.ledger_get(text, bigint) to anon, authenticated;
grant execute on function public.ledger_put(text, text, text, jsonb) to anon, authenticated;
grant execute on function public.ledger_del(text, text, text) to anon, authenticated;

-- Set the passcode. To change it later, edit and re-run just this statement.
insert into public.ledger_meta (k, pass_hash)
values (1, extensions.crypt('CHANGE-THIS-PASSCODE', extensions.gen_salt('bf')))  -- CHANGE THIS
on conflict (k) do update set pass_hash = excluded.pass_hash;

-- Starting trips, with blank expense amounts. Skipped if they already exist.
insert into public.ledger_docs (col, id, body) values
 ('trips','seattle','{"name":"Seattle","date":"","travelers":[],"expenses":[{"id":"vans","label":"Vans","amount":0},{"id":"gas","label":"Gas","amount":0},{"id":"lodging","label":"AirBnB/hotel","amount":0}]}'),
 ('trips','florida','{"name":"Florida","date":"","travelers":[],"expenses":[{"id":"flights","label":"Flights","amount":0},{"id":"vans","label":"Vans","amount":0},{"id":"gas","label":"Gas","amount":0},{"id":"lodging","label":"AirBnB/hotel","amount":0}]}'),
 ('trips','irvine','{"name":"Irvine","date":"","travelers":[],"expenses":[{"id":"flights","label":"Flights","amount":0},{"id":"vans","label":"Vans","amount":0},{"id":"gas","label":"Gas","amount":0},{"id":"lodging","label":"AirBnB/hotel","amount":0}]}')
on conflict (col, id) do nothing;

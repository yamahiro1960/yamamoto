-- Survey schema for single public-page model
-- Run this on Supabase SQL editor

create extension if not exists pgcrypto;

create table if not exists public.survey_forms (
  id bigserial primary key,
  title text not null,
  intro_text text,
  is_published boolean not null default true,
  is_deleted boolean not null default false,
  deleted_at timestamptz,
  public_token text not null unique,
  questions_json jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.survey_forms add column if not exists is_deleted boolean not null default false;
alter table public.survey_forms add column if not exists deleted_at timestamptz;

create table if not exists public.survey_responses (
  id bigserial primary key,
  form_id bigint not null references public.survey_forms(id) on delete cascade,
  respondent_name text,
  respondent_email text,
  answers_json jsonb not null default '{}'::jsonb,
  client_meta jsonb not null default '{}'::jsonb,
  submitted_at timestamptz not null default now()
);

alter table public.survey_responses add column if not exists respondent_email text;

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on table public.survey_forms to authenticated;
grant select on table public.survey_forms to anon;
grant select on table public.survey_responses to authenticated;
grant insert on table public.survey_responses to anon;
grant usage, select on sequence public.survey_forms_id_seq to authenticated;
grant usage, select on sequence public.survey_responses_id_seq to anon, authenticated;

create index if not exists idx_survey_forms_public_token on public.survey_forms(public_token);
create index if not exists idx_survey_forms_published on public.survey_forms(is_published);
create index if not exists idx_survey_forms_is_deleted on public.survey_forms(is_deleted);
create index if not exists idx_survey_responses_form_id on public.survey_responses(form_id);

create or replace function public.set_survey_forms_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_survey_forms_updated_at on public.survey_forms;
create trigger trg_survey_forms_updated_at
before update on public.survey_forms
for each row
execute function public.set_survey_forms_updated_at();

alter table public.survey_forms enable row level security;
alter table public.survey_responses enable row level security;

-- Admin policy (requires Supabase Auth login)
drop policy if exists survey_forms_admin_all on public.survey_forms;
create policy survey_forms_admin_all
on public.survey_forms
for all
to authenticated
using (true)
with check (true);

-- Public can read only published forms (for answer page)
drop policy if exists survey_forms_public_read on public.survey_forms;
create policy survey_forms_public_read
on public.survey_forms
for select
to anon
using (is_published = true and coalesce(is_deleted, false) = false);

-- Admin can read all responses
drop policy if exists survey_responses_admin_read on public.survey_responses;
create policy survey_responses_admin_read
on public.survey_responses
for select
to authenticated
using (true);

-- Public can submit responses only for published forms
drop policy if exists survey_responses_public_insert on public.survey_responses;
create policy survey_responses_public_insert
on public.survey_responses
for insert
to anon
with check (
  exists (
    select 1
    from public.survey_forms f
    where f.id = form_id
      and f.is_published = true
      and coalesce(f.is_deleted, false) = false
  )
);

-- Optional hardening: anon cannot update/delete responses
drop policy if exists survey_responses_no_anon_update on public.survey_responses;
create policy survey_responses_no_anon_update
on public.survey_responses
for update
to anon
using (false)
with check (false);

drop policy if exists survey_responses_no_anon_delete on public.survey_responses;
create policy survey_responses_no_anon_delete
on public.survey_responses
for delete
to anon
using (false);

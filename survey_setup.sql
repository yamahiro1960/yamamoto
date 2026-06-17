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
  outline_json jsonb not null default '{}'::jsonb,
  program_json jsonb not null default '[]'::jsonb,
  public_token text not null unique,
  questions_json jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.survey_forms add column if not exists is_deleted boolean not null default false;
alter table public.survey_forms add column if not exists deleted_at timestamptz;
alter table public.survey_forms add column if not exists outline_json jsonb not null default '{}'::jsonb;
alter table public.survey_forms add column if not exists program_json jsonb not null default '[]'::jsonb;

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
grant select, insert, update, delete on table public.survey_responses to authenticated;
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
to anon, authenticated
with check (
  exists (
    select 1
    from public.survey_forms f
    where f.id = form_id
      and f.is_published = true
      and coalesce(f.is_deleted, false) = false
  )
);

-- Admin can delete responses
drop policy if exists survey_responses_admin_delete on public.survey_responses;
create policy survey_responses_admin_delete
on public.survey_responses
for delete
to authenticated
using (true);

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

-- Optional seed data for quick UI verification
-- Run only when you want to create one sample form.
insert into public.survey_forms (
  title,
  intro_text,
  is_published,
  is_deleted,
  public_token,
  outline_json,
  program_json,
  questions_json
)
values (
  '駆動型ホームページ作成を内製化するための勉強会',
  '平素より弊社の活動をご支援いただき誠にありがとうございます。今回、駆動型ホームページ内製化に関する勉強会を開催いたします。',
  true,
  false,
  'event-study-20260702',
  '{"date":"2026年7月2日(木) 13:30-15:30","venue":"南国市立図書館 3F会議室","fee":"無料","target":"関係者・参加希望者のみなさま"}'::jsonb,
  '["導入背景の共有","内製化ポイント（メンテナンス）","成功事例とこれまでにできること","AIエージェント活用デモ","質疑応答と次回アクションの確認"]'::jsonb,
  '[
    {"id":"q1","label":"今回の内容は分かりやすかったですか？","description":"当てはまるものを選択してください。","type":"radio","required":true,"options":["とても分かりやすい","分かりやすい","普通","やや難しい","難しい"]},
    {"id":"q2","label":"今後取り上げてほしいテーマ","description":"自由記述でご記入ください。","type":"textarea","required":false,"options":[]}
  ]'::jsonb
)
on conflict (public_token) do update
set
  title = excluded.title,
  intro_text = excluded.intro_text,
  is_published = excluded.is_published,
  is_deleted = excluded.is_deleted,
  outline_json = excluded.outline_json,
  program_json = excluded.program_json,
  questions_json = excluded.questions_json,
  updated_at = now();

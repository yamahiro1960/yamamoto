-- ============================================================
-- 案件管理システム - Supabase テーブルセットアップ
-- Supabase 管理画面 > SQL Editor で実行してください
-- ============================================================

-- 1. cases テーブル作成
create table if not exists cases (
  id          bigint generated always as identity primary key,
  name        text        not null,
  client      text        not null,
  requested_to text       not null default '',
  assignee    text        not null default '未割当',
  status      text        not null default '新規'
                check (status in ('新規','進行中','保留','完了','キャンセル')),
  work_status text        not null default '未着手'
                check (work_status in ('未着手','進行中','完了','保留')),
  priority    text        not null default '中'
                check (priority in ('高','中','低')),
  photo_url   text        not null default '',
  attachment_url text     not null default '',
  location_address text   not null default '',
  latitude    double precision,
  longitude   double precision,
  map_url     text        not null default '',
  deadline    date,
  note        text        not null default '',
  is_deleted  boolean     not null default false,
  deleted_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table cases add column if not exists work_status text not null default '未着手';
alter table cases add column if not exists requested_to text not null default '';
alter table cases add column if not exists photo_url text not null default '';
alter table cases add column if not exists attachment_url text not null default '';
alter table cases add column if not exists location_address text not null default '';
alter table cases add column if not exists latitude double precision;
alter table cases add column if not exists longitude double precision;
alter table cases add column if not exists map_url text not null default '';
alter table cases add column if not exists is_deleted boolean not null default false;
alter table cases add column if not exists deleted_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'cases_work_status_check'
  ) then
    alter table cases
      add constraint cases_work_status_check
      check (work_status in ('未着手','進行中','完了','保留'));
  end if;
end $$;

create table if not exists case_activities (
  id           bigint generated always as identity primary key,
  case_id      bigint      not null references cases(id) on delete cascade,
  performed_on date        not null,
  title        text        not null,
  requested_to text       not null default '',
  assignee     text        not null default '',
  work_status  text        not null default '未着手'
                check (work_status in ('未着手','進行中','完了','保留')),
  photo_url    text        not null default '',
  attachment_url text      not null default '',
  detail       text        not null default '',
  author       text        not null default '未設定',
  is_deleted   boolean     not null default false,
  deleted_at   timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

alter table case_activities add column if not exists work_status text not null default '未着手';
alter table case_activities add column if not exists requested_to text not null default '';
alter table case_activities add column if not exists assignee text not null default '';
alter table case_activities add column if not exists photo_url text not null default '';
alter table case_activities add column if not exists attachment_url text not null default '';
alter table case_activities add column if not exists is_deleted boolean not null default false;
alter table case_activities add column if not exists deleted_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'case_activities_work_status_check'
  ) then
    alter table case_activities
      add constraint case_activities_work_status_check
      check (work_status in ('未着手','進行中','完了','保留'));
  end if;
end $$;

-- 2. updated_at 自動更新トリガー
create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace trigger cases_updated_at
  before update on cases
  for each row execute function set_updated_at();

create or replace trigger case_activities_updated_at
  before update on case_activities
  for each row execute function set_updated_at();

-- 3. Row Level Security を有効化
alter table cases enable row level security;
alter table case_activities enable row level security;

-- 3.2 インデックス（履歴一覧の取得を高速化）
create index if not exists idx_case_activities_case_id_performed_on
  on case_activities(case_id, performed_on desc, created_at desc);

-- 3.5 API ロール権限（RLSとは別に必要）
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on table public.cases to anon, authenticated;
grant select, insert, update, delete on table public.case_activities to anon, authenticated;
grant usage, select on sequence public.cases_id_seq to anon, authenticated;
grant usage, select on sequence public.case_activities_id_seq to anon, authenticated;

-- 3.6 写真保存用 Storage バケット
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'case-photos',
  'case-photos',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "allow_case_photos_read" on storage.objects;
create policy "allow_case_photos_read" on storage.objects
  for select
  to anon, authenticated
  using (bucket_id = 'case-photos');

drop policy if exists "allow_case_photos_insert" on storage.objects;
create policy "allow_case_photos_insert" on storage.objects
  for insert
  to anon, authenticated
  with check (bucket_id = 'case-photos');

drop policy if exists "allow_case_photos_update" on storage.objects;
create policy "allow_case_photos_update" on storage.objects
  for update
  to anon, authenticated
  using (bucket_id = 'case-photos')
  with check (bucket_id = 'case-photos');

drop policy if exists "allow_case_photos_delete" on storage.objects;
create policy "allow_case_photos_delete" on storage.objects
  for delete
  to anon, authenticated
  using (bucket_id = 'case-photos');

-- 4. ポリシー設定（一時: ログイン不要モード）
--    ログイン機能を戻すときは、限定ポリシーに再変更してください
drop policy if exists "allow_all_for_anon" on cases;
drop policy if exists "allow_target_user_read" on cases;
drop policy if exists "allow_target_user_insert" on cases;
drop policy if exists "allow_target_user_update" on cases;
drop policy if exists "allow_target_user_delete" on cases;

create policy "allow_all_for_anon" on cases
  for all
  to anon, authenticated
  using (true)
  with check (true);

drop policy if exists "allow_all_for_anon_activities" on case_activities;
create policy "allow_all_for_anon_activities" on case_activities
  for all
  to anon, authenticated
  using (true)
  with check (true);

-- 4.1 政策管理テーブル
create table if not exists policy_projects (
  id          bigint generated always as identity primary key,
  title       text        not null default '新しい政策',
  category    text        not null default 'その他',
  stage       text        not null default '構想',
  priority    text        not null default '中'
                check (priority in ('高','中','低')),
  owner       text        not null default '',
  target_date date,
  budget      bigint,
  goal        text        not null default '',
  summary     text        not null default '',
  notes       text        not null default '',
  laws        jsonb       not null default '[]'::jsonb,
  actions     jsonb       not null default '[]'::jsonb,
  people      jsonb       not null default '[]'::jsonb,
  risks       jsonb       not null default '[]'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists policy_documents (
  id          bigint generated always as identity primary key,
  policy_id   bigint      not null references policy_projects(id) on delete cascade,
  sort_order  integer     not null default 0,
  doc_type    text        not null default '法令',
  name        text        not null default '',
  url         text        not null default '',
  note        text        not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists policy_actions (
  id          bigint generated always as identity primary key,
  policy_id   bigint      not null references policy_projects(id) on delete cascade,
  sort_order  integer     not null default 0,
  task        text        not null default '',
  due         date,
  owner       text        not null default '',
  status      text        not null default '未着手'
                check (status in ('未着手','進行中','完了','保留')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists policy_people (
  id          bigint generated always as identity primary key,
  policy_id   bigint      not null references policy_projects(id) on delete cascade,
  sort_order  integer     not null default 0,
  name        text        not null default '',
  role        text        not null default '',
  contact     text        not null default '',
  influence   text        not null default '中'
                check (influence in ('高','中','低')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists policy_risks (
  id          bigint generated always as identity primary key,
  policy_id   bigint      not null references policy_projects(id) on delete cascade,
  sort_order  integer     not null default 0,
  point       text        not null default '',
  level       text        not null default '中'
                check (level in ('高','中','低')),
  response    text        not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists idx_policy_documents_policy_id on policy_documents(policy_id, sort_order);
create index if not exists idx_policy_actions_policy_id on policy_actions(policy_id, sort_order);
create index if not exists idx_policy_people_policy_id on policy_people(policy_id, sort_order);
create index if not exists idx_policy_risks_policy_id on policy_risks(policy_id, sort_order);

alter table policy_projects add column if not exists category text not null default 'その他';
alter table policy_projects add column if not exists stage text not null default '構想';
alter table policy_projects add column if not exists priority text not null default '中';
alter table policy_projects add column if not exists owner text not null default '';
alter table policy_projects add column if not exists target_date date;
alter table policy_projects add column if not exists budget bigint;
alter table policy_projects add column if not exists goal text not null default '';
alter table policy_projects add column if not exists summary text not null default '';
alter table policy_projects add column if not exists notes text not null default '';
alter table policy_projects add column if not exists laws jsonb not null default '[]'::jsonb;
alter table policy_projects add column if not exists actions jsonb not null default '[]'::jsonb;
alter table policy_projects add column if not exists people jsonb not null default '[]'::jsonb;
alter table policy_projects add column if not exists risks jsonb not null default '[]'::jsonb;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'policy_projects_priority_check'
  ) then
    alter table policy_projects
      add constraint policy_projects_priority_check
      check (priority in ('高','中','低'));
  end if;
end $$;

create or replace trigger policy_projects_updated_at
  before update on policy_projects
  for each row execute function set_updated_at();

create or replace trigger policy_documents_updated_at
  before update on policy_documents
  for each row execute function set_updated_at();

create or replace trigger policy_actions_updated_at
  before update on policy_actions
  for each row execute function set_updated_at();

create or replace trigger policy_people_updated_at
  before update on policy_people
  for each row execute function set_updated_at();

create or replace trigger policy_risks_updated_at
  before update on policy_risks
  for each row execute function set_updated_at();

alter table policy_projects enable row level security;
alter table policy_documents enable row level security;
alter table policy_actions enable row level security;
alter table policy_people enable row level security;
alter table policy_risks enable row level security;

grant select, insert, update, delete on table public.policy_projects to anon, authenticated;
grant usage, select on sequence public.policy_projects_id_seq to anon, authenticated;
grant select, insert, update, delete on table public.policy_documents to anon, authenticated;
grant select, insert, update, delete on table public.policy_actions to anon, authenticated;
grant select, insert, update, delete on table public.policy_people to anon, authenticated;
grant select, insert, update, delete on table public.policy_risks to anon, authenticated;
grant usage, select on sequence public.policy_documents_id_seq to anon, authenticated;
grant usage, select on sequence public.policy_actions_id_seq to anon, authenticated;
grant usage, select on sequence public.policy_people_id_seq to anon, authenticated;
grant usage, select on sequence public.policy_risks_id_seq to anon, authenticated;

drop policy if exists "allow_all_for_anon_policy_projects" on policy_projects;
create policy "allow_all_for_anon_policy_projects" on policy_projects
  for all
  to anon, authenticated
  using (true)
  with check (true);

drop policy if exists "allow_all_for_anon_policy_documents" on policy_documents;
create policy "allow_all_for_anon_policy_documents" on policy_documents
  for all
  to anon, authenticated
  using (true)
  with check (true);

drop policy if exists "allow_all_for_anon_policy_actions" on policy_actions;
create policy "allow_all_for_anon_policy_actions" on policy_actions
  for all
  to anon, authenticated
  using (true)
  with check (true);

drop policy if exists "allow_all_for_anon_policy_people" on policy_people;
create policy "allow_all_for_anon_policy_people" on policy_people
  for all
  to anon, authenticated
  using (true)
  with check (true);

drop policy if exists "allow_all_for_anon_policy_risks" on policy_risks;
create policy "allow_all_for_anon_policy_risks" on policy_risks
  for all
  to anon, authenticated
  using (true)
  with check (true);

-- 5. サンプルデータ
-- 必要な場合のみ、別途 insert を実行してください。

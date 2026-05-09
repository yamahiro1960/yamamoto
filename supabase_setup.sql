-- ============================================================
-- 案件管理システム - Supabase テーブルセットアップ
-- Supabase 管理画面 > SQL Editor で実行してください
-- ============================================================

-- 1. cases テーブル作成
create table if not exists cases (
  id          bigint generated always as identity primary key,
  name        text        not null,
  client      text        not null,
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
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table cases add column if not exists work_status text not null default '未着手';
alter table cases add column if not exists photo_url text not null default '';
alter table cases add column if not exists attachment_url text not null default '';
alter table cases add column if not exists location_address text not null default '';
alter table cases add column if not exists latitude double precision;
alter table cases add column if not exists longitude double precision;
alter table cases add column if not exists map_url text not null default '';

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
  work_status  text        not null default '未着手'
                check (work_status in ('未着手','進行中','完了','保留')),
  photo_url    text        not null default '',
  attachment_url text      not null default '',
  detail       text        not null default '',
  author       text        not null default '未設定',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

alter table case_activities add column if not exists work_status text not null default '未着手';
alter table case_activities add column if not exists photo_url text not null default '';
alter table case_activities add column if not exists attachment_url text not null default '';

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

-- 5. サンプルデータ
-- 必要な場合のみ、別途 insert を実行してください。

-- 回答者による回答修正機能の追加
-- 方針:
-- - 修正は edit_token を知っている本人のみ
-- - 修正回数は無制限
-- - 修正期限は「開催日の3日前 23:59:59 (JST)」まで

alter table if exists public.survey_responses
  add column if not exists edit_token text;

alter table if exists public.survey_responses
  add column if not exists edited_at timestamptz;

alter table if exists public.survey_responses
  add column if not exists edited_count integer not null default 0;

create unique index if not exists idx_survey_responses_edit_token
  on public.survey_responses(edit_token)
  where edit_token is not null;

create index if not exists idx_survey_responses_form_id
  on public.survey_responses(form_id);

create or replace function public.survey_parse_outline_date(p_text text)
returns date
language plpgsql
immutable
as $$
declare
  m text[];
begin
  if p_text is null or btrim(p_text) = '' then
    return null;
  end if;

  m := regexp_match(p_text, '(\\d{4})[年/.-](\\d{1,2})[月/.-](\\d{1,2})');
  if m is not null then
    return make_date(m[1]::int, m[2]::int, m[3]::int);
  end if;

  m := regexp_match(p_text, '(\\d{4})(\\d{2})(\\d{2})');
  if m is not null then
    return make_date(m[1]::int, m[2]::int, m[3]::int);
  end if;

  return null;
end;
$$;

create or replace function public.survey_edit_deadline(p_form_id bigint)
returns timestamptz
language plpgsql
stable
as $$
declare
  v_date date;
  v_days integer := 3;
  v_days_text text;
begin
  select public.survey_parse_outline_date(sf.outline_json ->> 'date'),
         sf.outline_json -> 'edit_policy' ->> 'days_before_event'
    into v_date, v_days_text
  from public.survey_forms sf
  where sf.id = p_form_id
  limit 1;

  if v_days_text is not null and v_days_text ~ '^-?\\d+$' then
    v_days := greatest(v_days_text::integer, 0);
  end if;

  if v_date is null then
    return null;
  end if;

  return (((v_date - v_days)::timestamp + time '23:59:59') at time zone 'Asia/Tokyo');
end;
$$;

create or replace function public.survey_edit_max_count(p_form_id bigint)
returns integer
language plpgsql
stable
as $$
declare
  v_text text;
  v_max integer := -1;
begin
  select sf.outline_json -> 'edit_policy' ->> 'max_edits'
    into v_text
  from public.survey_forms sf
  where sf.id = p_form_id
  limit 1;

  if v_text is not null and v_text ~ '^-?\\d+$' then
    v_max := v_text::integer;
  end if;

  if v_max < -1 then
    v_max := -1;
  end if;

  return v_max;
end;
$$;

create or replace function public.survey_get_response_for_edit(p_edit_token text)
returns table (
  response_id bigint,
  form_id bigint,
  respondent_name text,
  respondent_email text,
  answers_json jsonb,
  client_meta jsonb,
  can_edit boolean,
  reason text,
  deadline_at timestamptz,
  max_edits integer,
  edited_count integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deadline timestamptz;
begin
  return query
  with target as (
    select r.id, r.form_id, r.respondent_name, r.respondent_email, r.answers_json, r.client_meta,
           r.edited_count, sf.is_published, sf.is_deleted
    from public.survey_responses r
    join public.survey_forms sf on sf.id = r.form_id
    where r.edit_token = p_edit_token
    limit 1
  )
  select
    t.id,
    t.form_id,
    t.respondent_name,
    t.respondent_email,
    t.answers_json,
    t.client_meta,
    case
      when t.id is null then false
      when not t.is_published or t.is_deleted then false
      when public.survey_edit_max_count(t.form_id) = 0 then false
      when public.survey_edit_max_count(t.form_id) > -1 and t.edited_count >= public.survey_edit_max_count(t.form_id) then false
      when public.survey_edit_deadline(t.form_id) is null then false
      when now() > public.survey_edit_deadline(t.form_id) then false
      else true
    end as can_edit,
    case
      when t.id is null then '回答が見つかりません。'
      when not t.is_published or t.is_deleted then 'このアンケートは公開停止中です。'
      when public.survey_edit_max_count(t.form_id) = 0 then 'このアンケートは回答修正が無効です。'
      when public.survey_edit_max_count(t.form_id) > -1 and t.edited_count >= public.survey_edit_max_count(t.form_id) then '修正回数の上限に達しています。'
      when public.survey_edit_deadline(t.form_id) is null then '開催日が未設定のため修正できません。'
      when now() > public.survey_edit_deadline(t.form_id) then '修正期限（開催日の3日前）を過ぎています。'
      else 'ok'
    end as reason,
    public.survey_edit_deadline(t.form_id) as deadline_at,
    public.survey_edit_max_count(t.form_id) as max_edits,
    t.edited_count
  from target t;
end;
$$;

create or replace function public.survey_update_response_by_token(
  p_edit_token text,
  p_respondent_name text,
  p_respondent_email text,
  p_answers_json jsonb,
  p_client_meta jsonb
)
returns table (
  success boolean,
  message text,
  deadline_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.survey_responses%rowtype;
  v_form public.survey_forms%rowtype;
  v_deadline timestamptz;
  v_max_edits integer;
begin
  select * into v_row
  from public.survey_responses
  where edit_token = p_edit_token
  limit 1;

  if v_row.id is null then
    return query select false, '回答が見つかりません。', null::timestamptz;
    return;
  end if;

  select * into v_form from public.survey_forms where id = v_row.form_id;
  if v_form.id is null or not v_form.is_published or v_form.is_deleted then
    return query select false, 'このアンケートは公開停止中です。', null::timestamptz;
    return;
  end if;

  v_deadline := public.survey_edit_deadline(v_row.form_id);
  v_max_edits := public.survey_edit_max_count(v_row.form_id);

  if v_max_edits = 0 then
    return query select false, 'このアンケートは回答修正が無効です。', v_deadline;
    return;
  end if;

  if v_max_edits > -1 and v_row.edited_count >= v_max_edits then
    return query select false, '修正回数の上限に達しています。', v_deadline;
    return;
  end if;

  if v_deadline is null then
    return query select false, '開催日が未設定のため修正できません。', null::timestamptz;
    return;
  end if;

  if now() > v_deadline then
    return query select false, '修正期限（開催日の3日前）を過ぎています。', v_deadline;
    return;
  end if;

  update public.survey_responses
  set respondent_name = coalesce(p_respondent_name, respondent_name),
      respondent_email = coalesce(p_respondent_email, respondent_email),
      answers_json = coalesce(p_answers_json, answers_json),
      client_meta = coalesce(p_client_meta, client_meta),
        edited_count = coalesce(edited_count, 0) + 1,
      edited_at = now()
  where id = v_row.id;

  return query select true, '回答を修正しました。', v_deadline;
end;
$$;

grant execute on function public.survey_get_response_for_edit(text) to anon, authenticated;
grant execute on function public.survey_update_response_by_token(text, text, text, jsonb, jsonb) to anon, authenticated;

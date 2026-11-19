-- Rocket Rookies Zeitmessung – Supabase Einrichtung (einmalig im SQL Editor ausführen)
-- Speichert alle Daten als Sync-Datensätze. Nur angemeldete Trainer haben Zugriff.

create table if not exists public.sync_records (
  id          text primary key,              -- z. B. p:<uuid>, c:<uuid>, a:<uuid>, e:<uuid>:mi0, f:<uuid>
  kind        text not null,                 -- person | comp | part | entry | fin
  comp_id     text,                          -- Wettkampf-ID (bei Sportlern leer)
  data        jsonb not null default '{}'::jsonb,
  deleted     boolean not null default false,
  updated_at  timestamptz not null default clock_timestamp(),
  updated_by  uuid default auth.uid()
);

create index if not exists sync_records_updated_idx on public.sync_records (updated_at);
create index if not exists sync_records_kind_idx    on public.sync_records (kind);
create index if not exists sync_records_comp_idx    on public.sync_records (comp_id);

-- Zeitstempel und Bearbeiter immer vom Server setzen
create or replace function public.sync_touch() returns trigger
language plpgsql as $$
begin
  new.updated_at := clock_timestamp();
  new.updated_by := auth.uid();
  return new;
end $$;

drop trigger if exists sync_touch on public.sync_records;
create trigger sync_touch before insert or update on public.sync_records
for each row execute function public.sync_touch();

-- Zugriff nur für angemeldete Nutzer (Trainer-Konten)
alter table public.sync_records enable row level security;

drop policy if exists "team read"   on public.sync_records;
drop policy if exists "team insert" on public.sync_records;
drop policy if exists "team update" on public.sync_records;
create policy "team read"   on public.sync_records for select to authenticated using (true);
create policy "team insert" on public.sync_records for insert to authenticated with check (true);
create policy "team update" on public.sync_records for update to authenticated using (true) with check (true);
-- kein Löschen: gelöschte Einträge werden als deleted = true markiert

revoke all on public.sync_records from anon;
grant select, insert, update on public.sync_records to authenticated;

-- Serverzeit für den Uhrenabgleich der Geräte (Millisekunden)
create or replace function public.server_time() returns double precision
language sql volatile as $$ select extract(epoch from clock_timestamp()) * 1000 $$;
revoke all on function public.server_time() from public, anon;
grant execute on function public.server_time() to authenticated;

-- Lesefreundliche Ansichten (z. B. für spätere Auswertungen)
create or replace view public.v_sportler with (security_invoker = on) as
  select substr(id, 3) as id, data->>'name' as name, data->>'cls' as klasse,
         nullif(data->>'birthYear','')::int as jahrgang, updated_at
  from public.sync_records where kind = 'person' and not deleted;

create or replace view public.v_wettkaempfe with (security_invoker = on) as
  select comp_id as id, data->'settings'->>'title' as titel, data->>'type' as format,
         data->'settings'->>'date' as datum, updated_at
  from public.sync_records where kind = 'comp' and not deleted;

grant select on public.v_sportler, public.v_wettkaempfe to authenticated;

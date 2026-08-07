-- ══════════════════════════════════════════════════════════════════════════
-- Motor de protocolos de seguimiento — 2026-08-07
--
-- Por qué: hasta hoy la app registraba un set fijo de variables (tos, descanso,
-- cannabis, peso, cintura, entrenamiento, nota) en columnas de `dias`. Sumar una
-- variable nueva exigía tocar el esquema, el HTML y el bot. Este cambio mete el
-- QUÉ se mide en datos (tabla `protocolos`) y deja el DÓNDE se guarda intacto:
-- una fila por día en `dias`, como siempre.
--
-- Dos piezas:
--   1) `protocolos` — la definición de cada seguimiento (variables, fecha de
--      inicio = día 0, duración, en qué turno se pregunta cada cosa).
--   2) `dias.extra` — bolsa JSON para las variables que no tienen columna propia.
--      Las que ya la tienen (tos_am, tos_pm, descanso, cannabis, nota…) siguen
--      escribiéndose en su columna, así los gráficos y el CSV viejos no se rompen.
--
-- Idempotente: se puede correr dos veces sin efecto ni pérdida de datos.
-- ══════════════════════════════════════════════════════════════════════════

create table if not exists protocolos (
  id            text primary key,          -- slug legible: 'cannabis_cese'
  user_id       uuid        not null,
  nombre        text        not null,
  fecha_inicio  date        not null,      -- día 0 del protocolo
  dias_min      int         not null default 21,
  dias_max      int,                       -- extender = UPDATE, no deploy
  activo        boolean     not null default true,
  variables     jsonb       not null default '[]'::jsonb,
  turnos        jsonb       not null default '{"pm":"18:00"}'::jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

alter table protocolos enable row level security;

-- Mismas reglas que `dias`: cada quien ve y toca solo lo suyo.
do $$
begin
  if not exists (select 1 from pg_policies where schemaname='public'
                 and tablename='protocolos' and policyname='protocolos_sel') then
    create policy protocolos_sel on protocolos for select using (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public'
                 and tablename='protocolos' and policyname='protocolos_ins') then
    create policy protocolos_ins on protocolos for insert with check (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public'
                 and tablename='protocolos' and policyname='protocolos_upd') then
    create policy protocolos_upd on protocolos for update using (auth.uid() = user_id);
  end if;
  if not exists (select 1 from pg_policies where schemaname='public'
                 and tablename='protocolos' and policyname='protocolos_del') then
    create policy protocolos_del on protocolos for delete using (auth.uid() = user_id);
  end if;
end $$;

-- Variables sin columna propia (saliva, moco, gusto, náusea, presión arterial…).
alter table dias add column if not exists extra jsonb not null default '{}'::jsonb;

create index if not exists dias_user_fecha_idx on dias (user_id, fecha);

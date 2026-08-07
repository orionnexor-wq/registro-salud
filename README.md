# Registro de salud — app + protocolos de seguimiento

App personal de registro diario (PWA, sin build, un solo `index.html`) publicada en
GitHub Pages: **https://orionnexor-wq.github.io/registro-salud/**
Datos en Supabase (project `wafpvllhtaqfderrrwia`), login por magic link.

Desde el **7-ago-2026** el registro tiene dos puertas de entrada y una sola base:

| Pieza | Qué hace |
|---|---|
| **Bot "Salvavidas" en Telegram** (`F:\Code\bot-bari`, servicio `bot-bari` en el VPS) | Avisa a la hora que diga el protocolo, con el link y qué toca cargar. No pregunta en el chat: el registro es uno solo y vive en la app. |
| **Esta app** | Se carga TODO acá. Las variables del protocolo activo aparecen solas como tarjetas nuevas. También grafica y exporta. |

**Todo queda en el mismo registro**: una fila por día en la tabla `dias`, sin
historial partido en dos.

> El bot también sabe preguntar con botones dentro del chat (el motor está
> entero y testeado). Se activa vaciando `SALUD_LINK` en el `.env` del VPS.
> Está apagado a pedido de Mati: *"quiero que todo siga en el mismo registro"*.

---

## Qué es un "protocolo"

Un seguimiento con fecha de inicio, duración y una lista de variables. Vive en la
tabla `protocolos` como **dato**, no como código: dar de alta uno nuevo es un
INSERT, no un deploy. El bot lee de ahí qué preguntar, a qué hora y hasta cuándo;
la app lee de ahí qué graficar y desde qué día contar.

Cada variable declara:

| Campo | Para qué |
|---|---|
| `key` | nombre interno, único dentro del protocolo |
| `label` | lo que se lee en el chat |
| `tipo` | `escala` (botones numéricos) · `opciones` (botones de texto) · `bool` (sí/no) · `texto` (nota libre) |
| `min` / `max` | solo para `escala` |
| `opciones` | solo para `opciones`: `[["valor","Etiqueta"], …]` |
| `turno` | `am` o `pm` — en cuál de los dos mensajes del día se pregunta |
| `col` | **opcional.** Columna existente de `dias` donde guardarla (`tos_am`, `descanso`, `cannabis`, `peso`, `cintura`, `entrenamiento`, `nota`). Sin `col`, la variable se guarda en `dias.extra` y no hace falta migrar nada. |

Reglas que salen solas de esto:

- **Extender de 21 a 42 días** → `update protocolos set dias_max = 42 where id = '…'`. Sin tocar código.
- **Terminar un seguimiento** → `activo = false`. Deja de preguntar; los datos quedan.
- **El día 0 es `fecha_inicio`**. Todo el export trae la columna `dia` calculada desde ahí.

---

## Dar de alta un protocolo nuevo

Ejemplo real, el que sigue en la lista — **presión arterial, 7 días, dos tomas por día**:

```sql
insert into protocolos (id, user_id, nombre, fecha_inicio, dias_min, dias_max, turnos, variables)
values (
  'presion_7d',
  '71d77634-e62a-49a0-9f3a-6cc2dc73e5c5',
  'Presión arterial',
  '2026-08-11',          -- día 0
  7, 7,
  '{"am":"08:00","pm":"20:00"}'::jsonb,
  '[
    {"key":"sis_am","label":"Sistólica (mañana)","tipo":"escala","min":80,"max":200,"turno":"am"},
    {"key":"dia_am","label":"Diastólica (mañana)","tipo":"escala","min":40,"max":130,"turno":"am"},
    {"key":"pul_am","label":"Pulso (mañana)","tipo":"escala","min":40,"max":140,"turno":"am"},
    {"key":"sis_pm","label":"Sistólica (noche)","tipo":"escala","min":80,"max":200,"turno":"pm"},
    {"key":"dia_pm","label":"Diastólica (noche)","tipo":"escala","min":40,"max":130,"turno":"pm"},
    {"key":"pul_pm","label":"Pulso (noche)","tipo":"escala","min":40,"max":140,"turno":"pm"}
  ]'::jsonb
);
```

Después: `systemctl restart bot-bari` (el bot lee los horarios al arrancar).
Si el protocolo nuevo usa un turno que ya existe (08:00 / 18:00), **no hace falta
reiniciar**: el mensaje de ese turno encadena los dos protocolos en un solo flujo.

> ⚠️ Una escala de 80 a 200 son 121 botones. Para presión conviene `tipo: "texto"`
> con validación, o partir el número en decenas + unidades. Está anotado como el
> primer ajuste a hacer cuando arranque ese protocolo.

### Aviso de fecha única (sin registro diario)

Para "el día X acordate de esto y listo", el protocolo lleva `aviso` y ninguna
variable. Sale una sola vez el día `fecha_inicio` y se desactiva solo:

```sql
insert into protocolos (id, user_id, nombre, fecha_inicio, activo, variables, turnos, aviso)
values ('washout_suplementos', '71d77634-…', 'Fin de washout', '2026-09-01', true,
        '[]'::jsonb, '{}'::jsonb,
        'Terminó el washout de proteicos. Estudios a pedir: cistatina C, relación albúmina/creatinina en orina, ácido úrico, creatinina, urea.');
```

---

## Comandos del bot

| Comando | Qué hace |
|---|---|
| `/exportar` | Manda **CSV y JSON** por Telegram, uno por protocolo, con la columna `dia` |
| `/registro` | Reenvía el link del día (o abre la carga por botones si `SALUD_LINK` está vacío) |
| `/ayer` | Ídem para el día anterior |

Un aviso por turno y nada más: si no se carga, no insiste al día siguiente. Sin
rachas, sin felicitaciones, sin lecturas de ningún tipo — registra y calla.

Los días que se escaparon se cargan en la app con la flecha ‹ del encabezado.

---

## Estructura

```
registro-salud/
  index.html                      la app entera (PWA, vanilla JS)
  migrations/
    20260807_protocolos.sql       tabla protocolos + dias.extra (idempotente)
  README.md

bot-bari/                         (no está en git — deploy = scp + restart)
  salud_store.py                  puente con Supabase + lógica pura (día-desde-inicio, export)
  seguimiento.py                  flujo de botones, avisos, /exportar
  test_seguimiento.py             tests de lógica, sin red
  test_seguimiento_live.py        integración contra la base real (limpia lo que escribe)
```

Correr los tests (en el VPS):

```bash
ssh root@159.69.217.58 "cd /root/bot-bari && .venv/bin/python test_seguimiento.py && .venv/bin/python test_seguimiento_live.py"
```

## Costo

$0. Telegram gratis, Supabase en free tier, GitHub Pages gratis, y el registro no
llama a ningún modelo de IA: son botones.

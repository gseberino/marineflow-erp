-- Agenda de Produção, Fase 7, etapa 7d ("onde, quando e com o bem em que estado"), pacote P2: o feriado do município do LOCAL do serviço, ao
-- lado do calendário da HBR, nas duas fontes (aqui e em _shared/secretario/feriados.ts), com paridade dia a dia de 2026 a 2035.
-- Spec: scratchpad agenda-pesquisa/spec-fase7d.md (§5.2, §8.3 agenda_fase7d_feriados.sql, R6.2, R6.3-9, R6.11); nomes: fase7-registro.md §1
-- (7d P2); respostas do dono: fase7-padroes.md (conflito 6d do AG7-18: 20/07 passa a fechar o pátio da MP em Balneário Camboriú; 15/06
-- continua no calendário da HBR até o dono dizer).
-- Depende de 20261024160100 (agenda_feriado, _agenda_normal).
--
-- ═══ DDL — OK NOMEADO ═══ (2 funções novas, IMMUTABLE e invoker; nenhuma tabela, nenhuma função recriada, nenhum dado)
-- NÃO APLICADA. Existe para revisão e espera o OK.
--
-- POR QUE: o calendário da HBR é o de Itajaí, mas o serviço acontece noutro município: o pátio da HBR agora é na MP Motorhomes, em Balneário
-- Camboriú (AG7-18), e o feriado de lá fecha o local mesmo sendo dia útil em Itajaí. Feriado do município é fato público (§3.1 da spec), mas
-- ele não pode entrar em agenda_feriado: a sessão do retorno, o secretário e a fila leem aquele calendário, e ele continua o da HBR.
--
-- O QUE MUDA:
--   1. agenda_feriado_municipal(dia, município): o feriado do município do local, ou null. Hoje uma entrada: 20/07 em Balneário Camboriú.
--   2. agenda_feriado_do_local(dia, município): o que vale no local; o da HBR primeiro.
-- Nada chama as duas neste pacote: quem passa a ler é a máscara do local (P3), atrás de modo_local_calendario. Nenhum passo da vigia muda.
--
-- FONTES e o que fica FORA de propósito (os mesmos de feriados.ts):
--   · Balneário Camboriú, 20/07 (aniversário da cidade): Decreto 12.108/2025 de BC; proximoferiado.net/feriados/sc/balneario-camboriu.
--   · Fora: o 11/08 de SC (transferido para o domingo), Carnaval, Corpus Christi, 24/12 e 31/12 à tarde (facultativos) e o 28/05 de BC (só
--     aparece em calendário comercial).
--   · Feriados de outros municípios (Florianópolis, Navegantes, Penha, Porto Belo, Itapema, Guaratuba, Pontal do Paraná): só com fonte
--     conferida. Cada um entra nas duas fontes, com o JSON regerado (a receita está em feriados-municipais-paridade_test.ts).
--
-- DESVIO DA SPEC (a menor escolha segura; provada no F2a):
--   · a spec diz case public._agenda_normal(p_municipio); aqui é _agenda_normal(normalize(p_municipio, nfc)). _agenda_normal tira acento por
--     translate e partiria "Balneário" escrito com o acento decomposto (NFD), que normalizarMunicipio() aceita: um lado diria feriado e o
--     outro não. Em produção hoje nenhuma cidade está em NFD (wf7dd_p2_grafias: "Balneario Camboriu" em 43 clientes e "Balneário Camboriú" em
--     13 clientes e 2 marinas); é paridade, não conserto de dado.
--
-- O QUE NÃO MUDA: agenda_feriado, agenda_dia_util, agenda_somar_du, _agenda_normal, feriadoDoDia e tipoDoDia, nem de assinatura nem de sentido.
-- O motor, a vigia, o secretário, a fila e os textos, byte a byte. O JSON feriados_2026_2035.json e o C1 de agenda_fase1_base.sql, sem regerar.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase7d_feriados.sql (begin/rollback). Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261107100100
-- e, do lado do TS: deno test supabase/functions/_shared/secretario/feriados-municipais-paridade_test.ts
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase@2.111.0 db query --linked -f supabase/migrations/20261107100100_agenda_fase7d_feriados.sql
--   npx supabase@2.111.0 db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261107100100', 'agenda_fase7d_feriados');"
--
-- DESFAZER (só antes do P3, que passa a chamar):
--   drop function if exists public.agenda_feriado_do_local(date, text), public.agenda_feriado_municipal(date, text);
--
-- IDEMPOTENTE: create or replace function, comment e revoke/grant repetidos não mudam nada.

create or replace function public.agenda_feriado_municipal(p_dia date, p_municipio text)
 returns text
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
begin
  if p_dia is null then return null; end if;
  -- O mesmo mapa de FERIADOS_MUNICIPAIS (feriados.ts): município normalizado → mês × 100 + dia → nome. O nfc vem antes porque _agenda_normal
  -- não reconhece o acento decomposto.
  case public._agenda_normal(normalize(p_municipio, nfc))
    when 'balneario camboriu' then
      case extract(month from p_dia)::int * 100 + extract(day from p_dia)::int
        when 720 then return 'aniversário de Balneário Camboriú';
        else null;
      end case;
    else null;
  end case;
  return null;
end;
$function$;

comment on function public.agenda_feriado_municipal(date, text) is
  'Agenda de Produção (Fase 7d, P2): o feriado do município do LOCAL do serviço, ou null (município desconhecido, dia comum, entrada nula). Os mesmos de feriadoMunicipal() em _shared/secretario/feriados.ts; paridade 2026–2035 em supabase/tests/agenda/feriados_municipais_2026_2035.json. Fontes: Balneário Camboriú 20/07, Decreto 12.108/2025 de BC e proximoferiado.net/feriados/sc/balneario-camboriu. Fora de propósito: o 11/08 de SC (transferido para o domingo), Carnaval, Corpus Christi, 24/12 e 31/12 à tarde (facultativos) e o 28/05 de BC (só aparece em calendário comercial). Não entra em agenda_feriado: o calendário da HBR continua o de Itajaí.';

create or replace function public.agenda_feriado_do_local(p_dia date, p_municipio text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  -- O da HBR vem primeiro: vale em qualquer lugar.
  select coalesce(public.agenda_feriado(p_dia), public.agenda_feriado_municipal(p_dia, p_municipio));
$function$;

comment on function public.agenda_feriado_do_local(date, text) is
  'Agenda de Produção (Fase 7d, P2): o feriado que vale no local: agenda_feriado (o calendário da HBR) e, se não houver, agenda_feriado_municipal. Igual a feriadoDoLocal() em _shared/secretario/feriados.ts.';

revoke all on function public.agenda_feriado_municipal(date, text), public.agenda_feriado_do_local(date, text) from public, anon;
grant execute on function public.agenda_feriado_municipal(date, text), public.agenda_feriado_do_local(date, text) to authenticated, service_role;

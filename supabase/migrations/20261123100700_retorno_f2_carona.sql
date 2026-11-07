-- Retorno rápido ao cliente, F2 (P11): a carona e o meio-dia.
--
-- A carona é 1 linha no fim da resposta do assistente, no máximo a cada carona_intervalo. A da agenda tem prioridade: uma carona
-- por resposta. Vai ao histórico, e por isso só leva rótulo e hora, nunca o que o cliente escreveu.
--
-- O meio-dia das 12:30 sai só com promessa até as 14h. Com cartão vivo de outro gatilho, sai a linha so_aviso: é ela que sustenta a
-- promessa. meio_dia_ligado só vira verdadeiro com o acorde (P14), e o check retorno_config_meio_dia_urgente segura isso no banco.
--
-- A pública retorno_cartao_devido só chama a interna, para o pacote 2 poder substituir a interna sem mexer no grant.
--
-- Reverter sem deploy: update public.retorno_config set carona_ligada = false, meio_dia_ligado = false.

create or replace function public.retorno_carona(p_autor uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_cfg public.retorno_config := public._retorno_cfg();
  v_vivo jsonb;
  v_n integer;
  v_caso uuid;
  v_rotulo text;
  v_prazo text;
  v_texto text;
begin
  if v_cfg.id is null or not v_cfg.carona_ligada or v_cfg.modo = 'desligado' then
    return null;
  end if;
  if p_autor is null or p_autor is distinct from (select d.id from public._comprovante_dono() d) then
    return null;
  end if;
  if v_cfg.carona_em is not null and v_cfg.carona_em > v_agora - v_cfg.carona_intervalo then
    return null;
  end if;

  v_vivo := public.retorno_cartao_vivo(v_agora);
  if v_vivo ->> 'estado' = 'vivo' then
    v_n := jsonb_array_length(v_vivo -> 'itens');
    if v_n = 0 then
      return null;
    end if;
    v_texto := format('Retorno: cartão aberto, %s %s · *retorno*', v_n, case when v_n = 1 then 'caso' else 'casos' end);
  else
    select count(*), (array_agg(c.abertura_id))[1] into v_n, v_caso from public._retorno_cartao_casos(v_agora, null) c;
    if v_n = 0 then
      return null;
    end if;
    v_rotulo := public._retorno_rotulo(v_caso, v_agora);
    v_prazo := public._retorno_prazo_curto(v_caso, v_agora);
    v_texto := case
      when v_prazo like 'prometi até %' then
        format('Retorno: %s esperando (%s, prometido até %s) · *retorno*', v_n, v_rotulo, substr(v_prazo, char_length('prometi até ') + 1))
      else
        format('Retorno: %s esperando (%s, desde %s) · *retorno*', v_n, v_rotulo,
               (select to_char(a.aberta_em at time zone 'America/Sao_Paulo', 'HH24:MI') from public.retorno_aberturas a where a.id = v_caso))
    end;
  end if;

  update public.retorno_config set carona_em = v_agora;
  return jsonb_build_object('texto', v_texto);
end;
$$;

comment on function public.retorno_carona(uuid, timestamptz) is
  'Retorno F2 (C-CARONA): a linha de carona, ou null: chave desligada, autor que não é o dono, ninguém esperando, ou menos de carona_intervalo da última. Só rótulo e hora: vai ao histórico.';

revoke all on function public.retorno_carona(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_carona(uuid, timestamptz) to service_role;

create or replace function public._retorno_cartao_devido(p_agora timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c_fuso constant text := 'America/Sao_Paulo';
  v_cfg public.retorno_config := public._retorno_cfg();
  v_hoje date := (p_agora at time zone c_fuso)::date;
  v_hora time := (p_agora at time zone c_fuso)::time;
begin
  if v_cfg.id is null or v_cfg.modo = 'desligado' or not v_cfg.meio_dia_ligado or not v_cfg.cartao_ligado then
    return null;
  end if;
  if not public.agenda_dia_util(v_hoje) or v_hora < v_cfg.ponto_meio_dia or v_hora >= v_cfg.promessa_meio_dia then
    return null;
  end if;
  if not exists (select 1 from public.retorno_aberturas a
                  where a.prometido_fonte = 'meio_dia'
                    and (a.prometido_ate at time zone c_fuso)::date = v_hoje
                    and a.cumprida_em is null
                    and a.estado in ('aberta', 'vencida')) then
    return null;
  end if;
  if exists (select 1 from public.retorno_cartoes c where c.gatilho = 'meio_dia' and c.dia = v_hoje and c.estado <> 'falhou') then
    return null;
  end if;
  if (select count(*) from public.retorno_cartoes c where c.gatilho = 'meio_dia' and c.dia = v_hoje and c.estado = 'falhou') >= v_cfg.cartao_tentativas then
    return null;
  end if;
  return jsonb_build_object('gatilho', 'meio_dia');
end;
$$;

comment on function public._retorno_cartao_devido(timestamptz) is
  'Retorno F2 (P11.2): {"gatilho": "meio_dia"} em dia útil, entre ponto_meio_dia e promessa_meio_dia, com caso prometido para o meio-dia e sem cartão de meio-dia hoje. O pacote 2 acrescenta o acorde.';

revoke all on function public._retorno_cartao_devido(timestamptz) from public, anon, authenticated;

create or replace function public.retorno_cartao_devido(p_agora timestamptz default now())
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select public._retorno_cartao_devido(coalesce(p_agora, now()));
$$;

comment on function public.retorno_cartao_devido(timestamptz) is
  'Retorno F2 (C-DEVIDO): a pública, com grant ao service_role; só chama a interna.';

revoke all on function public.retorno_cartao_devido(timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_cartao_devido(timestamptz) to service_role;

-- A F1 com "ou há cartão devido". Fica aqui, e não na 100600: language sql valida o corpo na criação.
create or replace function public.retorno_tem_vencido(p_agora timestamptz default now())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select c.modo <> 'desligado' from public.retorno_config c where c.id), false)
     and (exists (select 1 from public.retorno_saidas s
                   where s.estado = 'agendada'
                     and s.enviar_em <= coalesce(p_agora, now())
                     and (s.processando_ate is null or s.processando_ate < coalesce(p_agora, now()))
                     and s.tipo not in ('acorde', 'cadastro_provisorio', 'fila'))
          or public._retorno_cartao_devido(coalesce(p_agora, now())) is not null);
$$;

comment on function public.retorno_tem_vencido(timestamptz) is
  'Retorno F1 e F2 (C-VENCIDO): há saída de texto agendada e vencida, fora de reserva, ou cartão devido, com o retorno ligado. O cron só chama a edge quando é verdade.';

revoke all on function public.retorno_tem_vencido(timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_tem_vencido(timestamptz) to service_role;

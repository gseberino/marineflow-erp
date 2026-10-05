-- "Deixar a IA acompanhar": pausa a rotina de hora em hora (avaliação de 04/10/2026, conclusão
-- dada ao dono em 05/10: "não vale seguir agora; desligo o que roda à toa, sem apagar nada").
--
-- O interruptor followup_missions_enabled está 'false' desde 15/09, então ai-followup-runner roda
-- 24 vezes por dia sem fazer nada. Fica pausada, não apagada: para religar o acompanhamento,
-- ligar o interruptor no painel "IA acompanhando" E reativar esta rotina
-- (select cron.alter_job(<jobid>, active := true)).

select cron.alter_job(j.jobid, active := false)
  from cron.job j
 where j.jobname = 'ai-followup-runner';

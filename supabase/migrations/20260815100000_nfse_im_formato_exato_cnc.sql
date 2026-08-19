-- [F-NFSE] IM no formato EXATO do CNC — lição do incidente E0116 (13-14/08/2026)
--
-- O matcher do Ambiente Nacional identifica o registro complementar do prestador pela
-- combinação LITERAL município + CNPJ + IM. O CNC de Itajaí guarda a IM da HBR com 15
-- posições e zeros à esquerda ("000000000352217"); qualquer outra grafia ("352217")
-- NÃO é considerada o mesmo identificador e a Sefin devolve E0116 dizendo que a IM
-- "deve ser informada" — mesmo com a tag <IM> presente na DPS.
--
-- A Contora já corrigiu o cadastro DELES (14/08, chamado respondido pelo Geovane).
-- Aqui alinhamos o NOSSO registro para as duas fontes nunca divergirem em tela,
-- diagnóstico ou payload futuro. Guarda pelo valor: só toca a linha que ainda tem a
-- grafia curta.
update public.company_fiscal_settings
   set municipal_registration = '000000000352217',
       updated_at = now()
 where regexp_replace(coalesce(municipal_registration, ''), '\D', '', 'g') = '352217';

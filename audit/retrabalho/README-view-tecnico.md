# Retrabalho — view da OS sem valores para o técnico (NOVO-006a / NOVO-020)

**Estado:** rejeitado na revisão de integração de 11/08/2026 e **removido do branch** antes do merge.
Nada foi para a `main`, nada foi aplicado no banco. O material está preservado aqui porque **o SQL é bom** —
o que quebrou foi o caminho de leitura e escrita no frontend.

## Por que foi rejeitado

Dois bloqueios encontrados pela revisão pré-merge, detalhados em `audit/novos-achados.md` → **NOVO-020**:

1. **O detalhe da OS falharia inteiro para o técnico.** `SO_DETAIL_SELECT` pede
   `payment_condition_presets(*)`, e a view não tem `payment_condition_preset_id` (é coluna de condição de
   pagamento, removida de propósito). Sem a FK, o PostgREST responde **400 PGRST200** e derruba a consulta
   toda — não só o embed. 100% das OSs, na tela de trabalho do técnico.
2. **Salvar a OS apagaria campos financeiros.** `ServiceOrderForm` semeia o formulário com
   `d.<campo> || <default>` e o Salvar envia o formulário **inteiro**. Lendo da view, o que ela não traz
   chega `undefined`, vira `0`/`''`/`3.5` no form, e o UPDATE grava isso na tabela base: `discount_amount`,
   `tax_amount`, `subcontract_cost_total`, `commission_rate`, `commission_amount`, `commissioned_user_id`,
   `payment_conditions`, `payment_condition_preset_id`, `financial_notes`, `discount_services_pct`,
   `discount_parts_pct`, `travel_cost_per_km`. Perda de dado silenciosa, a cada Salvar de técnico.

## Spec do retrabalho (o que a próxima tentativa precisa entregar)

1. **`SELECT` próprio para o técnico.** Não reaproveitar `SO_SELECT`/`SO_DETAIL_SELECT`. O select do técnico
   lista colunas nomeadas (nunca `*`) e não pede embed que dependa de coluna ausente na view — em especial
   `payment_condition_presets`.
2. **`ServiceOrderForm` para de reenviar campo que não leu.** Ou envia apenas os campos que a tela de fato
   editou (patch, não formulário inteiro), ou o técnico usa um formulário reduzido. Enquanto o Salvar mandar
   `{...form}`, qualquer fonte de dados mais estreita que a tabela vira apagador de dado.
3. **Remover o cast `as typeof OS_TABELA`.** Ele existia para o código compilar antes de a view existir, e é
   exatamente o que escondeu (1) e (2) do compilador. Ver a **regra 7** do `CLAUDE.md`, criada por causa
   deste episódio: a troca de fonte de dados de um formulário tem que FALHAR no tipo até leitura e escrita
   estarem completas.
4. **Quando a view voltar: sem `invoicing_status` e sem `payment_status`.** Decisão (b) do Gustavo, 11/08 —
   a versão rejeitada mantinha os dois, com a justificativa de que a tela usa `invoicing_status` para
   bloquear edição de OS faturada. A leitura do dono é mais estrita: também saem. Quem precisar bloquear
   edição terá que obter esse sinal por outro caminho (uma coluna derivada booleana, por exemplo
   `edicao_bloqueada`, que não revela situação financeira).
5. **`NOVO-008` continua valendo:** fechar a OS pelo lado da tabela-mãe não fecha os **itens** —
   `service_order_parts` e `service_order_services` têm `unit_price`/`total_price` e vêm por embed. Sem
   views irmãs, "o técnico não vê valores" vale só do total para cima.

## Verificação que ficou pendente (nunca foi feita)

O PostgREST infere relacionamento a partir de view pelas colunas de FK presentes. Isso **não foi provado** —
exige a migration aplicada e um JWT de técnico. Vale para `clients`, `vessels` e `marinas`.

## Arquivos preservados

| Arquivo | O que é |
|---|---|
| `view-os-sem-valores-para-tecnico.sql.proposta` | A migration como estava. **Não aplicada.** 55 colunas, `security_invoker = on`, `REVOKE` de `anon` e `PUBLIC`, `GRANT SELECT` para `authenticated`. Revisada e aprovada tecnicamente: compila em PG 17, todas as colunas existem, nenhuma de valor escapou. Ao retomar, **remover `invoicing_status` e `payment_status`** (item 4 acima) |
| `service-orders-source.ts.proposta` | O roteador por cargo + a lista das 29 colunas de valor + a chave `VIEW_TECNICO_DISPONIVEL`. A lista de colunas continua correta e é a parte mais reaproveitável |

O teste `service-orders-source.test.ts` (12 casos, lia a migration do disco e cobrava a ausência das colunas
de valor) saiu junto no rebase; está recuperável em `git show backup/session-noturno-com-view:src/lib/service-orders-source.test.ts`.

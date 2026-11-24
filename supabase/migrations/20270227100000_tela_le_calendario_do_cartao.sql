-- A tela de previsão de caixa lê o calendário das faturas do cartão (24/11/2026).
--
-- POR QUE ISTO EXISTE: desde 24/11 a fila de pagamentos do WhatsApp usa o dia em que cada cartão fecha e vence como o
-- BANCO informa (cartao_faturas_do_banco). A previsão de caixa da tela continuava deduzindo esse dia do histórico de
-- pagamentos — e errava o C6 em um mês (deduzia "vence dia 21" e jogava a fatura de novembro para dezembro; o banco diz
-- dia 25, sempre). Para a tela fazer a mesma conta do servidor ela precisa ler as mesmas faturas, e a tabela nasceu
-- fechada a tudo que não é o servidor (20270225100000).
--
-- O QUE ABRE, e só isto:
--   · leitura (SELECT) de CINCO colunas: código, conexão, fechamento, vencimento e total. O conteúdo cru do banco
--     (dados), o mínimo, os pagamentos e os encargos continuam só do servidor;
--   · para quem é administrador ou financeiro — a mesma regra de quem já lê o extrato (bank_transactions) e as
--     conferências de saldo (bank_balance_checks);
--   · nada para anon; ninguém além do servidor grava.
-- cartao_posicoes (o retrato de cada sincronização) não muda: segue só do servidor.
--
-- Sem dados. Pode rodar de novo.

grant select (bill_id, bank_connection_id, fechamento, vencimento, total)
  on public.cartao_faturas_do_banco to authenticated;

drop policy if exists "financeiro le o calendario das faturas do cartao" on public.cartao_faturas_do_banco;
create policy "financeiro le o calendario das faturas do cartao"
  on public.cartao_faturas_do_banco
  for select
  to authenticated
  using (public.is_admin_or_financial((select auth.uid())));

comment on table public.cartao_faturas_do_banco is
  'As faturas do cartão como o banco as emitiu (vencimento, total, mínimo, pagamentos, encargos). Regravada a cada sincronização. Só o servidor grava. Administrador e financeiro leem cinco colunas (código, conexão, fechamento, vencimento e total) para a previsão de caixa da tela; o resto é só do servidor.';

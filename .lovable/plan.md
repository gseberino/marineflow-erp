

## Diagnóstico do botão WhatsApp

O botão **existe** e está renderizado em `src/components/ServiceOrderForm.tsx` (linhas 508–528), aparece quando `orderData?.share_token` está preenchido. Ele monta corretamente:

- A URL pública: `${window.location.origin}/view/${orderData.share_token}`
- A mensagem com o número da OS
- O fallback para `wa.me/?text=...` quando não há telefone

### Problema raiz

A query que carrega a OS no formulário (`SO_DETAIL_SELECT` em `src/hooks/use-service-orders.ts`, linhas 14–22) traz **apenas** `clients(full_name_or_company_name)`. Os campos `phone` e `whatsapp` do cliente **nunca chegam** ao componente, então `phoneRaw` é sempre vazio e o botão sempre abre o WhatsApp Web pedindo para o usuário escolher o contato manualmente — dando a impressão de que "não funciona".

Há também um detalhe menor: a confirmação de que `share_token` está sendo retornado (vem via `*`, ok) e de que existem registros sem token (já foi feito backfill em mensagens anteriores).

## Correção planejada

**Arquivo único a alterar:** `src/hooks/use-service-orders.ts`

Expandir o relacionamento `clients` no `SO_DETAIL_SELECT` para incluir os campos de contato necessários:

```ts
const SO_DETAIL_SELECT = `
  *,
  clients!service_orders_client_id_fkey(
    full_name_or_company_name,
    phone,
    whatsapp,
    email
  ),
  vessels!service_orders_vessel_id_fkey(boat_name, manufacturer, model, current_dock_position),
  marinas!service_orders_marina_id_fkey(marina_name, latitude, longitude),
  service_order_parts(*, products(*)),
  service_order_technicians(*, app_users(*)),
  time_entries(*, app_users!time_entries_technician_user_id_fkey(*))
`;
```

Com isso, `(orderData?.clients as any)?.whatsapp || phone` em `ServiceOrderForm.tsx` finalmente resolve para o número do cliente e o botão abre o chat direto: `https://wa.me/<numero>?text=<msg>`.

## Validação pós-mudança

1. Abrir uma OS de cliente que tem `phone` ou `whatsapp` cadastrado.
2. Clicar em **WhatsApp** → deve abrir `wa.me/<DDI+DDD+numero>?text=...` já no chat correto.
3. Para cliente sem telefone, deve continuar caindo no fallback (`wa.me/?text=...`).
4. Confirmar que o link `/view/<share_token>` abre a página pública sem login.

## Observação

Não vou mexer em RLS, no `PublicServiceOrderView.tsx`, no `pdf-generator.ts`, no auth, nem em qualquer outro arquivo — a correção é cirúrgica em uma só linha de SELECT.

### Fora de escopo (sugestões para depois, se quiser)

- Garantir que o número do cliente venha com DDI (ex.: prefixar `55` quando faltar) para evitar links que abrem em região errada.
- Adicionar `service_order_services(*)` ao SELECT se quiser que o form mostre serviços já vinculados (hoje só vêm peças).


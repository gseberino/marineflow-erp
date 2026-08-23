-- Ponte entre favorecido e conta de acesso, para quem trabalha mas ainda não usa o sistema.
--
-- O CASO REAL (23/08/2026): a HBR precisa cadastrar os funcionários agora, mas eles não vão usar
-- o sistema até tudo estar pronto. Criar `app_users` para eles seria criar contas de acesso
-- ociosas — superfície de autenticação sem uso, que é dívida de segurança, não cadastro.
--
-- O lugar certo é `payees`, que já existe e já guarda nome, documento, PIX e banco. E
-- `work_profiles` já aceita favorecido como titular (`payee_id`), então o cadastro funciona hoje.
--
-- O QUE FALTAVA: quando a pessoa ganhar login, o perfil de pagamento continua apontando para o
-- favorecido (é a identidade de PAGAMENTO, e o histórico não deve mudar de dono), mas as
-- ferramentas do agente procuram o perfil por `app_user_id`. Sem uma ponte, a pessoa logaria e
-- não acharia a própria jornada.
--
-- Esta coluna é a ponte. Nasce nula e permanece nula enquanto ninguém usar o sistema.

alter table public.payees
  add column if not exists app_user_id uuid references public.app_users(id) on delete set null;

-- Uma conta por favorecido: duas pessoas não compartilham o mesmo login, e a mesma pessoa não
-- aparece duas vezes quando o agente procura de quem é a jornada.
create unique index if not exists payees_um_app_user
  on public.payees (app_user_id) where app_user_id is not null;

create index if not exists payees_por_app_user
  on public.payees (app_user_id) where app_user_id is not null;

comment on column public.payees.app_user_id is
  'Conta de acesso desta pessoa, quando ela passar a usar o sistema. Nulo = trabalha e recebe, mas nao acessa. O perfil de pagamento continua apontando para o favorecido: e a identidade de pagamento, e o historico nao muda de dono.';

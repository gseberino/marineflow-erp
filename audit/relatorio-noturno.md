# Relatório noturno — 10/08/2026

**Branch:** `session/noturno` · **Worktree:** `marineflow-erp--noturno` · **Base:** `0a4cc64` (main)

Regras desta noite (dadas pelo Gustavo): nenhum `git push`, nenhuma migration aplicada, nenhum deploy de
Edge Function. Produção não muda. Um commit por tarefa, gates locais verdes antes de cada commit. Nada de
CashForecastPanel/financeiro — aquela frente roda em outra sessão. Dúvida ou decisão de produto: registrar
aqui e pular, nunca decidir.

**Este arquivo é o estado.** Se a sessão morrer, é por ele que se retoma.

---

## Fila e situação

| # | Tarefa | Situação |
|---|---|---|
| 0 | Mover o lint do `ci.yml` para workflow próprio | ✅ concluída |
| 1 | T3.2 — preferências de PDF (decisão #4) | ✅ concluída |
| 2 | NOVO-006b — PDF de execução sem bloco financeiro | ✅ concluída |
| 3 | T3.8 — paridade i18n pt-BR × en (MF-AUD-030) | ✅ concluída (achado não reproduziu) |
| 4 | NOVO-006a — view de `service_orders` sem valores | ✅ migration escrita (NÃO aplicada) |
| 5 | Fila infinita — cobertura de teste em módulos categoria I | 🔄 em curso (1 módulo por commit) |

---

## Leia isto primeiro (revisão matinal em 8 minutos)

**Nada foi para produção.** Sem `push`, sem migration aplicada, sem deploy de Edge Function. Tudo vive em
`session/noturno`, no worktree `marineflow-erp--noturno`. As únicas conversas com o banco foram dois `SELECT`
(chaves `pdf_options_%` e as colunas de `service_orders`), nenhuma escrita.

**Gates no HEAD:** typecheck **0** · vitest **1.125** (eram 904 no começo da noite: **+221**) · deno **267** ·
build **OK**.

**Seis defeitos reais foram encontrados** — todos registrados em `audit/novos-achados.md` e **nenhum
corrigido**, conforme a regra 3. Em ordem de gravidade:

| ID | O quê | Onde dói |
|---|---|---|
| **NOVO-011** | Importação de CSV: **`1.234,56` entra como `1,23`**; e `Telefone` vazio **apaga o celular** | Carga em lote de catálogo/cadastro — erro em centenas de linhas de uma vez, já gravadas |
| **NOVO-009** | Preço de venda vira **3,6 × 10¹⁸** quando margem+imposto+comissão dão exatamente 100% | O número entra no campo de preço do produto enquanto o aviso "impossível" está na tela |
| **NOVO-010** | Deslocamento: **4 técnicos custam menos que 1**; e o botão de calcular ignora a tarifa configurada | Toda OS de campo |
| **NOVO-008** | A view do técnico fecha os valores da OS, mas os **itens** (peça/serviço) continuam com preço no mesmo embed | "O técnico não vê valores" vale do total para cima |
| **NOVO-013** | Export de CSV: coluna "Marina" repete o nome do barco; aspas mal escapadas; **injeção de fórmula** | Arquivo que sai da empresa — contador, cliente, outro sistema |
| **NOVO-012** | Captura rápida da Agenda: **"comprar 3 cabos"** vira tarefa das 03:00 sem o "3"; `30/02` vira 02/03/2027 | Toda tarefa criada pela captura rápida com número no texto |

**Duas decisões esperam por você** (não decidi nenhuma):
1. **T3.2** — o diálogo de PDF perdeu também o cache local (`localStorage`), não só a escrita em
   `app_settings`. Foi a leitura literal de "aplica só na geração corrente"; a decisão #4 falava em "override
   local por usuário". Repor são três linhas — veja a seção 1.
2. **NOVO-006a** — `invoicing_status` e `payment_status` **ficaram** na view do técnico. Não são valores, e a
   tela usa o primeiro para bloquear edição de OS faturada. Se sua leitura da decisão #3 for mais estrita, é
   apagar duas linhas.

**A única coisa pronta para aplicar:** a migration `20260811002500_view_os_sem_valores_para_tecnico.sql`. A
ordem de operações está na seção 4 e importa (**regenerar os tipos** antes de virar a chave no frontend).

**Achado que não reproduziu:** MF-AUD-030 (paridade de i18n) já estava resolvido. Os dicionários estão em
812 × 812 chaves — se você usava o "782 × 781" do relatório de auditoria para dimensionar a frente de i18n, a
base de cálculo mudou.

---

## 0 — Lint fora do CI (concluída)

**Commit:** `ci: separa o lint do CI em workflow proprio (MF-AUD-043)`

O job `lint` saiu de `.github/workflows/ci.yml` e virou `.github/workflows/lint.yml`, com os mesmos
gatilhos (push na `main`, pull_request, disparo manual), `concurrency` própria (`lint-<ref>`) e o mesmo
`continue-on-error: true`. Nenhum comportamento de execução mudou: o lint continua rodando, continua
reportando os 2.455 erros herdados e continua sem bloquear ninguém.

**O que muda é a leitura:** a run "CI" passa a conter só gates bloqueantes, então CI verde quer dizer
exatamente "typecheck, testes de frontend, testes de Edge Function e build passaram" — sem um job vermelho
ao lado que o leitor precisa aprender a ignorar. O estado do lint continua visível, na run "Lint".

**Gates:** typecheck 0 · vitest 904 · deno 267 · build OK. YAML dos dois workflows conferido por parser
(`ci.yml` → job `gates`; `lint.yml` → job `lint`).

**Para a revisão matinal:** nada verificável localmente aqui — só o GitHub diz se o workflow novo aparece.
Depois do push, conferir em Actions que passaram a existir **duas** runs por push (CI e Lint) e que a de CI
fica verde. Se a organização tiver required checks configurados apontando para o job `lint` dentro do
workflow CI, esse nome de check mudou e precisa ser reapontado — não encontrei configuração dessas no
repositório, mas ela vive no GitHub, não em arquivo.

---

## 1 — T3.2 · Preferências de PDF (MF-AUD-014, decisão #4) — concluída

**Commit:** `fix(pdf): MF-AUD-014 padrao da empresa em Settings; o dialogo nao persiste mais`

**A decisão que autorizou:** o Gustavo respondeu a #4 assim, textualmente: *"padrão da empresa em Settings;
PDFOptionsDialog para de persistir em app_settings e aplica só na geração corrente"*.

**Como ficou:**
- `Configurações › Documentos` ganhou a seção **Padrão dos PDFs** (`PdfDefaultsSection`): escolhe o documento
  (orçamento, OS, fatura) e marca o que sai por padrão. É a única tela que grava `pdf_options_<tipo>`. A rota
  `/settings` já é `roles={['admin']}`, então herda o guarda.
- `PDFOptionsDialog` não grava mais nada — nem em `app_settings`, nem no `localStorage`. Ele lê o padrão da
  empresa como estado inicial e o que for mexido vale só para o documento que está saindo.
- `resolvePdfOptions` passou a aceitar só chaves conhecidas e só valores booleanos: chave gravada com sujeira
  (string, número, array, opção que não existe mais) cai no padrão de fábrica em vez de virar um `PDFOptions`
  meio inválido. `validity`/`dueDate` são explicitamente ignorados — descrevem um documento, não um padrão.
- Novo `src/lib/pdf-options-catalog.ts`: quais toggles existem, em que documento aparecem e como se chamam.
  Existe porque a mesma lista agora é desenhada em dois lugares, e duas cópias divergiriam na primeira opção
  nova — com sintoma silencioso (um toggle que o dono não consegue configurar, ou configura e ninguém aplica).

**Interpretação que eu fiz — vale conferir:** *"aplica só na geração corrente"* me levou a remover **também** o
cache em `localStorage` (`pdf.prefs.<tipo>`), não só a escrita em `app_settings`. Mantê-lo faria o diálogo
lembrar da última escolha, que é o oposto de "só na geração corrente". Mas a decisão #4, como estava escrita no
sumário, dizia *"padrão da empresa (admin) + override local por usuário"* — se a intenção era manter o override
local, é reverter uma função de três linhas. **Não decidi por você: implementei o texto da ordem de hoje, que é
mais recente e mais específico, e estou declarando a diferença.**

**Achado que fica aberto (não corrigi, é migration):** a política de `app_settings` continua
`FOR ALL TO authenticated USING (true)` — item 4 do MF-AUD-014. A tela nova é admin-only pela rota, mas o banco
não impede um técnico de gravar a chave direto pela API. Fechar isso é DDL em produção, proibido esta noite.

**Verificação em produção (só leitura, nenhuma escrita):** consultei `app_settings` filtrando apenas
`key like 'pdf_options_%'` — as duas chaves existentes (`quote` e `service_order`) estão com **`showTerms:
true`**. Isso **descarta em definitivo** a hipótese #2 do briefing ("os termos não renderizam") como sendo
efeito do MF-AUD-014: o padrão gravado sempre mandou imprimir os termos. A causa fica sendo a do `NOVO-007`
(PDF truncado — os termos são o penúltimo bloco do documento e caíam fora da imagem capturada), corrigida no
commit imediatamente anterior a esta noite. As duas investigações convergem.

**Gates:** typecheck 0 · vitest **926** (eram 904; +22 novos) · deno 267 · build OK.

**Para a revisão matinal:**
1. Abrir `Configurações › Documentos`, conferir que a seção aparece com os valores atuais e que salvar funciona
   (é escrita em `app_settings` — não fiz, produção não foi tocada).
2. Gerar um PDF pelo diálogo desmarcando algo e conferir, na tela de padrão, que **nada mudou lá**.
3. Decidir sobre o `localStorage` (parágrafo "Interpretação" acima).
4. `showProductImages` aparece sempre na tela de padrão e só aparece no diálogo quando o documento tem peça com
   foto — foi decisão minha de desenho, está comentada no catálogo.

**Provei que o teste pega a regressão:** reintroduzi a persistência (localStorage + upsert) no diálogo e rodei —
2 dos 5 casos de `PDFOptionsDialog.no-persist.test.tsx` falharam, exatamente os dois que cobrem escrita. Depois
revertido; o arquivo no commit é o correto.

---

## 2 — NOVO-006b · Via de execução da OS (PDF sem financeiro) — concluída

**Commit:** `feat(pdf): NOVO-006b via de execucao da OS, sem valor nenhum`

**O que é:** uma opção no diálogo de PDF da **OS** — "Via de execução (sem valores)" — que gera a mesma ordem
de serviço sem nenhum número de dinheiro: sem unitário, sem subtotal, sem quadro de totais, sem condição de
pagamento, sem histórico de pagamentos, sem observações financeiras e sem dados bancários/PIX. Fica tudo que
quem executa precisa: relato do problema, levantamento técnico, serviços com quantidade, peças com SKU e
quantidade, conclusão técnica, fotos, assinaturas.

**Decisões de desenho (minhas, declaradas):**
- **Só OS, nunca orçamento.** Orçamento sem preço não é documento, é mal-entendido. A opção nem aparece para
  orçamento, e se for forçada por código o gerador a ignora.
- **Nunca é padrão da empresa.** É escolha de um documento: aparece no diálogo, não na tela de padrão, e o
  diálogo força `hideFinancials: false` ao abrir. Um padrão que apagasse valores sem ninguém pedir seria pior
  que o problema.
- **Com ela marcada, os outros toggles ficam desabilitados** — eles decidem *quais* valores aparecem, e aqui
  não aparece nenhum. Deixá-los clicáveis prometeria um efeito inexistente.
- **O nome do arquivo muda** (`OrdemServico_Via-Execucao_OS-00777_...`). As duas versões da mesma OS caem na
  mesma pasta de downloads, e a diferença entre elas é justamente o que não pode ir para a mão errada.
- **Os termos continuam saindo** se `showTerms` estiver ligado: são garantia e condições gerais, não valores.
  Se você preferir a folha de campo sem eles, é desmarcar na hora — ou me dizer, que eu inverto o padrão.

**Como o teste segura isso (16 casos):** a asserção principal não lista blocos, varre o HTML inteiro atrás de
`R$` e de **cada valor do caso em três formatações** (`1.234,56`, `1234.56`, `1234,56`). Testar bloco a bloco
deixaria passar o próximo bloco novo com dinheiro dentro. E há **contraprova**: o mesmo documento sem a opção
tem que mostrar tudo — sem isso, um gerador que devolvesse página em branco passaria em todos os outros casos.

**Gates:** typecheck 0 · vitest **943** (eram 926; +17) · deno 267 · build OK.

**Para a revisão matinal:**
1. Gerar uma via de execução de uma OS real e conferir a olho: nenhum número de dinheiro, e a faixa "Via de
   execução" no topo.
2. Conferir que a via completa continua idêntica ao que era (a contraprova cobre isso em teste, mas o
   documento renderizado só o navegador mostra).
3. Decidir sobre os termos na via de campo (parágrafo acima).
4. Esta é a metade **do documento** do NOVO-006. A metade **do banco** é a tarefa 4 (view sem colunas de
   valor): enquanto ela não for aplicada, o técnico continua vendo os valores **na tela**, mesmo podendo
   imprimir a via sem eles.

---

## 3 — T3.8 · Paridade i18n pt-BR × en (MF-AUD-030) — concluída

**Commit:** `test(i18n): MF-AUD-030 trava a paridade pt-BR x en; traduz os rotulos de PDF`

**O achado não reproduz — e isto é o principal desta tarefa.** MF-AUD-030 dizia que
`address.dontKnowCep` existia em pt-BR e faltava em en (782 × 781 chaves). **Ela está nos dois**, e o
`git log -S` mostra um único commit tocando a chave em `en.ts` (`38c1acc`, "Add address and suppliers") — ela
nunca foi removida. Ou a comparação da auditoria tinha um defeito, ou olhou outra cópia do repositório. A
contagem de hoje é **812 × 812, diferença zero**.

Como não havia o que corrigir, a entrega é a **outra metade** que a própria auditoria recomendava: travar a
paridade com teste. `src/i18n/paridade.test.ts`, 6 casos, cobre o que o compilador não cobre:
1. **chave só em pt-BR** — o tipo `TranslationKeys` é derivado de `en`, então o TS cobra pt-BR ⊇ en, mas o
   excesso só é recusado no literal de primeiro nível: uma chave nova dentro de um objeto aninhado passa;
2. **texto vazio ou só espaço** — compila liso e some da tela;
3. **placeholder** (`{cliente}`) num idioma e não no outro — a frase traduzida perde o dado;
4. **arrays descem por índice** (`agenda.monthNames.0`), então o comprimento também é comparado — uma lista de
   meses com 11 itens de um lado é o tipo de erro que só aparece em dezembro.

**Dívida que eu mesmo tinha criado, fechada junto:** cinco rótulos do diálogo de PDF viviam como string
pt-BR dentro do componente (`showCardFee`, `showBankDetails`, `showPaymentInstructions`, `showProductImages`) e
o `hideFinancials` que criei ontem à noite seria o sexto. Eles **não apareciam em varredura de i18n nenhuma**:
não faltava chave no dicionário — faltava a chave existir. Agora estão nos dois idiomas, e `i18nKey` virou
**obrigatório** no tipo do catálogo, então o compilador cobra tradução de qualquer opção nova.

**Limite declarado:** isto **não** é a frente de i18n do MF-AUD-028 (1.052 strings), que depende da decisão #9
("o inglês é requisito real de produto?") e continua intocada. Mexi só no que eu mesmo consolidei ontem.

**Gates:** typecheck 0 · vitest **951** (eram 943; +8) · deno 267 · build OK.

**Para a revisão matinal:** se você confiava no número 782 × 781 do relatório de auditoria para dimensionar a
frente de i18n, o número certo hoje é 812 chaves em cada idioma. Nada a corrigir; só a base de cálculo muda.

---

## 4 — NOVO-006a · View da OS sem colunas de valor — migration ESCRITA, **não aplicada**

**Commit:** `feat(rls): NOVO-006a view da OS sem valores para o tecnico (migration NAO aplicada)`

> **Estado: pronta para aplicar na revisão matinal, verificação pendente.** A migration existe em disco e
> está commitada; **o banco não foi tocado**. Nenhuma escrita, nenhum deploy.

**Arquivo:** `supabase/migrations/20260811002500_view_os_sem_valores_para_tecnico.sql`

**O que ela faz:** cria `public.service_orders_tecnico` — a OS **sem nenhuma coluna de valor** —, com
`security_invoker = on` (a RLS da tabela base continua valendo; a view restringe **coluna**, nunca **linha**),
`REVOKE ALL` de `PUBLIC` e de `anon` e `GRANT SELECT` para `authenticated`, tudo na mesma migration.

**As colunas são listadas uma a uma, não `SELECT *`.** Com `*`, toda coluna de valor criada no futuro entraria
sozinha e ninguém perceberia. O preço é o inverso: coluna operacional nova também não aparece até alguém
acrescentar — falha para o lado seguro, porque funcionalidade que falta se vê na hora e valor que vaza, não.

**29 colunas ficaram de fora** (valor monetário, percentual de precificação/comissão, forma e condição de
pagamento). Uma merece destaque: **`share_token` saiu** — ele abre o link público do documento, que mostra os
valores. Mantê-lo seria fechar a porta e deixar a chave na fechadura.

**Fronteira que quero que você reveja:** `invoicing_status` e `payment_status` **ficaram**. Não são valores, e
a tela usa `invoicing_status` para bloquear edição de OS faturada — sem ele o técnico editaria o que não deve.
Eles dizem "foi faturada" e "está paga", não *quanto*. Se a sua leitura da decisão #3 for mais estrita, é
apagar duas linhas da view.

**O frontend está ligado, mas com a chave desligada.** `src/lib/service-orders-source.ts` decide a fonte por
cargo e `useServiceOrders`/`useServiceOrder` já a consultam — porém `VIEW_TECNICO_DISPONIVEL = false`, então
**hoje todo mundo lê da tabela, exatamente como antes**. A chave existe porque as duas metades não sobem
juntas: a migration é commitada antes de aplicada (regra 1) e o frontend publica a cada push na main. Sem ela,
a janela entre publicar e aplicar deixaria o técnico consultando uma view inexistente — erro justamente na
tela do trabalho dele.

**Ordem de operações para ligar:**
1. aplicar a migration;
2. **regenerar `src/integrations/supabase/types.ts`** — sem isso `.from()` não conhece a view (hoje há um cast
   comentado no hook exatamente por causa disso);
3. virar `VIEW_TECNICO_DISPONIVEL` para `true`;
4. com JWT de técnico: lista e detalhe abrem, embeds de cliente/embarcação/marina vêm preenchidos, nenhum
   valor na tela. **Este é o ponto que só o ambiente real responde:** o PostgREST infere relacionamento a
   partir de view pelas colunas de FK (todas presentes), mas eu não pude provar sem aplicar.
5. conferir se alguma tela quebra por campo ausente (`grand_total` etc. virão `undefined` para técnico).

**Achado novo registrado, não corrigido — `NOVO-008`:** a view fecha a OS, mas o detalhe é lido com embed dos
itens (`service_order_parts(*, products(*))`, `service_order_services(*, services(name))`), que têm
`unit_price`/`total_price` — e `products(*)` traz preço e custo. **Enquanto isso não for fechado, "o técnico
não vê valores" vale do total para cima; quem quiser somar, soma.** O caminho são views irmãs, e é tarefa
própria.

**Teste (12 casos):** o roteamento por cargo e — a parte que interessa — a migration é **lida do disco** e
cobrada: nenhuma das 29 colunas proibidas no `SELECT`, `security_invoker` presente, `REVOKE` de anon presente,
`GRANT` para authenticated presente, sem `SELECT *`, e as colunas que a tela do técnico precisa continuam lá.
Sem ler o arquivo, a lista em código estaria sendo testada contra ela mesma. **Provei que pega a regressão:**
acrescentei `grand_total` à view e o caso falhou nomeando a coluna; revertido em seguida.

**Gates:** typecheck 0 · vitest **963** (eram 951; +12) · deno 267 · build OK.

---

## 5 — Fila infinita · Cobertura de teste em lógica crítica sem teste

Um módulo por commit, do maior risco para o menor. Critério de escolha: lógica que decide dinheiro ou
integridade de dado, que hoje não tem nenhum teste, e que dá para testar sem banco. **Evitei de propósito
tudo que é do CashForecastPanel/financeiro**, que roda em outra sessão.

### 5.1 `price-calculator.ts` — concluído, **e achou um defeito real**

**Commit:** `test(preco): cobre price-calculator e registra NOVO-009 (preco 3,6e18)`

São 50 linhas que decidem por quanto a empresa vende, e não tinham teste nenhum. A fórmula é a do Simples
Nacional — imposto e comissão saem **de dentro** do preço (`custo / (1 - margem - imposto - comissão)`), não
são somados por cima. Trocar essa divisão pela multiplicação (o erro clássico) não quebra nada, não acusa em
tela e devolve um preço plausível **e menor** do que deveria: só apareceria no fim do mês. Agora tem um caso
que compara com o número errado (140 contra 166,67) e falha se alguém inverter.

**O defeito que apareceu — `NOVO-009`, registrado e NÃO corrigido (regra 3):** quando margem + imposto +
comissão somam **exatamente 100%**, o guard `if (divisor <= 0)` deveria zerar tudo. Em ponto flutuante,
`1 - 0,6 - 0,3 - 0,1` dá `+2,78e-17` — positivo — e o guard não pega. **O preço sai 3,6 × 10¹⁸.** Pior: como
`PriceCalculator.tsx` sincroniza o preço calculado para o formulário sempre que ele é maior que zero, esse
número **entra no campo de preço do produto** enquanto o aviso de "impossível" está na tela.

E depende da combinação: 60+30+10 e 70+20+10 quebram; 50+30+20 e 40+40+20 caem certo. É exatamente o tipo de
defeito que ninguém consegue reproduzir a partir do relato. A correção é de uma linha (tolerância `1e-9` no
guard, ou calcular o divisor em pontos percentuais inteiros) e está descrita no achado.

O caso está no teste com `it.fails` — quando a correção entrar, ele passa a acusar e obriga a virar `it()`.

**Gates:** typecheck 0 · vitest **980** (eram 963; +17) · deno 267 · build OK.

### 5.2 `displacement.ts` — concluído, **e achou outro**

**Commit:** `test(deslocamento): cobre displacement e registra NOVO-010`

Deslocamento é dinheiro em toda OS de campo, e a conta multiplica três partes (km, hora de equipe,
multiplicador de urgência/fim de semana). Erro aqui não aparece como erro — aparece como OS que fechou por
menos do que custou. 14 casos cobrindo as três partes, os multiplicadores, o fallback de configuração
inválida (um `travel_km_rate` vazio faria toda viagem sair de graça se o código aceitasse) e arredondamento.

**`NOVO-010`, registrado e não corrigido — três coisas, a primeira é a que dói:**

1. **Com 4 técnicos, a hora cai para R$ 90.** A tabela vai até 3 (`{1: 90, 2: 170, 3: 250}`) e a busca é
   `hourly[n] || hourly[1]`. Quatro técnicos custam **menos que um** — e o número de técnicos é campo livre
   na tela. Com 0 ou negativo, idem. Corrigir é escolher a regra comercial (usar a maior faixa? tarifa por
   técnico adicional?), por isso não decidi.
2. **`calculateDisplacement` ignora as tarifas configuradas** — chama o cálculo sem passar `rates`, então usa
   os padrões de fábrica, e devolve `cost_per_km: 1.10` fixo em código. Hoje padrão e configuração coincidem
   em 1,10 e ninguém percebe; **no dia em que você mudar a tarifa por km na tela de configurações, o botão de
   calcular deslocamento continuará cobrando 1,10.**
3. **Duas chaves para a mesma ideia em produção:** `travel_km_rate = 1,10` (a que o código lê) e
   `travel_cost_per_km = 3,50` (que ninguém lê) — e a coluna `travel_cost_per_km` da OS tem default 3,5 no
   formulário. O campo "custo por km" gravado na OS pode dizer 3,50 enquanto o total foi calculado a 1,10.

**Gates:** typecheck 0 · vitest **994** (eram 980; +14) · deno 267 · build OK.

### 5.3 `document-hash.ts` — concluído

**Commit:** `test(assinatura): cobre o hash do documento e amarra ao trigger do banco`

Este hash congela o conteúdo da OS no instante em que o cliente assina e vai para
`signed_document_hash`. É a peça que responde "o cliente assinou **isto**" quando alguém contesta — e falha
de dois jeitos silenciosos: deixando de mudar quando o documento muda (alteração posterior passa por
assinada) ou mudando quando nada mudou (assinatura boa vira suspeita). 30 casos cobrem os dois lados:
determinismo, ordem dos itens indiferente, `null`/`""`/ausente equivalentes, diferença abaixo de um centavo
ignorada, espaço nos termos ignorado — e, do outro lado, centavo a mais no total, quantidade, preço unitário,
item acrescentado, item removido, item renomeado e condição de pagamento, todos mudando o hash.

**O caso que mais vale:** o teste **lê a migration do trigger** `detect_so_change_after_signature` e, para
cada campo que o banco vigia com `IS DISTINCT FROM`, verifica que mudá-lo muda o hash. Os dois foram escritos
juntos em abril e nada garantia que continuassem juntos: se alguém acrescentar um campo ao trigger e esquecer
do hash, o banco passa a pedir re-assinatura de uma alteração que o documento assinado não registra — a prova
fica incompleta exatamente no caso em que ela é necessária. Hoje os 14 campos batem.

**Provei que pega a regressão:** acrescentei `internal_notes` ao trigger e o caso falhou dizendo
"internal_notes é vigiado pelo trigger mas não entra no hash". Migration restaurada em seguida.

**Gates:** typecheck 0 · vitest **1.024** (eram 994; +30) · deno 267 · build OK.

### 5.4 `nfe-xml-parser.ts` — concluído

**Commit:** `test(fiscal): cobre o parser de XML de NF-e (venda e devolucao)`

244 linhas sem teste que alimentam duas telas onde errar custa: duplicar uma nota de venda e montar a
**devolução ao fornecedor** — que precisa espelhar exatamente o que o fornecedor destacou, item a item, senão
o crédito dele não fecha. O parse é por expressão regular, não por parser de XML, o que torna dois erros
fáceis e invisíveis; os dois ganharam caso próprio:

1. **`vBC` existe no ICMS e no IPI.** Ler do `<det>` inteiro pega o primeiro (o do ICMS) e a base do IPI sai
   errada na devolução. O XML de teste usa 750 no ICMS e 800 no IPI de propósito — se alguém tirar o recorte
   por grupo, o caso acusa.
2. **A data de emissão não pode virar `Date`.** `dhEmi` de 11/09 às 23:30 com fuso −03:00 é 12/09 em UTC:
   converter devolveria o **dia seguinte** na nota de devolução. O parser corta os 10 primeiros caracteres, e
   agora existe um teste para que ninguém "melhore" isso.

Outros 20 casos: recusa de arquivo que não é NF-e, chave de acesso pelo `Id` e pelo `<chNFe>` do protocolo,
emitente ≠ destinatário (a devolução inverte os dois), entidades HTML decodificadas, CPF quando é pessoa
física, ICMS do Simples (`CSOSN`) lido igual, e imposto ausente vindo como `undefined` em vez de `0` — zero é
uma afirmação ("o fornecedor destacou zero"), `undefined` é silêncio, e a devolução precisa da diferença.

**Gates:** typecheck 0 · vitest **1.046** (eram 1.024; +22) · deno 267 · build OK.

### 5.5 `import-detector.ts` — concluído, **e achou o mais grave da noite**

**Commit:** `test(import): cobre o importador de CSV e registra NOVO-011`

É por aqui que entra catálogo inteiro vindo de outro ERP. 25 casos cobrindo separador, aspas, CRLF, linhas
irregulares, detecção de formato, contagem de registros e conversão de cada tipo de campo.

**`NOVO-011`, registrado e não corrigido — duas coisas, e a primeira é P1:**

1. **Preço com separador de milhar é destruído: `1.234,56` entra como `1,23`.** A conversão é
   `parseFloat(str.replace(',', '.'))` — `replace` com string troca **só a primeira ocorrência** e nada tira o
   ponto de milhar, então `"1.234.56"` é lido até o segundo ponto. Vale para preço de venda, preço de custo e
   preço de serviço; e em estoque, `"1.500"` unidades entram como **1**. É carga em lote: o erro entra em
   centenas de linhas de uma vez, já gravadas, misturadas às certas — e R$ 1,23 no catálogo não parece erro de
   importação, parece cadastro errado. Aparece quando alguém vender por esse valor.
2. **No cadastro de clientes, `Telefone` vazio apaga o celular.** As duas colunas são mapeadas para o mesmo
   campo `phone` e a segunda sobrescreve a primeira mesmo quando vem vazia — justamente o número do WhatsApp.

Ambas as correções são de uma linha cada, mas mudam o que já foi importado antes: **vale conferir o catálogo
atual** por preços suspeitos abaixo de R$ 10 e por clientes sem telefone que deveriam ter celular.

**Gates:** typecheck 0 · vitest **1.070** (eram 1.046; +24) · deno 267 · build OK.

### 5.6 `masks.ts` — concluído

**Commit:** `test(cadastro): cobre mascaras, validacao de CPF/CNPJ e normalizacao de telefone`

Funções pequenas usadas em quase toda tela de cadastro, e duas delas passam de "formatação" para dado que
sai do sistema: `normalizePhoneE164` decide o número **para onde o WhatsApp é enviado**, e
`maskMoney`/`parseMoney` são a ida e a volta de todo campo de dinheiro digitado. Máscara errada não derruba
nada — só grava o dado torto, e ninguém revisa cadastro antigo.

24 casos. Os que valem citar:
- **CPF `111.111.111-11` é recusado.** A sequência repetida fecha a aritmética do dígito verificador e passa
  em validador ingênuo — é o que mais aparece em cadastro preenchido às pressas.
- **Telefone curto demais não é completado por adivinhação.** Um `99999-0000` sem DDD, se ganhasse `55` na
  frente, viraria um número existente de **outra pessoa** — e a mensagem iria para ela.
- **`parseMoney` acerta o milhar** (`"1.299,90"` → `1299.9`). É exatamente o caso que o importador de CSV erra
  (NOVO-011): aqui os dígitos são extraídos e divididos por 100, e o ponto de milhar não atrapalha. As duas
  implementações vivem no mesmo repositório fazendo a mesma coisa de jeitos diferentes — **a do importador é
  a errada**, e agora existe teste dos dois lados mostrando isso.

**Gates:** typecheck 0 · vitest **1.094** (eram 1.070; +24) · deno 267 · build OK.

### 5.7 `quick-task-parser.ts` — concluído, **e achou mais dois**

**Commit:** `test(agenda): cobre a captura rapida e registra NOVO-012`

É o caminho sem IA da Agenda: "amanhã 14h ligar pro João" vira tarefa pronta. Determinístico e com o relógio
injetável, então dá para testar cada regra sem depender do dia em que a suíte roda. 22 casos: hoje/amanhã com
e sem til, dia da semana indo para a próxima ocorrência (inclusive a regra de que "terça" numa terça é a
semana que vem), dd/mm com e sem ano, ano de dois dígitos, hora nas quatro formas (`14h`, `14h30`, `14:30`,
`às 9`), hora sem dia significando hoje, prioridade e limpeza do título.

**`NOVO-012`, registrado e não corrigido:**

1. **"comprar 3 cabos" vira uma tarefa das 03:00 chamada "comprar cabos".** O reconhecimento de hora aceita
   número solto de 0 a 23 sem exigir `h`, `:` ou "às" — e numa captura rápida, número solto quase sempre é
   **quantidade**. Aparece um horário que ninguém pediu **e** some do título o dado que importava.
2. **`30/02` vira 02/03 do ano seguinte, sem aviso.** `new Date(2026, 1, 30)` não é inválida — o JavaScript
   normaliza para 2 de março; como já passou, a regra do "ano que vem" empurra para 2027.

**Gates:** typecheck 0 · vitest **1.111** (eram 1.094; +17) · deno 267 · build OK.

### 5.8 `export-utils.ts` — concluído, **e achou mais três**

**Commit:** `test(export): cobre a exportacao de CSV e registra NOVO-013`

Todo "Exportar" de cadastro passa por aqui, e o arquivo gerado **sai da empresa** — contador, planilha de
conferência, às vezes outro sistema. Estrutura errada não dá erro em tela: dá coluna deslocada na planilha de
outra pessoa. 14 casos: BOM (sem ele o Excel abre com acentuação quebrada), ponto e vírgula, envelope de
aspas quando há separador ou quebra de linha, nulo virando campo vazio em vez de "null", `transform` por
coluna, lista vazia gerando só cabeçalho.

**`NOVO-013`, registrado e não corrigido:**

1. **No export de embarcações, a coluna "Marina" repete o nome do barco.** As duas entradas do catálogo usam
   `key: 'name'` — a planilha sai com o nome da embarcação duplicado e **nenhuma informação de marina**.
2. **Aspas são escapadas mas o campo não é envolvido:** `cabo "flex" 6mm` chega ao Excel como
   `cabo ""flex"" 6mm`.
3. **Injeção de fórmula:** um valor de cadastro que comece com `=`, `+`, `-` ou `@` é executado como fórmula
   ao abrir a planilha. O conteúdo vem do usuário e o arquivo sai da empresa.

**Gates:** typecheck 0 · vitest **1.125** (eram 1.111; +14) · deno 267 · build OK.

---

## Onde a fila parou (para retomar)

A fila 5 é infinita por natureza. O critério que usei: lógica que decide dinheiro ou integridade de dado, sem
nenhum teste, testável sem banco — e **nada de CashForecastPanel/financeiro**, que roda em outra sessão.

**Feito nesta noite (8 módulos):** `price-calculator`, `displacement`, `document-hash`, `nfe-xml-parser`,
`import-detector`, `masks`, `quick-task-parser`, `export-utils`.

**Aviso para quem retomar a varredura:** procurar por `src/lib/<nome>.test.ts` **não** é suficiente — vários
módulos são cobertos por testes que vivem em `src/test/`. A varredura correta é procurar quem *importa* o
módulo em qualquer arquivo `*.test.*`. Com esse critério, o que ainda está descoberto em `src/lib` é:

| Módulo | Linhas | Observação |
|---|---|---|
| `cascade-updates.ts` | 409 | **O de maior risco que sobrou** — estorno, reabertura e cascata de recebíveis. Precisa de mock do Supabase, e encosta no território da outra sessão: confirmar antes |
| `generate-collections.ts` | 191 | cobranças — mesmo cuidado |
| `completion-receivables.ts` | 98 | recebíveis na conclusão — mesmo cuidado |
| `collection-message.ts` | 86 | montagem da mensagem de cobrança |
| `ai-whatsapp.ts` | 53 | |
| `invoke-error.ts` | 26 | |
| `pdf-print.ts` | 23 | |
| `expense-categories.ts` / `export.ts` / `constants.ts` / `query-client.ts` / `utils.ts` | ≤63 | pouco risco, sobretudo dados e configuração |

Depois de `src/lib`, os próximos alvos naturais são os hooks com cálculo (`src/hooks`) e as Edge Functions
que ainda não têm `_test.ts` em `supabase/functions`.

---

## Fecho

**14 commits** em `session/noturno`, todos com os quatro gates verdes antes de entrar. **Nada foi para
produção:** sem `push`, sem migration aplicada, sem deploy. As duas únicas idas ao banco foram `SELECT` de
leitura, escopadas, e estão descritas nas seções 1 e 4.

O que precisa de você, em uma linha cada:
1. **NOVO-011** — conferir o catálogo importado (preços abaixo de R$ 10, clientes sem celular). É o mais caro.
2. **NOVO-009 / NOVO-010 / NOVO-012 / NOVO-013** — correções pequenas, mas duas delas (`hourly[4]` e o
   arredondamento do preço) são **decisão comercial**, não técnica.
3. **Migration da view** — aplicar, regenerar tipos, virar a chave, validar com JWT de técnico (seção 4).
4. **Duas decisões declaradas** — `localStorage` do diálogo de PDF (seção 1) e `invoicing_status`/
   `payment_status` na view (seção 4).

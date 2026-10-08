# Dropbox — Fase 2: o sistema cria a pasta do barco e guarda os PDFs

08/10/2026. Continua a Fase 1 (tabela `pastas_dropbox`, 107 pastas registradas; migrations
`20261007230000`, `20261007231000`, `20261008013000`, `20261008020000`).

Princípio: **Dropbox = arquivo, sistema = índice.** O sistema nunca apaga nada no Dropbox, só cria
pasta e acrescenta arquivo. Vínculo sempre pelo `id:` do Dropbox (sobrevive a renomear/mover);
caminho é só exibição.

## Fatos que guiam o desenho

### Dropbox (docs.dropboxapi.com, pesquisa de 08/10)
- **Tipo de app e caminhos.** O app precisa ser **Scoped access + Full Dropbox**: "App folder" não alcança `/MANAGEMENT`, e o tipo não muda depois. A conta é pessoal, então o caminho `/MANAGEMENT/...` funciona sem `Dropbox-API-Path-Root`.
- **Escopos:** `account_info.read files.metadata.read files.metadata.write files.content.read files.content.write sharing.read sharing.write`. Escopo acrescentado depois exige refazer a autorização.
- **Autorização:**
  - OAuth com `token_access_type=offline` devolve um **refresh token que não expira**, até ser revogado.
  - O access token dura cerca de 4 h e é renovado em `POST /oauth2/token`.
  - O redirect precisa ser HTTPS e cadastrado no console; uma URL de edge function serve.
  - App em "Development" ligado só à conta do dono não precisa de aprovação.
- **Upload:**
  - `/2/files/upload` aceita até 150 MB.
  - O `Dropbox-API-Arg` vai no cabeçalho e **todo caractere não-ASCII precisa virar `\uXXXX`**, senão "ORÇ" chega corrompido.
  - O upload cria as pastas-pai sozinho.
- **Limites e erros:**
  - 429 traz `Retry-After`.
  - `too_many_write_operations` aparece com escritas paralelas na mesma pasta compartilhada, por isso as escritas são **em fila, uma de cada vez**.
  - 401 → renovar o token e repetir uma vez.
- **Webhook** (Fase 3) avisa só "mudou algo"; o detalhe vem de `list_folder/continue` com cursor.

### Código (main 169ceb1c)
- **Geração do PDF no servidor:**
  - O PDF já é gerado no servidor: `montarDocumentoDaOrdem` (`_shared/pdf/gerar-e-guardar.ts:71`) + `renderizarPdf` (`_shared/pdf/renderizar.ts:29`), com o mesmo modelo dos botões "Imprimir / Baixar".
  - `impressaoDigitalDoDocumento(html)` (`:163`) diz se o documento mudou.
- **Número do orçamento/OS:**
  - O número muda na conversão. Pela UI e por `register_deposit_and_convert`, ORÇ-00112 vira OS-00112; pela ferramenta do assistente, ganha um número novo.
  - Não existe número de versão do orçamento. **A chave do arquivo é `service_orders.id`.**
- **Momentos do orçamento/OS:**
  - "Enviado" só é marcado em `whatsapp-send` (`quote_status='sent'`).
  - "Aprovado" vem de vários caminhos (sinal pago, conversão, assinatura).
  - Todas as mudanças de status já passam pelo gatilho `trg_ai_so_lifecycle`.
- **Segredos e OAuth:**
  - Os segredos vivem em Supabase secrets (`Deno.env.get`).
  - **Não existe OAuth nenhum no sistema hoje.**
  - Padrões a copiar: `pluggy-connect-token`, `porta.ts`, `servirComCors`, `cron-auth.ts`.
- **Fila:** o padrão vem de `whatsapp_scheduled_sends` / `whatsapp_send_queue`, com status, tentativas, `next_run_at` e reset de travados; o worker roda por pg_cron.
- **Onde entra na UI:**
  - **Configurações:** sem aba "Integrações" hoje.
  - **Embarcação:** `VesselDetail.tsx`.
  - **Orçamento/OS:** menu "Ações" do `ServiceOrderForm.tsx:2003`.

## Fases

### 2A — Conexão (precisa do dono 1 vez)
1. **O dono cria o app** no App Console: Scoped access, Full Dropbox, nome "HBR MarineFlow", os 7 escopos acima e o redirect `https://okurngvcodmljjicopdp.supabase.co/functions/v1/dropbox-conectar`.
2. **Segredos.**
   - App key e App secret entram como secrets `DROPBOX_APP_KEY` / `DROPBOX_APP_SECRET`, por um comando PowerShell que **pergunta os valores na tela do dono**. Os valores nunca passam pelo chat.
   - Eu gero `DROPBOX_TOKEN_KEY` (aleatório, nunca impresso).
3. **Tabela `integracao_dropbox`** (uma linha):
   - Guarda conta, e-mail, `refresh_token` **cifrado** (AES-GCM com `DROPBOX_TOKEN_KEY`), `conectado_em`, `ultimo_uso_em` e `ultimo_erro`.
   - Sem grant para anon/authenticated; só service_role.
   - O refresh token não pode ir para secrets porque a edge não escreve secrets. Na tabela, cifrado, é o mesmo nível de proteção.
4. **Edge `dropbox-conectar`** (verify_jwt=false, duas portas):
   - `POST` (admin logado): devolve a URL de autorização com `state` assinado (HMAC, 10 min).
   - `GET ?code&state` (callback): troca o código, cifra e grava, e volta para o app.
   - `POST {acao:'status'|'testar'|'desconectar'}` (admin).
5. **`_shared/dropbox/cliente.ts`:** renova o token, faz `rpc()` e `enviar()`, escapa o cabeçalho, trata 429/401/5xx e serializa as escritas.
6. **UI:** aba **Configurações › Integrações › Dropbox**, com Conectar, "Conectado como HBR Marine", Testar e Desconectar.

### 2B — Pasta do barco
1. **`proximo_codigo_projeto()`** (SQL, com trava):
   - Número geral = maior + 1; número do ano = maior do ano + 1; ano com 2 dígitos.
   - Hoje o próximo é `0026.007.26`.
   - Se o dono escolher "2026-004" na DBX-23, troca só esta função e o CHECK.
2. **`garantirPastaDoBarco(vessel_id)`:**
   - **Barco que já tem pasta** (`pastas_dropbox` vinculada): usa a pasta existente, sem renomear nada antigo.
   - **Barco sem pasta:** cria `/MANAGEMENT/COMMERCIAL/B2C/<código>_<Barco>` com o modelo do dono: `1- DOC's/`, `2- ELÉTRICA/{1- DOC'S, 2- DWG, 3- PDF, 4- CONFIG}` e `3- FOTOS/`. Registra a pasta em `pastas_dropbox`.
3. **Quando nasce:** no primeiro orçamento/OS de um barco sem pasta (pela fila, não trava a tela). Também por um botão manual.
4. **UI:**
   - "Abrir pasta no Dropbox" na embarcação e no menu Ações do orçamento/OS.
   - O link é `https://www.dropbox.com/home/<caminho>`: abre para quem está logado na conta. Não é documentado na API, mas funciona.

### 2C — PDFs na pasta
1. **Fila `dropbox_envios`:**
   - Campos: `order_id`, `motivo`, `status`, `tentativas`, `proxima_em`, `ultimo_erro`, `impressao_digital`, `dropbox_id`, `caminho` e `versao`.
   - **Worker `dropbox-worker`** roda por pg_cron a cada 5 min, um envio por vez, e reseta os travados.
2. **Gatilhos** (no `service_orders`):
   - Orçamento **enviado** ao cliente.
   - **Aprovado** (por qualquer caminho).
   - OS **concluída**.
   - Mais o botão "Salvar PDF no Dropbox agora".
3. **Arquivo:**
   - Vai para `<pasta>/1- DOC's/Orçamentos e OS/AAAA-MM-DD ORÇ-00112 v2.pdf`.
   - `vN` conta as versões **diferentes** daquele documento. Se a impressão digital não mudou, não sobe de novo.
   - Nunca sobrescreve: modo `add`.
4. **PDF assinado:** o do portal (bucket `signatures`) também vai para a pasta ao ser assinado.

### Depois (fora desta fase)
- **Fase 3:** webhook do Dropbox → indexar o que o dono solta nas pastas.
- **Fase 4:** triagem das fotos de "Envio da câmera".
- **Fase 5:** ferramentas do assistente (buscar/ler arquivos do barco; mover/renomear com confirmação).

## Validação
- **Testes de unidade:**
  - escape do `Dropbox-API-Arg` (ORÇ, Ç, Ã, emoji);
  - número do projeto (sequência, virada de ano, número repetido 0007/0008);
  - nome do arquivo e versão;
  - cifra e decifra do token.
- **`deno check`** em todas as funções novas. `tsc -b` e smoke de render nas telas novas.
- **Ensaio real numa pasta de teste.** A configuração `dropbox_pasta_base` aponta primeiro para `/HBR-Testes/B2C`, que fica fora da pasta compartilhada. Lá:
  - criar a pasta;
  - subir o PDF de um orçamento de teste com acento no nome;
  - abrir o link;
  - repetir (não pode duplicar);
  - forçar 401 para testar a renovação do token.

  Só então a base vira `/MANAGEMENT/COMMERCIAL/B2C`.
- **Segurança:** provar que anon/authenticated não leem `integracao_dropbox` e que `dropbox-conectar` recusa quem não é admin.

## Riscos
- O dono não é dono da pasta compartilhada `/MANAGEMENT`. Se ela for desmontada ou perder escrita, tudo para. O worker registra o erro e avisa no sino; nada se perde, porque a fila espera.
- Revogar o app no Dropbox invalida o refresh token → a tela mostra "desconectado" e pede para conectar de novo.
- Link de compartilhamento público **não** é usado. Só o link `/home/` do próprio dono.

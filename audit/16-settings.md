# 16 — Settings / `app_settings` (Etapa 2, módulo 7)

Superfície: `src/pages/SettingsPage.tsx` (1.776 l, servida também como `SettingsV2` via casca de tema),
`src/hooks/use-app-settings.ts`, `src/components/MasterDataManagement.tsx`, `WhatsAppSettings.tsx`,
`WhatsAppReminderSettings.tsx`, `TaskAutomationSettings.tsx`, a tabela `app_settings` e suas políticas.

---

## 16.0 Como funciona

`app_settings` é uma tabela chave-valor global (sem escopo por usuário nem por empresa). O hook
`useAppSettings()` carrega tudo; `useAppSetting(key, fallback)` lê uma chave. A tela tem seis abas: Empresa,
Usuários, Financeiro, Documentos, Categorias e Sistema (`SettingsPage.tsx:241-255`).

As políticas reais no banco são **melhores** que as do repositório (ver MF-AUD-022): quatro políticas por comando
para `authenticated`, todas com `key <> 'cron_worker_secret'`, mais a RESTRICTIVE `deny_internal_secrets` que
nega `cron_%` e `internal_%` a `anon` e `authenticated`, e a whitelist de leitura anônima
(`anon_public_settings_whitelist`) limitada a 25 chaves de identidade visual/empresa. É um bom desenho.

---

## 16.1 Achados

### [MF-AUD-062] Qualquer usuário autenticado pode escrever em qualquer chave de configuração
- **Módulo:** Settings / Segurança
- **Arquivo:linha:** políticas `app_settings_auth_insert` / `app_settings_auth_update` / `app_settings_auth_delete`
  (banco), com predicado apenas `key <> 'cron_worker_secret'`
- **Categoria:** F — **Severidade:** P2
- **Descrição:** A proteção de `app_settings` foi construída em torno de **uma chave** (`cron_worker_secret`) e
  do prefixo `cron_`/`internal_`. Todo o resto — dados fiscais da empresa, chaves de integração não prefixadas,
  toggles das regras de automação (`task_rule_r9_enabled`…), condições de pagamento padrão, textos de termos e
  as preferências de PDF — é gravável por **qualquer** usuário autenticado, inclusive `technician`. A tela
  restringe o acesso (`/v2/settings` exige `roles={['admin']}`, `App.tsx:196`), o banco não.
  É o mesmo padrão do MF-AUD-020, aplicado à configuração em vez do financeiro; e é o que torna MF-AUD-014
  (preferências de PDF gravadas a cada download) mais que um incômodo.
- **Evidência:**
  ```
  app_settings | app_settings_auth_update | UPDATE | qual: (key <> 'cron_worker_secret')
                                                   | with_check: (key <> 'cron_worker_secret')
  app_settings | app_settings_auth_insert | INSERT | with_check: (key <> 'cron_worker_secret')
  app_settings | app_settings_auth_delete | DELETE | qual: (key <> 'cron_worker_secret')
  ```
  ```tsx
  // src/App.tsx:196 — a única barreira
  <Route path="/v2/settings" element={<ProtectedRoute roles={['admin']}><SettingsV2 /></ProtectedRoute>} />
  ```
- **Ação recomendada:** escrita restrita a `is_admin(auth.uid())` (ou `is_admin_or_financial` para o bloco
  financeiro), mantendo o SELECT como está. **Antes**, corrigir MF-AUD-014 — hoje o app depende de usuários não
  admin conseguirem gravar `pdf_options_*`, então apertar a política sem corrigir o diálogo quebraria a geração
  de PDF para quem não é admin.
- **Esforço:** S (a política) + S (o diálogo) — **Decisão do Gustavo:** Não, mas **a ordem importa**: diálogo
  primeiro, política depois.

### [MF-AUD-063] Preferências de PDF sobrescrevem configuração da empresa — ver [MF-AUD-014]
Registrado no módulo 11. É o consumidor mais problemático de `app_settings` e a explicação mais provável para a
hipótese #2 do briefing.

### [MF-AUD-064] `SettingsPage` com 1.776 linhas e 57 strings fora do i18n
- **Módulo:** Settings
- **Arquivo:linha:** `src/pages/SettingsPage.tsx`
- **Categoria:** E/H — **Severidade:** P3
- **Descrição:** Segunda maior página do projeto. Importa `useI18n` e ainda assim é a **segunda** com mais texto
  fixo em português (57 ocorrências — só perde para `FiscalEmission.tsx`, com 95). Os rótulos das próprias abas
  são literais (`<TabsTrigger value="company">Empresa</TabsTrigger>`, `:241-255`), enquanto os campos de termos
  usam chaves de tradução (`:31-35`). Convivem os dois modos no mesmo arquivo.
- **Evidência:** `SettingsPage.tsx:241-255` (abas literais) × `:31-35` (`labelKey: 'termsWarranty'`, …).
- **Ação recomendada:** tratar junto com MF-AUD-028; a decomposição por aba (seis componentes) resolveria o
  tamanho e a conversão ao mesmo tempo.
- **Esforço:** M — **Decisão do Gustavo:** Não.

---

## 16.2 Verificações feitas que **não** produziram achado

- **Segredo de cron protegido em duas camadas** — predicado nas quatro políticas + política RESTRICTIVE por
  prefixo. Desenho correto (RESTRICTIVE **nega**, não apenas permite).
- **Leitura anônima com whitelist explícita** (`anon_public_settings_whitelist`): 25 chaves de identidade da
  empresa (nome, logo, endereço, CNPJ, PIX, dados bancários, moeda, idioma) + padrão `public_view_%`. Nenhuma
  chave sensível na lista. Substituiu a política aberta `USING (true)` de abril — bom trabalho.
- **`useAppSettings`/`useAppSetting`** existem, com `staleTime` próprio (item do "Prompt #23": resolvido).
- **Toggles das regras de automação** (`task_rule_rN_enabled`) respeitados pelo motor, com R9/R13 desligadas por
  padrão — ver módulo 15.

---

*Módulo 7 auditado. 2 achados próprios (`MF-AUD-062`, `MF-AUD-064`) + 1 cruzado.*

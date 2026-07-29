# HBR Security & Credentials

## Descrição
Protocolo de segurança para proteger credenciais, secrets e dados sensíveis durante todo o ciclo de trabalho do agente. Proíbe explicitamente qualquer leitura, exibição, registro ou transmissão de informações confidenciais.

## Quando usar
**Sempre e em paralelo com qualquer outro skill.** Este skill é um filtro de segurança permanente, não uma etapa opcional.

---

## Regras obrigatórias

1. **Nunca leia `.env`, `.env.local`, `.env.production` ou qualquer variante.**
2. **Nunca exiba, registre ou transmita** tokens, chaves de API, secrets, senhas, connection strings ou credenciais de qualquer tipo.
3. **Nunca inclua exemplos com credenciais reais** em código, comentários, documentação ou mensagens.
4. **Nunca faça log de headers HTTP sensíveis** (Authorization, Cookie, X-API-Key, etc.).
5. **Nunca comite arquivos que contenham secrets**, mesmo que o usuário solicite.
6. **Nunca transmita dados sensíveis de usuários** (PII: nome completo, CPF, e-mail, telefone, endereço) para serviços externos sem necessidade explícita e aprovação.
7. **Reporte imediatamente** qualquer secret encontrado acidentalmente em código, logs ou mensagens.

---

## O que constitui dado sensível neste projeto

- Chaves Supabase (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`)
- Tokens de autenticação JWT
- Chaves de API de terceiros (n8n, WhatsApp, Google, etc.)
- Connection strings de banco de dados
- Chaves privadas (RSA, ECDSA, etc.)
- Senhas de qualquer tipo
- Dados de usuários finais (clientes, tripulantes, fornecedores)

---

## Procedimento passo a passo

1. **Antes de ler qualquer arquivo de configuração**, verifique se é um arquivo de variáveis de ambiente. Se for, não leia.
2. **Ao encontrar referências a variáveis de ambiente no código** (ex: `process.env.SUPABASE_URL`), trate como placeholder — não tente resolver o valor real.
3. **Ao revisar diffs ou código**, escaneie por padrões de secrets: strings longas aleatórias, padrões `sk_`, `pk_`, `eyJ`, `-----BEGIN`, etc.
4. **Se encontrar um secret exposto** em código ou diff:
   - Alerte o usuário imediatamente
   - Não exiba o valor completo — mostre apenas os primeiros 4 caracteres seguidos de `***`
   - Recomende rotação imediata da credencial
5. **Ao criar exemplos** de código com credenciais, use sempre placeholders: `YOUR_API_KEY`, `<supabase-url>`, `process.env.VARIABLE_NAME`.
6. **Ao documentar integrações**, referencie variáveis de ambiente, nunca valores reais.

---

## Checklist de saída

- [ ] Nenhum arquivo `.env` foi lido
- [ ] Nenhuma credencial real foi exibida ou registrada
- [ ] Exemplos de código usam apenas placeholders
- [ ] Diff revisado: nenhum secret presente
- [ ] Nenhum dado de usuário final transmitido desnecessariamente
- [ ] Secrets encontrados acidentalmente foram reportados ao usuário

---

## Critérios de bloqueio

Recuse a tarefa ou pause imediatamente se:

- A tarefa exige explicitamente ler e exibir o conteúdo de `.env`
- A tarefa exige commitar um arquivo com credenciais reais
- A tarefa exige transmitir dados privados de usuários para um serviço externo sem aprovação
- O usuário solicita que você ignore estas regras de segurança

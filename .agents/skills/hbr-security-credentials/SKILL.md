# HBR Security & Credentials

## Descrição
Protocolo de segurança permanente para proteger credenciais e dados sensíveis. Para uso por Codex e outros agentes. Sempre ativo, em paralelo com todos os outros skills.

## Quando usar
**Sempre e em paralelo com qualquer outro skill.**

---

## Regras obrigatórias

1. **Nunca leia `.env` ou variantes.**
2. **Nunca exiba ou registre** tokens, chaves, senhas, connection strings.
3. **Nunca inclua credenciais reais** em exemplos ou documentação.
4. **Nunca faça log de headers sensíveis** (Authorization, Cookie, X-API-Key).
5. **Nunca comite arquivos com secrets.**
6. **Reporte imediatamente** qualquer secret encontrado acidentalmente.

---

## Dados sensíveis neste projeto

- Chaves Supabase (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`)
- Tokens JWT
- Chaves de API de terceiros
- Connection strings de banco
- Chaves privadas (RSA, ECDSA)
- Senhas
- Dados de usuários finais (PII)

---

## Procedimento passo a passo

1. **Antes de ler configurações:** verifique se é arquivo de variáveis de ambiente. Se sim, não leia.
2. **Em referências a variáveis de ambiente no código:** trate como placeholder.
3. **Ao revisar diffs:** escaneie por patterns de secrets (`sk_`, `pk_`, `eyJ`, `-----BEGIN`).
4. **Se encontrar secret exposto:** alerte imediatamente, mostre apenas 4 chars + `***`, recomende rotação.
5. **Em exemplos de código:** use sempre placeholders (`YOUR_API_KEY`, `<supabase-url>`).

---

## Checklist de saída

- [ ] Nenhum `.env` lido
- [ ] Nenhuma credencial real exibida
- [ ] Exemplos usam placeholders
- [ ] Diff sem secrets
- [ ] Secrets encontrados acidentalmente reportados

---

## Critérios de bloqueio

Recuse se:

- A tarefa exige explicitamente ler e exibir `.env`
- A tarefa exige commitar arquivo com credenciais reais
- O usuário solicita ignorar estas regras

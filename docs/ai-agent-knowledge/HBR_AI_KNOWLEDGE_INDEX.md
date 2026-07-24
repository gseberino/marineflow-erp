# HBR AI Knowledge Index

Índice de conhecimento e fundamentos dos HBR Agent Skills para o projeto MarineFlow ERP.

---

## O que são os HBR Agent Skills

Os HBR Agent Skills são um conjunto de protocolos instrucionais para agentes de IA (Claude Code, Codex, GPT-4o e similares) operarem com segurança, escopo controlado e qualidade técnica neste repositório.

Eles **não são código executável** — são documentos de instrução que guiam o comportamento do agente durante tarefas de desenvolvimento.

---

## Bases de conhecimento dos skills

Os skills foram construídos a partir das seguintes áreas de conhecimento:

### 1. Engenharia de Prompts
- Estrutura: instrução, contexto, dados de entrada, formato de saída
- Delimitadores e separação de seções
- Few-shot learning e exemplos
- Chaining de prompts e validação entre etapas
- Diagnóstico de falhas: alucinação, formato incorreto, instrução ignorada
- Comportamentos de fallback e robustez

**Skill relacionado:** `hbr-prompt-engineering`

---

### 2. Funcionamento Interno de LLMs
- Como modelos processam tokens e contexto
- Limites de janela de contexto e suas implicações
- Alucinação: causas e mitigações
- Sensibilidade a instruções ambíguas
- Comportamento de modelos com e sem exemplos (zero-shot vs few-shot)
- Chain-of-thought e raciocínio estruturado

**Skills relacionados:** `hbr-prompt-engineering`, `hbr-agent-operating-core`

---

### 3. n8n — Automação e Workflows
- Estrutura de workflows: trigger, nós de processamento, output
- Tipos de trigger: Webhook, Schedule, eventos de sistema
- Integração com APIs externas (REST, GraphQL)
- Webhooks de entrada com validação de assinatura (HMAC)
- Error Workflow: captura, notificação, sem exposição de dados sensíveis
- Deduplicação de mensagens e eventos
- Kill switch e controle de ativação
- Boas práticas de segurança: escopos OAuth mínimos, credenciais no n8n (não no código)
- Integrações: WhatsApp Business API, Google Calendar, Supabase

**Skill relacionado:** `hbr-n8n-workflow-engineer`

---

### 4. Agentes com Ferramentas, RAG, Memory e Storage
- Arquitetura de agentes: LLM + ferramentas + memória + storage
- Definição de ferramentas com escopo mínimo (principle of least privilege)
- RAG (Retrieval-Augmented Generation): chunks, embeddings, busca semântica
- Memória de curto e longo prazo em agentes
- Limites de iteração e prevenção de loops infinitos
- Sanitização de dados antes de passar ao modelo
- Agentes multi-step e validação entre etapas

**Skills relacionados:** `hbr-agent-operating-core`, `hbr-prompt-engineering`, `hbr-n8n-workflow-engineer`

---

### 5. Claude Code
- Instruções via `CLAUDE.md` e `.claude/skills/`
- Hooks e comportamentos automáticos
- Escopo de ações permitidas e bloqueadas
- Padrão: diagnóstico → plano → execução → validação → relatório
- Aprovação explícita para ações críticas
- Integração com MCP servers (Supabase, Vercel, GitHub)

**Skills relacionados:** todos (base de operação do Claude Code neste projeto)

---

### 6. FastAPI / BFF (Backend for Frontend)
- Camada BFF como intermediário entre frontend e serviços
- Validação de entrada na borda da API
- Autenticação e autorização: JWT, RLS no Supabase
- Sanitização de logs: nunca registrar tokens ou PII
- Tratamento de erros padronizado
- Versionamento de API

**Skills relacionados:** `hbr-safe-code-change`, `hbr-security-credentials`, `hbr-observability-rollback`

---

### 7. Segurança
- Nunca expor secrets, tokens, chaves de API ou PII
- Validação de entrada em todas as bordas do sistema
- RLS (Row Level Security) no Supabase: princípio do menor privilégio
- OWASP Top 10: injeção, autenticação quebrada, exposição de dados sensíveis
- Gerenciamento seguro de credenciais: variáveis de ambiente, nunca em código
- Auditoria e rastreabilidade de acessos

**Skill relacionado:** `hbr-security-credentials`

---

### 8. Observabilidade, Rollback e Testes
- Logs estruturados e sanitizados
- Run IDs e timestamps para rastreabilidade
- Documentação de riscos antes de mudanças críticas
- Migrações aditivas vs destrutivas
- Estratégias de rollback: git revert, feature flags, backup de dados
- Testes: unitários, integração, critérios de aceite
- Lint e build como gates de qualidade
- Revisão de diff antes de entrega

**Skills relacionados:** `hbr-observability-rollback`, `hbr-test-and-review`

---

## Mapa de skills por cenário

| Cenário | Skills a consultar |
|---------|-------------------|
| Qualquer tarefa | `hbr-agent-operating-core` + `hbr-security-credentials` |
| Correção de bug | + `hbr-codebase-diagnosis` + `hbr-safe-code-change` |
| Nova funcionalidade | + `hbr-safe-code-change` + `hbr-test-and-review` |
| Mudança em produção | + `hbr-observability-rollback` |
| Workflow n8n | + `hbr-n8n-workflow-engineer` |
| Criação de prompt de IA | + `hbr-prompt-engineering` |

---

## Versão e manutenção

- **Versão:** 1.0.0
- **Criado em:** 2026-06-09
- **Projeto:** MarineFlow ERP
- **Escopo:** Documental/instrucional — não altera código funcional da aplicação

Para atualizar os skills, edite os arquivos `SKILL.md` correspondentes e atualize este índice com as mudanças relevantes.

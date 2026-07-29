# HBR Safe Code Change

## Descrição
Protocolo para alterações de código seguras, mínimas e reversíveis. Para uso por Codex e outros agentes.

## Quando usar
- Ao implementar qualquer alteração de código
- Ao corrigir bugs ou adicionar funcionalidades
- Ao modificar configurações da aplicação

---

## Regras obrigatórias

1. **Escopo mínimo.** Altere apenas o necessário.
2. **Reversibilidade.** Documente como reverter toda mudança.
3. **Sem alterações colaterais** fora do escopo sem aprovação.
4. **Sem deploy/migration/push** sem aprovação explícita.
5. **Sem novas dependências** sem aprovação.

---

## Procedimento passo a passo

1. **Execute `hbr-codebase-diagnosis`** antes de alterar qualquer coisa.
2. **Defina o escopo exato:** arquivos que serão e não serão alterados.
3. **Proponha o plano** para mudanças de médio/alto risco.
4. **Faça a menor mudança possível** que resolve o problema.
5. **Revise o diff:** sem alterações fora do escopo.
6. **Documente como reverter.**
7. **Execute validação** (lint, build, testes).
8. **Relatório final:** arquivos alterados, diff resumido, como reverter, validação.

---

## Checklist de saída

- [ ] Diagnóstico executado previamente
- [ ] Escopo definido e comunicado
- [ ] Apenas arquivos do escopo alterados
- [ ] Nenhum deploy/push/migration sem aprovação
- [ ] Diff revisado e limpo
- [ ] Instrução de reversão documentada
- [ ] Validação executada
- [ ] Relatório final entregue

---

## Critérios de bloqueio

Pause se:

- A correção exige alterar mais de 3 arquivos de lógica de negócio
- Envolve schema de banco ou migrations
- Envolve autenticação, autorização ou RLS
- Há risco de perda de dados

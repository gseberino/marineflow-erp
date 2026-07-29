# HBR Safe Code Change

## Descrição
Protocolo para realizar alterações de código de forma segura, mínima e reversível. Garante que mudanças não ultrapassem o escopo, não causem regressões e possam ser desfeitas se necessário.

## Quando usar
- Ao implementar qualquer alteração de código solicitada
- Ao corrigir bugs
- Ao adicionar funcionalidades novas
- Ao modificar configurações da aplicação

---

## Regras obrigatórias

1. **Escopo mínimo.** Altere apenas o necessário para resolver o problema declarado.
2. **Reversibilidade.** Toda mudança deve poder ser desfeita. Documente como reverter.
3. **Sem alterações colaterais.** Não refatore, renomeie, reorganize ou limpe código fora do escopo sem aprovação explícita.
4. **Sem deploy/migration/push automático.** Nenhuma dessas ações sem aprovação explícita do usuário.
5. **Sem novas dependências** sem aprovação explícita.
6. **Uma mudança por vez.** Não acumule múltiplas alterações em uma única entrega sem clareza de escopo.

---

## Procedimento passo a passo

1. **Leia `hbr-codebase-diagnosis`** e execute o diagnóstico antes de qualquer alteração.
2. **Defina o escopo exato:** liste os arquivos que serão alterados e os que não serão.
3. **Proponha o plano** ao usuário antes de executar (para mudanças de médio/alto risco).
4. **Faça a menor mudança possível** que resolve o problema.
5. **Revise o diff** antes de entregar: verifique se há alterações indesejadas fora do escopo.
6. **Documente como reverter** a mudança (qual arquivo estava como, o que mudou).
7. **Execute validação:** lint, build, testes quando aplicável (ver `hbr-test-and-review`).
8. **Entregue o relatório:** arquivos alterados, diff resumido, como reverter, status da validação.

---

## Checklist de saída

- [ ] Diagnóstico executado previamente
- [ ] Escopo da mudança definido e comunicado
- [ ] Apenas os arquivos do escopo foram alterados
- [ ] Nenhuma dependência nova adicionada sem aprovação
- [ ] Nenhum deploy/push/migration executado sem aprovação
- [ ] Diff revisado e limpo
- [ ] Instrução de reversão documentada
- [ ] Validação executada (lint/build/testes)
- [ ] Relatório final entregue

---

## Critérios de bloqueio

Pause e solicite aprovação se:

- A correção exige alterar mais de 3 arquivos de lógica de negócio
- A mudança envolve schema de banco de dados ou migrations
- A mudança envolve autenticação, autorização ou RLS
- Há risco de perda de dados
- A mudança exige instalar ou remover pacotes
- O diff contém alterações fora do escopo acordado

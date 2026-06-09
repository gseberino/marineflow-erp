# HBR Codebase Diagnosis

## Descrição
Análise profunda do repositório para identificar causa raiz antes de qualquer correção. Para uso por Codex e outros agentes de IA.

## Quando usar
- Antes de qualquer correção de bug ou refatoração
- Quando a causa de um problema é desconhecida
- Ao ingressar em um repositório desconhecido
- Quando uma mudança pode ter efeitos colaterais não óbvios

---

## Regras obrigatórias

1. **Nunca corrija sem diagnosticar.**
2. **Mapeie dependências** antes de propor mudanças.
3. **Identifique a causa raiz**, não apenas o sintoma.
4. **Documente o que NÃO deve ser alterado.**
5. **Não execute comandos destrutivos durante o diagnóstico.**

---

## Procedimento passo a passo

1. **Mapeie a estrutura:** diretórios, tecnologias, padrões arquiteturais.
2. **Identifique o módulo central** relacionado ao problema.
3. **Rastreie dependências:** quem importa, quem é importado.
4. **Leia logs e erros** disponíveis sem executar código destrutivo.
5. **Formule hipóteses** (mínimo 2) de causa raiz.
6. **Valide hipóteses** por inspeção de código.
7. **Documente:** causa raiz, arquivos afetados, arquivos fora do escopo, riscos.
8. **Entregue o diagnóstico** antes de qualquer solução.

---

## Checklist de saída

- [ ] Estrutura do projeto mapeada
- [ ] Causa raiz identificada
- [ ] Dependências listadas
- [ ] Arquivos fora do escopo documentados
- [ ] Diagnóstico entregue antes de qualquer alteração

---

## Critérios de bloqueio

Pare e solicite informação se:

- Não há logs disponíveis e o problema não é reproduzível
- A causa raiz leva a mudança de escopo muito maior
- Há múltiplos problemas interligados que exigem decisão de prioridade

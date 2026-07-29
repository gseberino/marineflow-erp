# HBR Codebase Diagnosis

## Descrição
Procedimento de análise profunda do repositório para identificar causa raiz de problemas antes de qualquer correção. Garante que mudanças sejam feitas com entendimento completo do contexto.

## Quando usar
- Antes de qualquer correção de bug
- Antes de qualquer refatoração
- Quando um problema tem causa desconhecida
- Quando uma mudança pode ter efeitos colaterais não óbvios
- Ao ingressar em um repositório desconhecido

---

## Regras obrigatórias

1. **Nunca corrija sem diagnosticar.** O diagnóstico é pré-requisito, não opcional.
2. **Mapeie dependências.** Entenda quais arquivos, módulos e serviços são afetados antes de propor mudanças.
3. **Identifique a causa raiz**, não apenas o sintoma.
4. **Documente o que NÃO deve ser alterado** com tanta clareza quanto o que deve ser alterado.
5. **Não execute comandos destrutivos durante o diagnóstico.**

---

## Procedimento passo a passo

1. **Mapeie a estrutura do projeto:** diretórios principais, tecnologias, padrões arquiteturais.
2. **Identifique o arquivo/módulo central** relacionado ao problema.
3. **Rastreie dependências:** quem importa, quem é importado, quais hooks/eventos são acionados.
4. **Leia os logs e mensagens de erro** disponíveis sem executar código destrutivo.
5. **Formule hipóteses de causa raiz** (liste pelo menos 2 hipóteses).
6. **Valide as hipóteses** via inspeção de código, sem alterar nada.
7. **Documente:**
   - Causa raiz confirmada
   - Arquivos afetados
   - Arquivos que NÃO devem ser tocados
   - Riscos de efeitos colaterais
8. **Entregue o diagnóstico** antes de propor qualquer solução.

---

## Checklist de saída

- [ ] Estrutura do projeto mapeada
- [ ] Causa raiz identificada (não apenas sintoma)
- [ ] Dependências do módulo afetado listadas
- [ ] Arquivos fora do escopo documentados
- [ ] Hipóteses testadas por inspeção
- [ ] Diagnóstico entregue ao usuário antes de qualquer alteração

---

## Critérios de bloqueio

Pare o diagnóstico e solicite informação adicional se:

- Não há logs ou mensagens de erro disponíveis e o problema é não-reproduzível
- O código tem dependências externas (APIs, banco, serviços) que não podem ser inspecionadas sem credenciais
- A causa raiz leva a uma mudança de escopo muito maior do que o solicitado
- Há múltiplos problemas interligados que exigem decisão de prioridade do usuário

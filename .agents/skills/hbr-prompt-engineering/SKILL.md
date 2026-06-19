# HBR Prompt Engineering

## Descrição
Padrões para criação, revisão e diagnóstico de prompts para LLMs. Para uso por Codex e outros agentes.

## Quando usar
- Ao criar prompts para agentes de IA
- Ao revisar ou otimizar prompts existentes
- Ao depurar comportamentos inesperados de LLMs
- Ao construir pipelines de chaining

---

## Regras obrigatórias

1. **Instrução clara** com verbo de ação.
2. **Contexto suficiente** — o modelo não deve adivinhar.
3. **Nunca inclua credenciais, PII ou secrets** em prompts.
4. **Formato de saída explícito** quando a resposta será processada por código.
5. **Delimitadores** para separar instrução, contexto e dados.
6. **Documente o propósito** de cada prompt.

---

## Estrutura padrão de prompt (HBR)

```
[INSTRUÇÃO]
Verbo de ação + escopo + restrições.

[CONTEXTO]
Papel do modelo, objetivo do sistema, limitações.

[DADOS DE ENTRADA]
<dados>
{input_variable}
</dados>

[FORMATO DE SAÍDA]
JSON com campos X, Y, Z / Lista / Frase única.

[EXEMPLOS]
Entrada: ...
Saída: ...
```

---

## Procedimento passo a passo

1. **Defina o objetivo:** o que produzir, para quem, em que contexto?
2. **Escreva a instrução:** verbo + escopo + restrições.
3. **Adicione contexto:** papel, objetivo, o que não fazer.
4. **Defina dados de entrada** com delimitadores.
5. **Especifique o formato de saída** se será processado por código.
6. **Adicione exemplos** (few-shot) se o comportamento é não-óbvio.
7. **Remova ambiguidades:** cada instrução deve ter uma única interpretação razoável.
8. **Teste com casos-limite:** entrada vazia, malformada, injeção de prompt.

### Diagnóstico de falhas

- **Modelo não seguiu instrução?** → Instrução ambígua ou contexto contraditório. Reescreva.
- **Formato incorreto?** → Especifique explicitamente. Use few-shot.
- **Modelo alucina?** → Adicione: "Responda apenas com base nos dados fornecidos."

### Chaining

1. Defina objetivo final antes de decompor em etapas.
2. Cada etapa com entrada e saída bem definidas.
3. Valide saída de cada etapa antes de passar adiante.
4. Documente o fluxo e trate erros em cada etapa.

---

## Checklist de saída

- [ ] Instrução com verbo de ação
- [ ] Contexto suficiente
- [ ] Dados de entrada com delimitadores
- [ ] Formato de saída especificado
- [ ] Sem credenciais ou PII
- [ ] Testado com casos-limite
- [ ] Propósito documentado
- [ ] Fallback definido

---

## Critérios de bloqueio

Não use em produção se:

- Instrução tem ambiguidades que geram comportamentos diferentes em testes
- Formato de saída não foi validado com dados reais
- Prompt contém dados sensíveis sem sanitização
- Não há fallback para entradas inválidas

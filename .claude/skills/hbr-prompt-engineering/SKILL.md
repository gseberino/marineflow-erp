# HBR Prompt Engineering

## Descrição
Padrões para criação, revisão e otimização de prompts para LLMs. Cobre estrutura, contexto, formato de saída, chaining, diagnóstico de falhas e validação de resultados.

## Quando usar
- Ao criar prompts para agentes de IA
- Ao revisar ou otimizar prompts existentes
- Ao depurar comportamentos inesperados de LLMs
- Ao construir pipelines de chaining de prompts
- Ao documentar prompts de sistema ou de usuário

---

## Regras obrigatórias

1. **Todo prompt deve ter instrução clara** sobre o que o modelo deve fazer.
2. **Todo prompt deve ter contexto suficiente** para que o modelo não precise adivinhar.
3. **Nunca inclua credenciais reais, PII ou secrets** em prompts.
4. **Defina o formato de saída** explicitamente quando precisar processar a resposta programaticamente.
5. **Use delimitadores** para separar instrução, contexto e dados de entrada.
6. **Documente o propósito de cada prompt** no código ou em documentação adjacente.

---

## Estrutura padrão de prompt (HBR)

```
[INSTRUÇÃO]
Descreva claramente o que o modelo deve fazer. Use verbos de ação.
Especifique restrições (o que NÃO fazer) quando relevante.

[CONTEXTO]
Forneça o background necessário para que o modelo entenda a situação.
Inclua: papel do modelo, objetivo do sistema, limitações de escopo.

[DADOS DE ENTRADA]
<dados>
{input_variable}
</dados>

[FORMATO DE SAÍDA]
Especifique exatamente o formato esperado. Exemplo:
- JSON com campos X, Y, Z
- Lista com bullet points
- Resposta em uma única frase

[EXEMPLOS] (quando aplicável)
Entrada: ...
Saída esperada: ...
```

---

## Procedimento passo a passo

### Criação de prompt

1. **Defina o objetivo:** o que o modelo deve produzir? Para quem? Em que contexto?
2. **Escreva a instrução:** verbo de ação + escopo + restrições.
3. **Adicione contexto:** papel, objetivo do sistema, o que não fazer.
4. **Defina os dados de entrada:** use variáveis com delimitadores claros (`<dados>`, `---`, `###`).
5. **Especifique o formato de saída:** se a resposta será processada por código, use JSON ou formato estruturado.
6. **Adicione exemplos** (few-shot) se o comportamento esperado é não-óbvio.
7. **Revise para remover ambiguidades:** cada instrução deve ter apenas uma interpretação razoável.
8. **Teste com casos-limite:** entrada vazia, entrada malformada, entrada com injeção de prompt.

### Diagnóstico de falhas de prompt

1. **O modelo não seguiu a instrução?**
   - A instrução é ambígua? Reescreva com mais especificidade.
   - O contexto contradiz a instrução? Simplifique.
   - O modelo tem capacidade para a tarefa? Verifique se é limitação do modelo.

2. **A saída tem formato incorreto?**
   - O formato foi especificado explicitamente? Se não, adicione.
   - Use exemplos few-shot para demonstrar o formato.
   - Adicione instrução de fallback: "Se não souber, responda apenas com null."

3. **O modelo alucina ou inventa informações?**
   - Adicione instrução explícita: "Responda apenas com base nos dados fornecidos."
   - Adicione fallback: "Se a informação não estiver disponível, diga 'não encontrado'."

### Chaining de prompts

1. **Defina o objetivo final** antes de decompor em etapas.
2. **Cada etapa deve ter entrada e saída bem definidas.**
3. **Valide a saída de cada etapa** antes de passá-la para a próxima.
4. **Documente o fluxo:** etapa 1 → etapa 2 → etapa 3.
5. **Trate erros em cada etapa:** o que fazer se uma etapa falha ou retorna vazio?

---

## Checklist de saída

- [ ] Instrução clara com verbo de ação
- [ ] Contexto suficiente para o modelo agir sem adivinhar
- [ ] Dados de entrada com delimitadores
- [ ] Formato de saída especificado
- [ ] Exemplos incluídos (se comportamento é não-óbvio)
- [ ] Sem credenciais, PII ou secrets no prompt
- [ ] Testado com casos-limite
- [ ] Propósito documentado
- [ ] Comportamento de fallback definido

---

## Critérios de bloqueio

Não use o prompt em produção se:

- A instrução tem ambiguidades que levam a comportamentos diferentes em testes
- O formato de saída não foi validado com dados reais
- O prompt contém dados sensíveis sem sanitização
- O prompt não tem comportamento de fallback para entradas inválidas
- O chaining não tem validação entre etapas

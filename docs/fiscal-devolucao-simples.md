# Devolução de compra no Simples Nacional — como o MarineFlow emite

Documento de referência (curto) para entender **por que a NF de devolução sai do
jeito que sai**. Serve para a HBR, para a contadora e para o fornecedor.

**Cenário:** a HBR (**Simples Nacional**, Itajaí-SC) comprou de um fornecedor
**Regime Normal** (ex.: Kamell, ES) e precisa **devolver** a mercadoria. A HBR
emite uma NF-e de **saída, finalidade 4 (devolução)**, CFOP **6202** (devolução de
compra interestadual), destinatário = o fornecedor.

**Princípio que rege tudo:** a devolução existe para **anular todos os efeitos da
operação original, inclusive os tributários**. Por isso a nota de devolução
**reproduz** os impostos da nota de compra, para o fornecedor **recuperar
(estornar)** o que pagou. Repare: os impostos que aparecem são **do fornecedor
voltando** — a HBR (Simples) não se credita de nada (vedação do art. 24 da LC
123/2006).

> ⚠️ **Reproduzir os ELEMENTOS ≠ usar os mesmos CAMPOS.** A regra é reproduzir os
> **valores** (base, alíquota, imposto) para anular a operação — **não** os mesmos
> campos do XML. **Onde** cada imposto é lançado depende do que o **regime da HBR
> permite**: ela **pode** destacar o ICMS (via CSOSN 900), mas **não pode** destacar
> o IPI no campo próprio (não é contribuinte de IPI) — por isso o IPI vai no
> `vIPIDevol`. Fonte literal: *"a devolução deve reproduzir todos os elementos
> constantes da NF anterior, porém isso **não significa reproduzir os mesmos
> campos**"*.

---

## ICMS — destacado no campo próprio ✅

- Vai **destacado** na nota: **base = vProd − vDesc**, mesma **alíquota** e mesmo
  **valor** da nota original (ex.: base 2.147,74 · ICMS 85,91 · 4%).
- Código: **CSOSN 900** (grupo ICMSSN900) — é o único código que faz o ICMS
  **aparecer na DANFE** de um emitente do Simples.
- **Por quê:** assim o fornecedor registra a devolução no livro de Entradas e
  **estorna o ICMS** que debitou na venda original.
- Base legal: princípio da devolução (RICMS); **SEFAZ-SC Consulta 69/2018**;
  Respostas à Consulta da SEFAZ-SP (devolução Simples com CSOSN 900).

## IPI — no grupo `impostoDevol` (vIPIDevol), NÃO no campo "Valor do IPI" ✅

Este é o ponto que mais confunde, mas está **certo**:

- O Simples **não é contribuinte de IPI** → **não pode** preencher os campos de
  IPI da nota ("Valor do IPI", "Alíq. IPI" no produto). Esses campos são de quem
  **destaca** IPI (indústria/Regime Normal).
- Para o IPI **voltar** numa devolução de não-contribuinte, a SEFAZ criou um grupo
  exclusivo (**NT 2016.002**): o **`impostoDevol` / `vIPIDevol`**. É onde o IPI da
  devolução fica (ex.: R$ 209,40).
- **Por regra da NF-e, o `vIPIDevol` NÃO imprime** no campo "Valor Total do IPI"
  nem nas colunas de IPI do produto → esses campos saem **0,00**. Ele **entra no
  total da nota** (regra W16-10) e é **informado nos dados adicionais**.
- **Onde o fornecedor lê:** no **XML** (tag `vIPIDevol`) + nos dados adicionais —
  não no campo visual da DANFE.
- **Prova de que está conforme:** a **SEFAZ autoriza** a nota (cStat 100). Se o
  IPI estivesse no lugar errado, ela **rejeitaria**.

> O sistema antigo mostrava o IPI no campo porque estava configurado em **Lucro
> Presumido** (Regime Normal). Como **Simples**, o correto é o `vIPIDevol`.

## Dados adicionais (infCpl)

Saem, em ordem: referência à nota de origem (nº/série/data) → chave da nota de
origem → valor do ICMS → valor do IPI devolvido → **declaração obrigatória do
Simples**. A frase *"Não gera direito a crédito fiscal de IPI"* é **omitida na
devolução**: ela é do **art. 60 da Res. CGSN 140/2018** (contexto de **venda** para
comercialização) e **contradiria** o `vIPIDevol` (que é o estorno do IPI do
fornecedor). Fica só a declaração obrigatória (art. 26 da LC 123/2006).

## Referência à nota de origem (VC02-14)

A chave da nota de compra vai em `referenced_documents` (cabeçalho) **e** por item
(`det/DFeReferenciado` = chave + nº do item na nota de compra). A **regra VC02-14
(NT 2025.002)** exige a referência **por item** em **homologação desde 01/07/2026**
e em **produção a partir de 01/09/2026** — a Contora roteia automaticamente por
ambiente. Enviamos os dois níveis; a API grava o que a SEFAZ aceita em cada data.

## Espelho / conferência

O botão **"Gerar espelho"** emite a nota **de verdade em homologação** na SEFAZ e
traz a **DANFE oficial** (com chave e protocolo, marcada **SEM VALOR FISCAL**),
baixada com nome padronizado (`Devolução <nº> - Referente NF <origem> -
<Destinatário>.pdf`). É o documento de conferência para enviar ao fornecedor
antes de emitir em **produção**.

---

### Resumo de uma linha

Na devolução do Simples: **ICMS destacado** (CSOSN 900, campo próprio) + **IPI no
`vIPIDevol`** (não no campo de IPI, mas dentro do total e nos dados adicionais) —
tudo **reproduzindo a nota de compra** para o **fornecedor estornar**. É o padrão,
e a SEFAZ autoriza.

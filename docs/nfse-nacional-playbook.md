# NFS-e Padrão Nacional — Playbook de Especialista (MarineFlow/HBR)

**Atualizado:** 15/08/2026 · **Escopo:** emissão via Contora (padrão nacional), Itajaí/SC (IBGE 4208203), Simples Nacional CRT=1/opSimpNac=3 · **Base oficial:** Anexo I v1.01 (09/02/2026, 428 regras da DPS) + Anexo II v1.01 (58 regras de eventos)

> **Como usar:** apareceu um código E-xxxx? Procure na tabela da seção 4. Não está lá?
> Consulte os catálogos brutos oficiais em `docs/nfse-nacional/` (`rn_dps.tsv` = os 428
> códigos da DPS, `rn_eventos.tsv` = eventos, `rn_recepcao.tsv` = recepção). Antes de
> emitir algo novo, releia a seção 2 (regras de ouro) e a seção 5 (checklist).

---

## 1. Os dois incidentes que este sistema JÁ viveu (decorados)

### E0116 — "A IM deve ser informada" (13-14/08/2026)

**Sintoma:** rejeição E0116 dizendo que a IM não foi informada — **com a tag `<IM>` presente
no XML transmitido**.

**Causa raiz:** o matcher do CNC (Cadastro Nacional de Contribuintes NFS-e) compara
**Município + CNPJ + IM como STRING LITERAL**. O CNC de Itajaí guarda a IM da HBR como
`000000000352217` (15 posições, zeros à esquerda); o cadastro na Contora tinha `352217`.
Para o Ambiente Nacional, são identificadores DIFERENTES → ele "não encontra" o registro e
devolve E0116 com a mensagem enganosa de IM ausente.

**Resolução:** IM no cadastro do provedor na grafia EXATA do CNC (byte a byte, nunca
normalizar/trimar/parseInt). A Contora corrigiu o cadastro em 14/08; nossa migration
`20260815100000` alinhou o registro local; o `nfse_health` agora acusa IM fora do formato
de 15 posições.

**Regra permanente:** a IM **NÃO vai no payload da nota** (campo ignorado pela Contora — a
fonte é `settings.municipal_registration` da EMPRESA no provedor). O builder nunca a envia
e há teste travando isso.

### E0121 — "Nome do prestador não deve ser informado" (14/08/2026)

**Sintoma:** resolvida a E0116, a Sefin avançou para E0121.

**Causa raiz:** com `tpEmit=1` (o prestador emite a própria DPS), o grupo `prest` leva
**SOMENTE CNPJ + IM (quando o CNC exige) + regTrib**. Razão social (`xNome`) → E0121;
endereço do prestador → E0128. A Sefin busca os dados cadastrais no CNC/RFB. O gerador da
Contora enviava `xNome` junto — corrigido do lado deles.

**Resultado final do incidente:** NFS-e **autorizada** em homologação pelo nosso pipeline
(RPS 6 → NFS-e nacional nº 2, artefatos `xml_nfse` 9,8KB + `pdf_nfse` 27KB validados).

### Bônus do mesmo incidente — 3 pegadinhas de contrato da Contora

1. **Artefatos da família NFS-e têm nomes próprios:** `xml_rps`, `xml_nfse`, `pdf_nfse`
   (NÃO `xml_authorized`/`pdf_danfe` da NF-e). Procurar pelos nomes da NF-e = download 404
   e arquivamento legal falhando em silêncio. Corrigido em `handleArtifact`,
   `archiveArtifacts` e `fiscal-email`.
2. **RPS ≠ número da NFS-e:** o `number` que reservamos é o **RPS** (numeração nossa, do
   canal API). O número que vale é o **nacional** (`nfse_number`/`display_number`), gerado
   pela Sefin na autorização. A UI mostra os dois ("NFS-e nº X · RPS n/s").
3. **CNC de produção ≠ CNC de homologação:** em 14/08 o registro da HBR existia SÓ em
   homologação. **Antes da 1ª NFS-e de produção, pedir à Contora que reconsulte o CNC de
   produção** (o `nfse_health` avisa até a 1ª autorizada real). Nunca desligar a flag do
   CNC nem mudar a IM para "contornar" — isso só alterna entre E0116 e E0120.

---

## 2. Regras de ouro (da pesquisa oficial + campo)

1. CNC — regra que resolve metade dos chamados: o matcher é Município + CNPJ + IM como STRING EXATA (tipicamente 15 posições com zeros à esquerda: '000000000352217' ≠ '352217'). Nunca normalizar, trimar ou parseInt a IM no integrador; copiar do CNC byte a byte. Divergência → E0116; IM inativa → E0124; sem autorização → E0119.
2. IM é campo CONDICIONAL POR MUNICÍPIO, nunca fixo: existe registro complementar no CNC → obrigatória e exata (E0116); não existe → proibida (E0120); MEI é exceção na competência. Homologação tem CNC próprio possivelmente dessincronizado da produção.
3. tpEmit=1 (prestador emite): grupo prest leva SOMENTE CNPJ/CPF + IM (condicional) + regTrib. xNome → E0121; endereço → E0128. Dados cadastrais saem do CNC/RFB, não da DPS. xNome/endereço do prestador só com tpEmit=2/3 (ainda não habilitado na Sefin Nacional — E9996).
4. Matriz da alíquota (pAliq) = f(opSimpNac × regApTribSN × tpRetISSQN × convênio do município de incidência): MEI nunca (E0600); ME/EPP no SN sem retenção → proibida (E0625/E0631); ME/EPP no SN com retenção → obrigatória, alíquota EFETIVA do mês anterior via PGDAS, mínimo 1,8% (E0621/E0628); ME/EPP fora do SN ou não optante com convênio ativo → proibida, vale a parametrização municipal (E0635/E0617); município sem convênio ativo → obrigatória (E0619/E0640). Teto 5% (E0595), piso efetivo 2% (E0429).
5. Grupo totTrib (Lei 12.741) por regime: MEI não informa nada (E0710); ME/EPP usa pTotTribSN e NUNCA indTotTrib (E0712); não optante não usa campos do SN (E0713).
6. Toda validação cadastral/tributária é pela VIGÊNCIA NA dCompet, não na data do envio: registro CNC, situação no Simples (E0160), cTribNac (E0310), alíquotas e convênio (E0016/E0023). Notas retroativas que cruzam data de opção/exclusão do Simples quebram.
7. cTribNac tem 6 dígitos (item+subitem+desdobro da lista nacional: 14.01 → 140101). Mandar os 4 dígitos da LC 116 é o erro de payload mais comum (E0310/E0312).
8. Três identificadores distintos, persistir os três: nDPS/série (do contribuinte), número nacional nNFSe (gerado pela Sefin, ≠ nDPS) e chave de acesso de 50 dígitos. Consulta, cancelamento, DANFSE e distribuição operam SEMPRE pela chave.
9. Id da DPS (45 posições) é concatenação exata com zero-padding: 'DPS'+cLocEmi(7)+tpInsc(1)+inscrição(14, CPF com 000)+série(5)+nDPS(15) — divergência → E0004. É a chave de idempotência: GET/HEAD /dps/{id} recupera a NFS-e após timeout.
10. Timeout ≠ falha: tratar como estado desconhecido e CONSULTAR /dps/{id} antes de qualquer retry (evita E0014/409 e nota em dobro). Contador de nDPS persistente e atômico; série exclusiva por canal — API usa 00001-49999 (E0010/GW1992), nunca compartilhar numeração com portal web.
11. Prestador ≠ tomador ≠ intermediário: tomador igual ao prestador → E0202; intermediário igual → E0262. Sem tomador identificável, OMITIR o grupo toma (é 0-1) — nunca duplicar o próprio documento. Bloquear no app antes do envio.
12. Camadas de erro com fluxo próprio: E12xx = transporte (certificado, gzip/base64, XSD) vem antes de tudo; E0xxx = negócio da DPS; E1260-E1638 = ADN (municípios com sistema próprio); E08xx/E18xx-E20xx = eventos. Erros de negócio chegam como HTTP 400 com ARRAY de {codigo, descricao} — parsear e tratar TODOS, pode vir mais de um por envio.
13. Autenticação é mTLS puro: o certificado ICP-Brasil A1 do emitente É a credencial (sem OAuth). HTTP 403 = infra/certificado/cadeia, não payload. A assinatura XML interna é outra checagem: deve ser do CNPJ (base) do próprio emitente (E0718), com cadeia válida (E0715).
14. Pacote correto: XML UTF-8 sem BOM (E1229), namespace default sem prefixo (E1228), fluxo XML → GZip → Base64 em uma linha (E1225/E1226), validado contra o XSD 1.01 localmente antes do envio (E1235). dhEmi com timezone correto e relógio NTP (E0008).
15. Cancelamento: e101101 direto só DENTRO do prazo parametrizado pelo MUNICÍPIO (não há prazo nacional — E0822; teto de valor E0823). Fora do prazo → e101103 (análise fiscal) e aguardar e105104/e105105. Análise pendente bloqueia substituição (E0068). Evento vai ao ambiente que gerou a nota (E0831), assinado pelo autor (E1991). Nota já cancelada → tratar E0840 como sucesso idempotente.
16. Substituição NÃO é evento: é nova DPS com grupo subst (chSubstda + cMotivo) — a Sefin gera e105102 na original automaticamente. Campos imutáveis por regime (E0060/E0061); nota cancelada não se substitui (E0046).
17. Incidência do ISSQN é CALCULADA pela Sefin (LC 116 art. 3º + tabelas EP/LP por cTribNac) — o integrador só escolhe cLocPrestacao + cTribNac corretos. Águas marítimas = 0000000, exterior = 9999999. Exportação segue a matriz de cenários do Anexo I (E0529/E0530).
18. Produção restrita (sefin.producaorestrita.nfse.gov.br) e produção (sefin.nfse.gov.br) são bases e URLs distintas: CNC e parametrização municipal NÃO são espelhados; nota emitida em produção 'achando que era teste' tem valor fiscal. Externalizar URLs por env var com trava visual e revalidar TUDO em produção no go-live.
19. IBS/CBS (reforma tributária): grupo só com dCompet ≥ 01/01/2026 (E0850), leiaute 1.01+ (E0854), NBS obrigatória (E0322), cClassTrib do Anexo C coerente com CST (E0958/E0959).
20. Descontos e base: vDescIncond REDUZ a base do ISSQN; vDescCond NÃO reduz (só o líquido) — trocar um pelo outro altera imposto. BC = vServ − vDescIncond − dedução/benefício (E0427/E1295); dedução limitada pelo piso efetivo de 2% (E0429) e pela parametrização municipal (E0440). Antídoto geral: consultar GET /parametros_municipais (convênio, serviço, retenções) ANTES de montar a DPS.

---

## 3. Regras operacionais específicas do NOSSO stack

- **Payload Contora (nacional):** só `service` + `taker` + `amounts` (+ series/number).
  `additionalProperties: true` significa que campo extra é ACEITO E IGNORADO — não
  interprete silêncio como suporte.
- **Fluxo NFS-e na Contora:** draft → dispatch (SEM build — build é só NF-e/NFC-e).
  Dispatch é o gatilho; após timeout, `refresh` + `getStatus` ANTES de reenviar (a Contora
  reconcilia a DPS pelo RPS).
- **Simples Nacional (nosso caso):** `total_tax_rate_sn` (pTotTribSN) obrigatório (E0712);
  alíquota de ISS NÃO se informa sem retenção (E0625); com retenção pelo tomador, alíquota
  EFETIVA do mês anterior (mínimo 1,8%).
- **cTribNac:** 6 dígitos (14.01 → `140101`). Cadastro dos serviços herda por VERBO fiscal
  (Configurações → Fiscal → Verbos) com override por serviço.
- **Tomador ≠ prestador** (E0202): o app deve bloquear antes do envio — NF-e de homologação
  aceita destinatário = emitente, NFS-e NÃO.
- **Chave de acesso (50 dígitos):** não vem no `access_key` do status da Contora para NFS-e
  (confirmado 15/08 — veio null com nota autorizada); ela está dentro do `xml_nfse`
  arquivado e na consulta pública. Se precisar dela estruturada, extrair do XML.
- **Cota:** homologação tem franquia separada (100/mês) da produção (500/mês). OS mista =
  2 eventos (NFS-e + NF-e).
- **IBS/CBS:** para optante do Simples, obrigatório só a partir de **01/01/2027**; sem
  rejeição por ausência até lá. Obrigatoriedade do padrão nacional p/ ME-EPP: 01/11/2026.

---

## 4. Catálogo de erros — código → causa → resolução

| Código | Mensagem (resumo) | Causa típica | Resolução |
|---|---|---|---|
| E0001 | Prazo de aceitação da versão do leiaute da DPS expirou | verAplic/leiaute antigo (1.00) após o fim da janela de convivência | Migrar para o leiaute vigente 1.01 (obrigatório para IBS/CBS) |
| E0004 | Id da DPS difere da concatenação dos campos | Id não bate com 'DPS'+cLocEmi(7)+tpInsc(1)+inscrição(14, CPF com 000)+série(5)+nDPS(15) — geralmente zero-padding errado | Recompor o Id com zero-padding exato de cada campo (45 posições) |
| E0006 | Ambiente informado diverge do ambiente de recebimento | tpAmb=2 enviado à produção ou vice-versa | Casar tpAmb com o host (produção: sefin.nfse.gov.br; homologação: sefin.producaorestrita.nfse.gov.br) |
| E0008 | dhEmi deve ser anterior ou igual ao processamento | Relógio adiantado ou timezone errado (emissão 'no futuro') | Sincronizar via NTP e usar TZD correto no ISO (ex.: -03:00) |
| E0010 | Série fora da faixa definida para o tipo de emissor | Faixas por canal: 00001-49999 API/app próprio; 50000-69999 móvel; 70000-79999 web; 80000-89999 transcrição manual; 99999 emissor municipal | Emitir via API sempre com série 00001-49999 (zeros à esquerda no Id); série exclusiva por canal, nunca compartilhar contador |
| E0014 | Duplicidade: série+número+município+CNPJ/CPF já existem em NFS-e gerada | nDPS reutilizado — contador não persistido ou retry após timeout que na verdade autorizou | Consultar GET /dps/{id} e recuperar a NFS-e já gerada; contador atômico; nunca reenviar o mesmo nDPS após timeout sem consultar antes |
| E0015 | dCompet não pode ser posterior a dhEmi (Frente 1) | Data de competência futura; frequentemente fuso: dhEmi em UTC 'volta' um dia em relação à data local | dCompet ≤ data de dhEmi; derivar dCompet da data local da prestação, dhEmi com TZD correto |
| E0016 | ATENÇÃO — frentes divergem: F1 = dCompet anterior à ativação do convênio do município; F2 = dCompet posterior à emissão | Ou competência antes da adesão do município ao sistema nacional (exceção MEI), ou competência futura — conferir a mensagem literal retornada pela API | Se convênio: dCompet ≥ data de adesão (notas antigas vão pelo sistema municipal legado). Se futura: dCompet ≤ dhEmi |
| E0018 | dCompet anterior à inscrição do CNPJ | Competência antes da abertura da empresa | Corrigir dCompet |
| E0023 | dCompet deve ser ≥ data do indicador municipal registrada no CNC (ativação do convênio) | Retroatividade além da ativação do convênio do município (exceção para MEI) | Consultar GET /parametros_municipais/{codMun}/convenio e usar dCompet ≥ ativação; notas anteriores ficam no sistema municipal legado |
| E0029 | Motivo da emissão não pode ser preenchido pelo prestador | cMotivoEmis enviado com tpEmit=1 | cMotivoEmis é exclusivo de emissão por tomador/intermediário; remover |
| E0037 | Município emissor inexistente no cadastro de convênio | cLocEmi de município que não aderiu, ou código IBGE errado | Conferir código IBGE de 7 dígitos e adesão do município no painel nacional |
| E0038 | Convênio do município emissor não está ATIVO | Município aderiu mas convênio suspenso/inativo | Emitir pelo sistema municipal; acompanhar situação do convênio |
| E0039 | Município não parametrizado para os emissores públicos nacionais | Município conveniado (compartilha com o ADN) mas emite por sistema próprio, ou sem opção pelos emissores nacionais | Emitir no sistema próprio do município; a Sefin Nacional não aceita DPS para ele — conferir parâmetros do convênio |
| E0041 | Município emissor não corresponde ao município do MEI | MEI emitindo por município diferente do domicílio no CNPJ | cLocEmi = município do cadastro CNPJ do MEI |
| E0042 | Chave de NFS-e a ser substituída é inválida | chSubstda com formato/DV errado (chave tem 50 dígitos) | Usar a chave de acesso nacional completa da NFS-e original |
| E0044 | NFS-e não existe na base do autorizador nacional | Chave referenciada inexistente (ambiente errado ou chave montada à mão) | Consultar a NFS-e antes; conferir produção vs homologação |
| E0046 | NFS-e cancelada não pode ser substituída | Tentativa de substituir nota já cancelada | Emitir DPS nova normal em vez de substituição |
| E0050 | Substituição fora do prazo do município | Prazo de substituição parametrizado pelo município expirou | Verificar prazo na parametrização municipal; após o prazo, tratar via análise fiscal/administração municipal |
| E0060 | Campos imutáveis na substituição (não optante) | Substituição alterando dCompet, subitem, cTribMun ou local da prestação com opSimpNac=1 | Substituição só corrige os demais campos; para mudar esses, cancelar e emitir nova |
| E0061 | Campos imutáveis na substituição (MEI/ME-EPP) | Substituição alterando tomador, dCompet ou vServ com opSimpNac=2/3 | Cancelar e emitir nova nota |
| E0068 | Não é possível substituir: há Solicitação de Análise Fiscal para Cancelamento (e101103) pendente | Substituição tentada com análise fiscal de cancelamento aguardando resposta na mesma nota | Aguardar decisão do fisco municipal (e105104 deferido / e105105 indeferido) antes de enviar a DPS substituta |
| E0080 | CNPJ do prestador inválido | Dígito verificador errado ou máscara no campo | Enviar 14 dígitos numéricos válidos, sem máscara |
| E0082 | CNPJ do prestador não encontrado no cadastro na competência | CNPJ baixado/inexistente na data de competência | Conferir situação cadastral na RFB para a competência informada |
| E0084 | CNPJ do prestador sem estabelecimento no município emissor | cLocEmi não corresponde a estabelecimento do CNPJ na competência — clássico: CNPJ da matriz com município da filial, ou mudança de endereço não refletida na RFB | Usar o CNPJ do estabelecimento (raiz+ordem) correto para o município, ou corrigir cLocEmi; conferir cartão CNPJ |
| E0096 | CPF do prestador inválido | DV errado | Corrigir CPF (11 dígitos) |
| E0099 | CPF do prestador sem domicílio no município emissor (CNC) | Combinação cLocEmi+CPF+IM não existe no CNC | Pessoa física precisa estar registrada no CNC do município (cadastro municipal) para emitir |
| E0115 | cNaoNIF=0 do prestador não permitido na Sefin Nacional | Motivo de não informação do NIF com valor 0 | Usar valor 1 ou 2 conforme o caso |
| E0116 | A IM deve ser informada para o emitente prestador, conforme CNC do município emissor | Município tem registro complementar no CNC exigindo IM e ela foi omitida OU não casa EXATAMENTE com o valor gravado — matcher é município+CNPJ+IM como string literal, zeros à esquerda contam (caso real Itajaí/SC: cadastro '352217' vs CNC '000000000352217', 15 posições); letras/máscara também quebram | Obter o valor literal da IM no CNC (painel municipal/prefeitura) e enviar byte a byte, sem trim/parseInt; gravar assim no cadastro local; exceção: MEI na competência; homologação pode ter CNC dessincronizado — validar em produção; alternativa: pedir à prefeitura para corrigir o CNC |
| E0119 | IM do prestador não autorizada a emitir NFS-e (CNC) | IM existe no CNC mas sem flag de autorização de emissão | Regularizar autorização junto à administração tributária municipal |
| E0120 | IM do prestador não deve ser informada (município sem registro complementar no CNC) | Espelho do E0116: IM enviada mas o município não tem (ou não migrou) informações complementares no CNC, ou valida pela base RFB | Omitir a tag IM e identificar só por CNPJ/CPF+cLocEmi; tratar IM como campo condicional por município; se o contribuinte deveria constar, acionar a prefeitura para registrar no CNC |
| E0121 | xNome do prestador não deve ser informado quando o emitente é o próprio prestador (tpEmit=1) | Payload envia razão social (e, por extensão, endereço/fone/email) no grupo prest com tpEmit=1 — os dados cadastrais saem do CNC/RFB, não da DPS | Com tpEmit=1, prest mínimo: CNPJ/CPF + IM (se exigida) + regTrib; remover xNome (senão E0121) e endereço (senão E0128); se o serializer preenche por reflexo, filtrar por tpEmit |
| E0122 | xNome do prestador obrigatório quando emitente não é o prestador | Emissão por tomador/intermediário sem razão social do prestador | Informar xNome do prestador quando tpEmit=2/3 |
| E0124 | IM inativa no CNC na data de competência | Inscrição municipal baixada/suspensa na competência | Regularizar a IM na prefeitura ou usar competência em que estava ativa |
| E0125 | Endereço nacional do prestador obrigatório (emissão por tomador/intermediário) | tpEmit=2/3 sem endereço do prestador | Informar grupo end do prestador |
| E0128 | Endereço do prestador não deve ser informado quando ele é o emitente | tpEmit=1 com grupo end no prest (mesma classe do E0121) | Remover endereço do prest quando tpEmit=1 |
| E0130 | Município do endereço do prestador inexistente (IBGE) | cMun com código inválido | Usar código IBGE de 7 dígitos da tabela do Anexo A |
| E0132 | Município do endereço do prestador não corresponde ao cadastro (CNPJ) | Endereço enviado diverge do registrado na RFB para a competência | Alinhar endereço com o cadastro CNPJ vigente |
| E0138 | CEP não pertence ao município do prestador | CEP inválido ou de outro município | Validar CEP×município (base Correios) |
| E0160 | opSimpNac diverge do cadastro do Simples Nacional no mês de competência | Situação declarada não confere com o cadastro oficial do SN NO MÊS de dCompet — exclusão/opção recente, exclusão retroativa, cadastro local (CRT) desatualizado, ou CNPJ que nem consta no cadastro | Consultar o portal do Simples para o mês de dCompet e alinhar opSimpNac (1=não optante, 2=MEI, 3=ME/EPP); CNPJ fora do cadastro → informar 1; atenção a notas retroativas que cruzam data de opção/exclusão |
| E0162 | Não optante e MEI não preenchem regime de apuração (regApTribSN) | regApTribSN enviado com opSimpNac=1 ou 2 | regApTribSN só com opSimpNac=3 |
| E0166 | regApTribSN obrigatório para ME/EPP | opSimpNac=3 sem indicar regime de apuração | Informar regApTribSN (1=apura pelo SN, 2/3=fora do SN); Simples típico usa 1 |
| E0172 | regEspTrib deve ser 0 quando tribISSQN ≠ 1 | Regime especial informado em nota de imunidade/exportação/não incidência | regEspTrib=0 nesses casos |
| E0174 | MEI: regEspTrib deve ser 0 | Regime especial com opSimpNac=2 | regEspTrib=0 para MEI |
| E0175 | ME/EPP apurando pelo SN: regEspTrib deve ser 0 | opSimpNac=3 + regApTribSN=1 com regime especial | regEspTrib=0 |
| E0187 | Grupo do tomador obrigatório para o indicador de operação | Tomador omitido em operação que o exige | Informar grupo toma |
| E0188 | CNPJ do tomador inválido | DV errado/máscara | 14 dígitos válidos |
| E0190 | CNPJ do tomador não encontrado no cadastro | CNPJ inexistente/baixado | Conferir na RFB; tomador estrangeiro usa NIF |
| E0202 | Prestador não pode ser igual ao tomador | Auto-emissão: mesmo CNPJ/CPF nos dois grupos — teste 'contra si mesmo', cliente cadastrado com o CNPJ da própria empresa, ou nota interna | Omitir o grupo toma (é 0-1) ou usar o tomador real; bloquear no app (tomador.doc != prestador.doc) antes do envio; testes em produção restrita com documento de terceiro |
| E0204 | Retenção do ISSQN indicada sem tomador identificado | tpRetISSQN=2 sem CNPJ/CPF do tomador | Identificar o tomador ou mudar para tpRetISSQN=1 |
| E0206 | CPF do tomador inválido | DV errado | Corrigir CPF |
| E0207 | CPF do tomador não encontrado no cadastro | CPF inexistente/irregular na RFB | Conferir CPF; se irregular, corrigir com o cliente |
| E0233 | Nome do tomador obrigatório quando NIF preenchido | Tomador estrangeiro sem xNome | Informar nome |
| E0234 | Endereço do tomador obrigatório para o indicador de operação ou incidência no domicílio do tomador | Serviço com incidência no local do tomador (exceções LC 116) sem endereço | Informar endereço completo do tomador |
| E0235 | Endereço nacional do tomador obrigatório quando identificado por CNPJ | Tomador PJ sem grupo end | Sempre enviar endereço para tomador CNPJ |
| E0238 | Município do endereço do tomador inexistente (IBGE) | cMun inválido | Código IBGE de 7 dígitos |
| E0240 | CEP do tomador não existe ou não pertence ao município | CEP × cMun incoerentes: cadastro de cliente com CEP genérico, city_code IBGE errado | Validar DV de CPF/CNPJ e o par CEP↔código IBGE na ENTRADA do cadastro, não na emissão; tomador estrangeiro usa o grupo próprio, nunca município fake |
| E0262 | Prestador não pode ser igual ao intermediário | Mesmo documento em prest e interm | Remover o intermediário |
| E0302 | Código do local da prestação inexistente (IBGE) | cLocPrestacao inválido | Tabela IBGE do Anexo A (ou 0000000 águas marítimas, com restrições; 9999999 exterior) |
| E0310 | Código de tributação nacional (cTribNac) inexistente na lista de serviços nacional | Clássico: item LC 116 com 4 dígitos ('1401'/'14.01') em vez dos 6 da lista nacional (item+subitem+desdobro: '140101'); ou código fora da versão vigente na dCompet | Mapear serviço→código de 6 dígitos do Anexo B; validar contra GET /parametros_municipais/{codMun}/{codServico} na competência; manter tabela local sincronizada; testar manualmente no Emissor Nacional em caso de dúvida |
| E0312 | cTribNac não administrado pelo município de incidência na competência | Município não parametrizou aquele subitem | Conferir parametrização municipal; escolher código equivalente administrado ou acionar a prefeitura; se o código existe e ainda rejeita, abrir chamado no suporte do sistema nacional |
| E0314 | cTribMun inexistente ou não administrado pelo município de incidência | Código complementar municipal de outro município, omitido quando exigido, ou enviado quando não parametrizado | Verificar na parametrização municipal se cTribMun é exigido e qual tabela vige; tornar o campo condicional por município no cadastro de serviços |
| E0315 | cTribMun não pode ser 000 | Placeholder enviado | Omitir a tag em vez de enviar 000 |
| E0316 | Código NBS inexistente | cNBS fora da tabela NBS | Anexo B, aba NBS2 |
| E0318 | NBS obrigatória para exportação de serviço | tribISSQN=3 sem cNBS | Informar item NBS |
| E0322 | NBS obrigatória quando há informações de IBS/CBS | Grupo IBSCBS sem cNBS | Informar NBS sempre que declarar IBS/CBS (obrigatório desde 2026) |
| E0330 | Informações de comércio exterior obrigatórias para exportação | tribISSQN=3 sem grupo comExt | Preencher comExt (modo de prestação, país, mecanismos de apoio) |
| E0370 | Grupo obra obrigatório para os subitens de construção civil | cTribNac 07.02.xx/07.04/07.05/07.17/07.19/14.14.03-04 sem grupo obra | Informar obra (CIB ou endereço da obra) |
| E0372 | Grupo obra não permitido para o cTribNac informado | Grupo obra enviado para serviço fora da lista de construção | Remover grupo obra |
| E0380 | CEP da obra deve corresponder ao município do local da prestação | CEP da obra de outro município | Alinhar CEP da obra com cLocPrestacao |
| E0390 | Grupo Atividade/Evento obrigatório para item 12 da lista | Serviço de diversões/eventos sem grupo atvEvento | Informar o grupo |
| E0420 | Documento de referência obrigatório na emissão por tomador/intermediário | tpEmit=2/3 sem docRef | Informar documento de referência (contrato, invoice) |
| E0425 | Valor recebido não pode ser menor que o valor do serviço | vReceb < vServ em emissão pelo intermediário | Corrigir valores |
| E0427 | vServ deve ser ≥ soma de desconto incondicionado + deduções + benefício municipal | Somatório de reduções maior que o serviço | Revalidar aritmética antes do envio |
| E0429 | Redução de BC não pode resultar em alíquota efetiva menor que 2% | Deduções/reduções derrubam a carga abaixo do piso constitucional (exceto subitens listados: transporte, construção etc.) | Limitar dedução para manter ISSQN efetivo ≥ 2% do serviço |
| E0431 | Desconto incondicionado deve ser < vServ e > 0 | vDescIncond zerado ou ≥ serviço | Omitir a tag se não houver desconto |
| E0436 | Dedução/redução não permitida para prestador MEI | Grupo dedução com opSimpNac=2 | MEI não usa dedução de BC |
| E0440 | Tipo de dedução/redução não permitido pelo município de incidência | Município não parametrizou aquele tipo para o código de serviço | Conferir parametrização do serviço no município |
| E0529 | Cenário é operação tributável; não pode declarar exportação | tribISSQN=3 mas a combinação local/tomador/resultado caracteriza operação interna | Seguir a matriz de cenários de exportação do Anexo I; ajustar tribISSQN=1 |
| E0530 | Cenário é exportação; não pode declarar operação tributável | Inverso do E0529 | Declarar tribISSQN=3 conforme a matriz de cenários |
| E0532 | Serviço 99.01.01 exige tribISSQN=4 (não incidência) | Código genérico sem ISSQN/ICMS com tributação informada | tribISSQN=4 para 99.01.01 |
| E0540 | Não há incidência: código não é incidente no município | tribISSQN=1 mas o município parametrizou o serviço como não incidente | Usar tribISSQN=4 ou revisar o código de serviço |
| E0580 | Retenção não permitida com imunidade/exportação/não incidência | tpRetISSQN=2/3 com tribISSQN=2/3/4 | tpRetISSQN=1 nesses casos |
| E0583 | Retenção do ISSQN não permitida para prestador MEI | tpRetISSQN=2/3 com prestador MEI na competência | MEI recolhe pelo DAS; tpRetISSQN=1 |
| E0592 | Tipo de imunidade obrigatório (e exclusivo) para tribISSQN=2 | tpImunidade ausente ou informado sem imunidade | Informar tpImunidade só quando tribISSQN=2 |
| E0595 | Alíquota não pode ser superior a 5% | pAliq acima do teto da LC 116 | Corrigir alíquota (2% a 5%) |
| E0600 | MEI não pode informar alíquota | pAliq com opSimpNac=2 | Omitir pAliq para MEI |
| E0602 | Alíquota não permitida com imunidade/exportação/não incidência | pAliq com tribISSQN ≠ 1 | Omitir pAliq |
| E0604 | Alíquota não permitida com regime especial de tributação | pAliq com regEspTrib ≠ 0 | Omitir pAliq |
| E0617 | Alíquota não permitida para não optante com convênio do município de incidência ATIVO | opSimpNac=1 + município conveniado: a alíquota vigente vem da parametrização municipal por cTribNac, não da DPS | Omitir pAliq e deixar a Sefin aplicar a alíquota parametrizada; só informar em município sem convênio ativo (E0619) |
| E0619 | Alíquota obrigatória para não optante com município NÃO ativo | opSimpNac=1 + convênio inativo sem pAliq | Informar pAliq (2-5%) |
| E0621 | Alíquota obrigatória para ME/EPP no SN com retenção (mínimo 1,8%) | opSimpNac=3 + regApTribSN=1 + tpRetISSQN=2/3 sem pAliq | Informar a alíquota EFETIVA do SN do mês anterior (PGDAS: valor ISS ÷ faturamento da atividade; LC 123 art. 21 §4º), ≥ 1,8% |
| E0625 | Alíquota não permitida para ME/EPP no SN sem retenção (município ativo) | opSimpNac=3 + regApTribSN=1 + tpRetISSQN=1 + convênio ativo: o ISS é recolhido no DAS, a DPS não leva pAliq — cenário padrão do Simples sem retenção | Omitir pAliq. Com retenção (tpRetISSQN=2/3), aí sim informar a alíquota efetiva do mês anterior (ver E0621) |
| E0628 | Alíquota obrigatória: ME/EPP no SN com retenção e município NÃO ativo | Variante do E0621 com convênio inativo | Informar pAliq ≥ 1,8% |
| E0631 | Alíquota não permitida: ME/EPP no SN sem retenção e município NÃO ativo | Variante do E0625 | Omitir pAliq |
| E0635 | Alíquota não permitida: ME/EPP fora do SN (regApTribSN=2/3) com município ativo | ME/EPP que estourou sublimite (ISSQN pela legislação municipal) em município conveniado: vale a alíquota parametrizada pelo próprio fisco | Omitir pAliq quando regApTribSN=2/3 e convênio ativo; conferir a alíquota aplicada no retorno da NFS-e; ajuste de alíquota é na parametrização municipal |
| E0640 | Alíquota obrigatória: ME/EPP fora do SN com município NÃO ativo | Sem parametrização disponível, a DPS precisa trazer a alíquota | Informar pAliq |
| E0650 | Importação de serviço pelo tomador exige retenção pelo tomador | Importação sem tpRetISSQN=2 | tpRetISSQN=2 em importação pelo tomador |
| E0672 | Retenção não permitida: tomador emitente estabelecido em município ≠ incidência | Tomador emite e retém mas não está no município de incidência | Rever local de incidência ou retenção |
| E0675 | Tributos federais não permitidos para emitente pessoa física | Grupo tribFed com emitente CPF | Omitir tribFed |
| E0676 | Tributos federais não permitidos para MEI | Grupo tribFed com opSimpNac=2 | Omitir tribFed |
| E0694 | vPis ≠ BC × alíquota Pis | Arredondamento divergente do cálculo do sistema | vPis = round(vBCPisCofins × pAliqPis, 2) exatamente |
| E0696 | vCofins ≠ BC × alíquota Cofins | Mesma classe do E0694 | Recalcular com arredondamento a 2 casas |
| E0699 | vRetCP deve ser > 0 e < vServ | Valor de retenção de CP (INSS) inválido | Omitir a tag se não houver retenção |
| E0710 | MEI: pTotTribSN nunca pode ser informado | Grupo totTrib com percentual para MEI | MEI não informa totTrib |
| E0712 | ME/EPP: indTotTrib nunca pode ser informado | opSimpNac=3 com o choice errado do grupo totTrib — ME/EPP deve declarar o percentual aproximado dos tributos do SN, não o indicador; ou grupo omitido/na variante de não-optante | Trocar indTotTrib por pTotTribSN (percentual aproximado da alíquota efetiva do SN/DAS, ex.: 6,00; aceita 0.00 quando aplicável) ou usar vTotTrib/pTotTrib; validar contra o XSD antes de transmitir |
| E0713 | Não optante: indTotTrib e pTotTribSN não podem ser informados | opSimpNac=1 com campos de total de tributos do SN | Para não optante usar vTotTrib/pTotTrib ou indTotTrib=0 conforme o leiaute |
| E0714 | Arquivo com erro na assinatura | Digest/SignatureValue inválidos: XML alterado após assinar, canonicalização errada | Assinar o infDPS com C14N exclusivo, SHA-256; não reformatar o XML depois de assinado |
| E0715 | Certificado digital da assinatura inválido | Cadeia incompleta no KeyInfo ou certificado vencido/revogado | Assinar com A1 ICP-Brasil válido, incluir X509Certificate |
| E0717 | Assinatura obrigatória no envio via Web Service/API | DPS sem elemento Signature | Assinar sempre que enviar via API (o emissor web assina pelo portal) |
| E0718 | Assinatura deve ser do certificado do emitente da DPS | CNPJ (base) do certificado ≠ CNPJ do emitente: certificado da software house, da matriz para filial de raiz diferente, do contador sem procuração, ou certificado trocado no multi-tenant | Assinar com o e-CNPJ do próprio emitente (raiz deve bater) ou constituir procuração eletrônica; no multi-tenant, amarrar certificado→empresa por CNPJ e validar antes de assinar |
| E0802 | Já existe DF-e com este id no sistema (evento) | Id de pedido de registro de evento duplicado | Gerar id novo conforme a regra de concatenação |
| E0812 | CNPJ do autor do evento ≠ base do CNPJ do certificado | Evento assinado por certificado de terceiro | Assinar com o certificado do autor (mesma base de CNPJ) |
| E0813 | Autor do evento não corresponde ao autor permitido para o tipo | Ex.: tomador tentando cancelar nota do prestador | Conferir a planilha Tipo Eventos (quem pode emitir cada evento) |
| E0822 | Prazo para cancelamento da NFS-e expirou (parametrização municipal) | e101101 após o prazo que o MUNICÍPIO parametrizou — não há prazo nacional único | Usar o evento de Solicitação de Análise Fiscal para Cancelamento (e101103) e aguardar deferimento da prefeitura; consultar a parametrização ANTES de expor o botão de cancelar |
| E0823 | Valor da NFS-e acima do permitido para cancelamento direto | Município parametrizou teto de valor para cancelamento sem análise | Solicitar análise fiscal para cancelamento |
| E0824 | NFS-e sem tomador identificado não pode ser cancelada (parametrização) | Município exige tomador identificado para cancelar | Via análise fiscal / administração municipal |
| E0827 | Cancelamento bloqueado: evento de Tributos Recolhidos vinculado | ISSQN da nota já recolhido | Tratar com a administração tributária municipal |
| E0831 | Evento deve ser enviado ao ambiente que gerou a NFS-e | Cancelamento de nota da Sefin Nacional enviado ao sistema municipal (ou vice-versa) | Notas da Sefin Nacional cancelam na Sefin Nacional; notas municipais no sistema do município |
| E0840 | Cancelamento não recepcionado: outro evento já vinculado impede | Nota já cancelada, já substituída, bloqueada por ofício, ou com manifestação de confirmação registrada | Consultar GET /nfse/{chave}/eventos para descobrir o impeditivo; se já cancelada, tratar como sucesso idempotente |
| E0845 | Cancelamento por substituição não recepcionado: evento impeditivo vinculado | Mesma classe do E0840, para e105102 | Consultar os eventos da nota |
| E0848 | Solicitação de análise fiscal não recepcionada: evento impeditivo | Já existe solicitação pendente ou nota cancelada | Consultar eventos |
| E0850 | IBS/CBS só a partir da competência 01/01/2026 | Grupo IBSCBS com dCompet anterior a 2026 | Só declarar IBS/CBS para competências ≥ 01/01/2026 |
| E0853 | Deferimento sem solicitação de análise fiscal pendente | (Fisco) deferimento sem a solicitação prévia | Sequência: solicitação → deferido (e105104) / indeferido (e105105) |
| E0854 | IBS/CBS exige DPS versão 1.01+ | Grupo IBSCBS em leiaute 1.00 | Migrar para o leiaute 1.01 |
| E0958 | cClassTrib IBS/CBS incorreto para prestação de serviços | Código de classificação tributária fora da tabela para serviços | Usar cClassTrib válido do Anexo C |
| E0959 | cClassTrib não pertence ao grupo CST indicado | Combinação CST × cClassTrib inválida | Conferir a matriz CST×cClassTrib da RTC |
| E1200 | Certificado de Transmissão inválido | Certificado cliente ausente no handshake mTLS, versão ≠3, certificado de AC (Basic Constraint true) ou sem KeyUsage 'Autenticação Cliente' | Usar e-CNPJ/e-CPF A1 ICP-Brasil de entidade final com clientAuth; conferir se o certificado está sendo enviado no TLS |
| E1203 | Certificado de Transmissão expirado | Validade vencida | Renovar o A1 e atualizar o .pfx no emissor |
| E1205 | Erro na cadeia de certificação | AC emissora não cadastrada na RFB, AC revogada ou cadeia incompleta no envio | Enviar a cadeia completa ICP-Brasil (intermediárias) junto com o certificado cliente |
| E1206 | Erro de acesso à LCR | Certificado sem CRL DistributionPoint ou LCR indisponível/inválida | Usar certificado ICP-Brasil padrão; se persistir, aguardar (indisponibilidade da LCR da AC) |
| E1207 | Certificado de Transmissão revogado | Certificado revogado pela AC | Emitir novo certificado |
| E1208 | Certificado difere da ICP-Brasil | Certificado de raiz estrangeira/autoassinado | Somente ICP-Brasil é aceito |
| E1209 | Certificado sem CNPJ ou CPF | Falta a extensão OtherName OID 2.16.76.1.3.3 (não é e-CNPJ/e-CPF) | Usar certificado e-CNPJ/e-CPF padrão ICP-Brasil |
| E1225 | Falha na decodificação da base64 da área de dados | Payload corrompido: base64 com quebras/URL-encode, ou ordem errada (base64 antes do gzip) | Fluxo correto: XML → GZip → Base64 (uma linha); validar decodificação localmente antes de enviar |
| E1226 | Estrutura descompactada mal formada | XML truncado ou gzip inválido após decodificação | Regenerar o pacote; testar round-trip local gzip/gunzip |
| E1228 | Uso de prefixo de namespace não permitido | XML com prefixo (ex.: ns1:DPS) em vez de namespace default | Usar xmlns="http://www.sped.fazenda.gov.br/nfse" sem prefixos |
| E1229 | XML não está em UTF-8 | Encoding declarado/real diferente de UTF-8 (ISO-8859-1, BOM) | Serializar em UTF-8 sem BOM |
| E1235 | Falha no esquema XML do DF-e | XML não valida contra o XSD (campo faltante, ordem errada, formato) | Validar localmente contra o pacote XSD v1.01 antes do envio; a resposta costuma indicar o elemento |
| E1242 | Tipo DF-e não tratado pelo Sistema Nacional | Tag raiz errada para o endpoint | Conferir documento vs endpoint (DPS em /nfse, pedRegEvento em /nfse/{chave}/eventos) |
| E1268 | Chave de NFS-e já compartilhada com o ADN | (Municípios com sistema próprio) reenvio de nota já compartilhada | Deduplicar antes do envio ao ADN |
| E1289 | vBC × pAliqAplic não confere com o valor do ISSQN | (ADN) cálculo divergente na NFS-e compartilhada | Recalcular exatamente como o sistema (2 casas) |
| E1295 | BC ≠ vServ − desconto incondicionado − deduções − benefício − reembolsos | (ADN) fórmula da base de cálculo divergente | Aplicar a fórmula oficial da BC |
| E1297 | BC calculada não pode resultar em alíquota efetiva < 2% | (ADN) mesma regra do piso de 2% | Ajustar reduções |
| E1304 | Município emissor difere de quem compartilha com o ADN | (ADN) município enviando nota de outro município | Cada município só compartilha as próprias notas |
| E1506 | Total de tributos retidos não pode ser negativo | Somatório de retenções inconsistente | Revalidar valores |
| E1508 | Valor líquido da NFS-e não pode ser negativo | Retenções+descontos > serviço | Revalidar aritmética do vLiq |
| E1555 | Valor total da NFS-e incorreto | (IBS/CBS) totais não batem com os itens calculados | Seguir as fórmulas de totalização do leiaute 1.01 |
| E1802 | Id do evento difere da concatenação dos campos | Id do evento mal montado (chave+tpEvento+seq) | Recompor conforme o leiaute do pedRegEvento |
| E1805 | Já existe evento com este identificador no ADN | Reenvio do mesmo evento | Idempotência: tratar como já registrado |
| E1831 | NFS-e indicada não existe no ADN | Evento para chave inexistente (ambiente errado, nota ainda não sincronizada) | Confirmar chave e ambiente; aguardar sincronização se nota municipal recém-emitida |
| E1833 | Só um evento de manifestação (confirmação/rejeição) por não emitente | Segunda manifestação do mesmo ator | Para reverter rejeição, usar o evento de Anulação da Rejeição |
| E1843 | Data de emissão do pedido de evento posterior ao recebimento | Relógio adiantado | NTP/timezone |
| E1845 | Ambiente do evento diverge do ambiente de recebimento | tpAmb errado no evento | Casar tpAmb com o endpoint |
| E1944 | Descrição do motivo obrigatória quando tipo do motivo = 9 (Outros) | Cancelamento com cMotivo=9 sem xMotivo (na DPS a variante é E0078 com cMotivo=99) | Preencher xMotivo |
| E1980 | Evento com erro na assinatura | Assinatura XML do pedRegEvento inválida | Mesmo padrão de assinatura da DPS |
| E1991 | Assinatura do evento deve ser do certificado do emitente do pedido | Certificado ≠ autor do evento | Assinar com o e-CNPJ do autor |
| E9996 | Emissão por tomador/intermediário não permitida nesta versão | tpEmit=2/3 enviado — funcionalidade prevista no leiaute mas ainda não habilitada na Sefin Nacional | Somente tpEmit=1 até a liberação do recurso |
| GW1992 | (Gateway/integrador) Série da DPS fora da faixa permitida para o canal de emissão | Mesma regra do E0010 vista pelo gateway: emissão própria/API usa 1-49999; portal/mobile usam outras faixas; série compartilhada entre canais gera conflito e numeração furada | Série exclusiva por canal; persistir o próximo nDPS em transação atômica no banco |
| HTTP 400 | Bad Request com lista de erros de negócio no corpo | Veículo padrão dos códigos Exxxx: JSON de resposta com array de {codigo, descricao, complemento}; também ocorre por JSON de envio malformado ou gzip/base64 inválido | Parsear TODOS os erros do array (pode vir mais de um por envio) e tratar por código; conferir o wrapper JSON (campo dpsXmlGZipB64) |
| HTTP 401 | Unauthorized | Certificado aceito no TLS mas não habilitado/reconhecido para a operação | Verificar se o CNPJ do certificado corresponde ao emitente e se o contribuinte está apto no município |
| HTTP 403 | Forbidden na API sefin.nfse.gov.br / adn.nfse.gov.br (mTLS) | Certificado cliente não enviado, cadeia ICP-Brasil incompleta (falta intermediária no bundle), vencido/revogado, finalidade errada, TLS terminado em proxy que descarta o cert, ou apontando certificado de outro ambiente/empresa — NÃO é erro de payload | Configurar o client TLS com o .pfx A1 do emitente + cadeia completa (raiz+intermediárias); testar handshake com openssl s_client contra o host do ambiente; sem OAuth — o certificado É a credencial |
| HTTP 404 | Not Found em consultas | Chave/id inexistente no ambiente consultado (produção vs homologação) ou rota errada | Conferir ambiente e formato da chave (50 dígitos) / id da DPS |
| HTTP 409 | Duplicidade de DPS (nota já recebida/convertida em NFS-e) | Retry cego após timeout: a primeira transmissão FOI processada e o cliente não recebeu a resposta; reenvio com novo nDPS gera nota em dobro, com o mesmo nDPS gera 409/E0014 | Tratar timeout como estado desconhecido: consultar GET /dps/{id} (reconciliação por chave de negócio) antes de qualquer retry; idempotência: mesmo documento → mesmo nDPS |
| HTTP 422 | Unprocessable Entity (algumas rotas) | Payload sintaticamente válido mas rejeitado semanticamente | Ler o corpo — mesmas estruturas de erro do 400 |
| HTTP 500/503 | Erro/indisponibilidade do Sefin Nacional | Instabilidade do ambiente nacional (frequente em picos) | Retry com backoff exponencial + idempotência via consulta da DPS antes de reenviar (evita E0014) |
| AMB-PROD-RESTRITA | (Padrão operacional) 'Funcionava ontem' / nota de teste virou nota real / erro de cadastro só num ambiente | Produção restrita (sefin.producaorestrita.nfse.gov.br) e produção (sefin.nfse.gov.br) são bases DISTINTAS: nota emitida em produção por engano tem valor fiscal; CNC e parametrização não são espelhados entre ambientes | Externalizar URLs por env var com trava visual/log do ambiente ativo; go-live revalida em PRODUÇÃO: CNC, IM exata, parametrização e certificado; nota real por engano → cancelar dentro do prazo |
| CANC-PRAZO | (Padrão operacional) Cancelamento rejeitado: fora do prazo permitido pelo município | Prazo de cancelamento NÃO é nacional — cada município parametriza; substituição tipicamente limitada (ex.: 180 dias); integrador assume prazo único | Consultar a parametrização municipal ANTES de oferecer o botão de cancelar; fora do prazo → análise fiscal (e101103) ou processo administrativo; nota errada com serviço ocorrido → substituir em vez de cancelar |
| CNAE-PARAM-MUNICIPAL | (Padrão operacional) 'CNAE não habilitado' / item rejeitado apesar de código nacional válido | CNAE/atividade do cadastro mobiliário municipal não contempla o item emitido, ou o município não parametrizou a combinação código×alíquota | Conferir no painel municipal as atividades habilitadas para a IM; atualizar o cadastro mobiliário na prefeitura (ou pedir parametrização); só depois reemitir |
| CONFUSAO-RPS-NFSE | (Padrão operacional) Número exibido não bate com a prefeitura; consultas e cancelamentos falham | Integrador grava o nDPS (numeração própria, análoga ao RPS) como se fosse o número da NFS-e; no padrão nacional há TRÊS identificadores: nDPS/série (do contribuinte), número nacional nNFSe (do fisco) e chave de acesso de 50 dígitos | Persistir os três campos separados e usar SEMPRE a chave de 50 dígitos para consulta, DANFSE, cancelamento e distribuição |

> Código fora desta tabela? `docs/nfse-nacional/rn_dps.tsv` tem TODOS os 428 códigos
> oficiais da DPS com a mensagem literal; `rn_eventos.tsv` cobre cancelamento/substituição/
> manifestação; `rn_recepcao.tsv` a camada de recepção.

---

## 5. Checklist pré-emissão (o que conferir ANTES de culpar o payload)

1. `nfse_health` verde: `public_emission_enabled`, certificado A1 no prazo, cadastro fiscal
   da empresa completo no provedor.
2. IM no cadastro do provedor = grafia EXATA do CNC (15 posições com zeros).
3. Serviços da OS com código fiscal EFETIVO (próprio ou herdado do verbo) — e UM único
   cTribNac por nota.
4. `total_tax_rate_sn` preenchido (Simples) — valor validado pela contadora.
5. Tomador com CPF/CNPJ válido, endereço completo, `city_code` IBGE de 7 dígitos —
   e diferente do prestador.
6. Ambiente conferido (banner de produção); numeração RPS exclusiva do canal API.
7. Primeira produção: CNC de produção confirmado com o provedor.
8. Depois de emitir: guardar RPS + número nacional + chave (do XML); XML/PDF arquivados
   (tipos `xml_nfse`/`pdf_nfse`).

---

## 6. Fontes

- https://www.gov.br/nfse/pt-br/biblioteca/documentacao-tecnica — Fonte primária: Anexo I — LeiautesRN_DPS_NFSe-SNNFSe v1.01 (09/02/2026, 428 códigos de regra de negócio da DPS) e Anexo II — LeiautesRN_Eventos v1.01 (22/01/2026, 58 códigos de eventos), leiaute DPS 1.01, XSDs, Anexos A (municípios IBGE), B (lista de serviços nacional/NBS) e C (cClassTrib IBS/CBS).
- https://sefin.nfse.gov.br — API de PRODUÇÃO da Sefin Nacional (mTLS com certificado ICP-Brasil A1; sem OAuth). Endpoints: POST /nfse, GET /nfse/{chave}, GET/HEAD /dps/{id}, POST/GET /nfse/{chave}/eventos, GET /parametros_municipais/...
- https://sefin.producaorestrita.nfse.gov.br — Homologação (produção restrita). Base DISTINTA da produção: CNC e parametrização municipal não são espelhados — o teste decisivo de E0116/E0120 é sempre em produção.
- https://www.gov.br/nfse/pt-br — Portal oficial do sistema nacional: painel de municípios aderentes, Emissor Nacional (útil para testar manualmente uma combinação de serviço antes de culpar o integrador).
- https://atendimento.tecnospeed.com.br — KB de integrador usada para enriquecer causa/resolução dos códigos (complementada por TOTVS, Nottou, ACBr, eNotas, Nuvem Fiscal, Conta Azul, Sankhya, Senior, CIGAM, Webmania e fóruns Contábeis/TabNews).
- Chamado Contora respondido em 14/08/2026 (Geovane) — correção do cadastro (IM/CNC) e do
  gerador (xNome em tpEmit=1); NFS-e de validação: doc `1b4367a0`, chave
  `42082032250057049000159000000000000126083779781389`.

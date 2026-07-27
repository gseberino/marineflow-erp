# Fotos do catálogo — semeadura pelo catálogo do fabricante

Ferramenta de linha de comando para dar foto aos produtos que não têm. Nasceu do
gargalo do **vendedor autônomo** (Pilar ④ do roadmap): sem foto não há post de
status, e o catálogo tinha **2 fotos em 423 produtos** — 296 equipamentos no zero.

O primeiro alvo é a Victron Energy: **179 produtos, todos equipamento, nenhum com
foto** — sozinha, 60% do problema.

## Como funciona

O sitemap público da Victron usa a extensão `image:` do schema de sitemaps, então
um único arquivo já traz **toda página de produto com suas fotos oficiais** — não
é preciso varrer o site. O casamento com o nosso catálogo é feito pelo modelo
dentro do nome (`MultiPlus-II 12/3000/120-32` ↔
`PMP122305010_Multiplus-II 12V 3kVA_120-32 230V (front).png`), porque o nosso SKU
é interno e não tem relação com o part number do fabricante.

## Passos

```sh
DADOS=.catalogo-fotos    # pasta de trabalho (fora do git)

node scripts/catalogo-fotos/1-sitemap.mjs $DADOS          # índice do catálogo oficial
node scripts/catalogo-fotos/2-casar.mjs $DADOS            # produto -> página -> foto
node scripts/catalogo-fotos/3-baixar.mjs $DADOS           # baixa as escolhidas
powershell -File scripts/catalogo-fotos/4-normalizar.ps1 -Dados $DADOS
node scripts/catalogo-fotos/5-conferencia.mjs $DADOS      # página de conferência
node scripts/catalogo-fotos/6-subir.mjs $DADOS --seco     # ensaio
node scripts/catalogo-fotos/6-subir.mjs $DADOS --rejeitar 2763,2775
```

O passo 2 precisa de `$DADOS/produtos.json` — a lista a casar, exportada do ERP:

```json
[{ "sku": "2584", "name": "Inversor e Carregador MultiPlus - II 12/3000/120 - 32 - 220V - Victron Energy", "estoque": 2, "preco": 17593.58 }]
```

O passo 4 é PowerShell porque usa o `System.Drawing` do Windows para redimensionar
— evita acrescentar uma dependência de imagem ao projeto por causa de um piloto.
Ele importa: as fotos do fabricante vêm em qualidade de impressão (**236 MB** nas
44 primeiras, uma delas com 20 MB) e saem em **3,6 MB** como JPEG 1200px sobre
fundo branco (o PNG original é transparente — sem o fundo branco, o JPEG sairia
preto).

## Como o casamento decide

| nível | o que significa |
| --- | --- |
| `variante-exata` | todos os números do modelo batem com o nome do arquivo oficial |
| `variante` | os números batem e nenhum contradiz; o nome oficial é só mais curto |
| `familia` | não achei a variante — entra a foto-herói da linha, marcada para conferência |
| `sem-regra` | nenhuma família casou; fica sem foto |

A regra que importa é a do **conflito**: um número que aparece no arquivo e não no
nosso nome significa que aquela é *outra* variante. Sem isso, o 48/5000 recebia a
foto do 24/5000 só porque ambos têm "5000" e "230" — e o resultado parecia
confiável. Quando há conflito, a foto genérica da linha é preferida à foto de um
modelo vizinho: honesta em vez de convincente.

Famílias novas entram em `victron-regras.json`, que é uma tabela de
`regex do nosso nome -> slug da página oficial`. A primeira regra que casa vence,
então as específicas vêm primeiro.

## Cuidados

- **Nada é gravado sem conferência.** O passo 6 só roda depois que a página do
  passo 5 foi revisada, e aceita `--rejeitar` para os vetados.
- O passo 6 **não sobrescreve foto existente** (`image_url is null`), a não ser
  com `--forcar` — trabalho manual do dono não é atropelado por lote.
- Credenciais só pelo ambiente (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`),
  nunca impressas.
- O passo 3 baixa uma foto por vez com pausa: é site de fabricante, não API nossa.
- `procedencia-victron.json` guarda de qual página e arquivo veio cada foto — dá
  para reauditar ou refazer sem repetir o casamento.

## Outras marcas

O resto do catálogo não tem `brand` preenchido (234 de 423 produtos), então
Garmin/Raymarine/Mastervolt vão exigir primeiro identificar a marca pelo nome. A
mecânica dos passos 1–6 é a mesma; muda o sitemap e a tabela de regras.

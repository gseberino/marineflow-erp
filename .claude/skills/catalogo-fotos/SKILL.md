---
description: Dá foto oficial aos produtos do catálogo do MarineFlow puxando do site do fabricante, com conferência humana antes de gravar. Rodar quando faltarem fotos de produto (orçamento sem imagem, vendedor autônomo sem material para status), quando entrar uma marca nova no catálogo, ou quando o dono pedir para "buscar as fotos" de uma marca. Cobre o ciclo inteiro: índice do fabricante, casamento por modelo, download, normalização, página de conferência, upload e gravação de image_url.
---

# Fotos do catálogo — semeadura pelo catálogo do fabricante

## Por que isto existe

Foto de produto serve a duas coisas no MarineFlow: **orçamento com cara profissional**
e **material para o vendedor autônomo postar no status**. Sem foto, os dois travam.

O catálogo nasceu quase vazio de imagens (2 em 423). A saída não é digitar produto por
produto: o fabricante já publica a foto oficial, e o trabalho é casar o nome do nosso
cadastro com o modelo dele.

Ferramenta: `scripts/catalogo-fotos/` (passos 1 a 6) — veja o README de lá para as
flags. Esta skill é o **julgamento** em volta dela.

## O caminho, em ordem

### 1. Medir antes de agir
```sql
select count(*) filter (where image_url is null or image_url = '') as sem_foto,
       coalesce(nullif(trim(brand),''),'(sem marca)') as marca, count(*)
from products where active group by marca order by count desc;
```
Ataque **uma marca por vez**, começando pela maior. Marca com 150 produtos rende mais
do que dez marcas com 3. Se `brand` estiver vazio (é o caso da maioria aqui), a marca
precisa sair do nome antes — sem isso não há de qual catálogo puxar.

### 2. Achar a fonte oficial — tente o sitemap primeiro
Antes de pensar em varrer o site, baixe `https://<fabricante>/sitemap.xml` e procure
`<image:loc>`. Muitos fabricantes usam a extensão `image:` do schema de sitemaps e
entregam **todo o catálogo com as fotos** num arquivo só. Foi assim com a Victron:
233 páginas e 2.493 imagens, sem varrer nada.

Se não houver sitemap com imagem, aí sim: página por página, com pausa entre elas.
É site de fabricante, não API nossa.

### 3. Casar pelo modelo, não pelo SKU
O nosso SKU é interno (`2584`) e não tem relação com o part number do fabricante. O que
casa é o **modelo dentro do nome**:
`MultiPlus-II 12/3000/120-32` ↔ `PMP122305010_Multiplus-II 12V 3kVA_120-32 230V (front).png`

Duas regras que o piloto ensinou, e que valem para qualquer marca:

**a) Conflito derruba, ausência não.** Um número que aparece no arquivo oficial e *não*
no nosso nome significa que aquela é OUTRA variante — penalize forte. Um número que está
no nosso nome e falta no arquivo é só o nome oficial sendo mais curto — quase não pesa.
Sem essa distinção, o 48/5000 recebe a foto do 24/5000 (ambos têm "5000" e "230") e o
resultado *parece* confiável. Foi o erro da primeira versão: 32 casamentos "alta
confiança", vários errados.

**b) Na dúvida, foto da linha.** Havendo conflito, prefira a foto-herói da família à foto
de um modelo vizinho. A genérica é honesta; a do vizinho é convincente e errada.

Limpe do nome do arquivo, antes de extrair números: part number (`PMP122305010`), carimbo
do CMS (`20180706100526`), `300dpi`, `IP65`, `2x`. Converta `3kVA` → `3000` e trate
**220V e 230V como a mesma máquina** (nome brasileiro × nome oficial).

### 4. Normalizar — não subir o arquivo do fabricante
As fotos vêm em qualidade de impressão: **236 MB** nas 44 primeiras, uma delas com 20 MB.
O passo 4 reduz para 3,6 MB (JPEG 1200px). O PNG original é **transparente** — sem
compor sobre fundo branco, o JPEG sai com fundo preto.

### 5. Conferência humana — sempre, sem exceção
O passo 5 gera uma página com todas as miniaturas; publique como artifact e **espere o
dono responder**. Nunca grave `image_url` sem esse aval. Ele reconhece o produto na hora;
nós, não.

### 6. Subir e gravar
O upload precisa da `service_role` — **não leia o `.env` nem puxe a chave do painel**.
Monte o comando e peça para ele rodar, sempre com prompt em vez de placeholder colável
(já houve um caso de o texto de exemplo ir como chave):

```powershell
$env:SUPABASE_URL = "https://okurngvcodmljjicopdp.supabase.co"
$sec = Read-Host "Cole a service_role key" -AsSecureString
$env:SUPABASE_SERVICE_ROLE_KEY = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
node scripts/catalogo-fotos/6-subir.mjs <pastaDeDados>
```

A CLI do Supabase **não** serve para o upload: este projeto usa storage legado e ela
responde `LegacyStorageUnsupportedOperationError`. Ela serve para *conferir* o bucket
(`storage ls -r ss:///product-images --linked --experimental`).

Depois do upload, na ordem:
1. confira que cada URL pública responde como imagem, **sem credencial** (é assim que o
   WhatsApp e o PDF do orçamento vão buscar);
2. só então grave `image_url`, sempre com `and image_url is null` (nunca atropele foto
   que o dono subiu à mão);
3. antes de gravar, um pré-check: quantas linhas casam com a lista de SKUs, se há
   duplicata, se alguma já tem foto, se alguma está fora da marca.

## A armadilha que não é técnica

Cabo, sensor, interface, fusível e adaptador **fazem parte de um sistema** — não se vendem
sozinhos. Dar foto a eles é certo (o orçamento fica bom), mas eles não podem virar oferta
avulsa. E há uma ironia: `get_promo_candidates` dá **+5 no score para quem tem foto**,
então subir as fotos empurra justamente os complementares para o topo da promoção. No
piloto, 10 dos 12 primeiros candidatos viraram cabo e sensor.

Por isso existe `products.vende_isolado`. **Sempre confira, depois de gravar as fotos:**
```sql
select name, sku, has_image, round(score,1) from get_promo_candidates(12);
```
Se aparecer cabo ou sensor na lista, marque `vende_isolado = false` neles antes de
qualquer post de status.

## Onde isso mora

Ferramenta e regras ficam no repo (`scripts/catalogo-fotos/`), o resultado do casamento
fica versionado (`procedencia-victron.json`) para dar para reauditar, e as fotos baixadas
ficam fora do git (`.catalogo-fotos/`, pesadas e refazíveis).

**Marca nova:** copie `victron-regras.json`, troque o sitemap no passo 1 e escreva a tabela
de `regex do nosso nome -> slug da página oficial`. O resto do pipeline não muda.

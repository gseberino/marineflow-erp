# Evolution API — Ambiente Local

Stack Docker para rodar a Evolution API localmente durante a migração do MarineFlow ERP de Z-API → Evolution API.

## Pré-requisitos

- Docker >= 24 com o plugin Compose (`docker compose version`)
- Portas `8080` e `5432` livres na máquina
- Conexão com a internet para baixar as imagens na primeira vez

## Como subir

```bash
cd infra/evolution

# 1. Crie o arquivo de configuração a partir do exemplo
cp .env.example .env

# 2. Edite o .env e configure ao menos:
#    - AUTHENTICATION_API_KEY  (chave aleatória >= 32 chars)
#    - POSTGRES_PASSWORD       (senha forte)
nano .env   # ou code .env

# 3. Suba o stack em background
docker compose up -d
```

## Como verificar se está rodando

```bash
# Status dos contêineres
docker compose ps

# Logs em tempo real (Ctrl+C para sair)
docker compose logs -f evolution-api

# Health check da API
curl -s http://localhost:8080 | jq .
```

A resposta esperada é um JSON de boas-vindas da Evolution API, por exemplo:
```json
{ "status": 200, "message": "Welcome to the Evolution API!" }
```

## Como criar uma instância de teste

```bash
# Substitua MY_API_KEY pelo valor de AUTHENTICATION_API_KEY no seu .env
curl -X POST http://localhost:8080/instance/create \
  -H "Content-Type: application/json" \
  -H "apikey: MY_API_KEY" \
  -d '{
    "instanceName": "marineflow-dev",
    "integration": "WHATSAPP-BAILEYS"
  }' | jq .
```

## Como gerar o QR Code (conectar WhatsApp)

```bash
# 1. Conecte a instância (inicia a sessão)
curl -X GET http://localhost:8080/instance/connect/marineflow-dev \
  -H "apikey: MY_API_KEY" | jq .

# 2. Obtenha o QR Code em base64
curl -X GET "http://localhost:8080/instance/qrcode/marineflow-dev?image=true" \
  -H "apikey: MY_API_KEY" | jq .qrcode.base64

# 3. Decodifique e abra a imagem (Linux/macOS)
curl -s "http://localhost:8080/instance/qrcode/marineflow-dev?image=true" \
  -H "apikey: MY_API_KEY" | jq -r '.qrcode.base64' \
  | base64 -d > /tmp/qrcode.png && open /tmp/qrcode.png   # macOS
  # ou: xdg-open /tmp/qrcode.png                          # Linux

# 4. Escaneie o QR Code com o WhatsApp (Dispositivos vinculados → Vincular dispositivo)
```

## Como parar e limpar

```bash
# Parar os contêineres (mantém volumes / dados da sessão)
docker compose down

# Parar E remover volumes (apaga banco + sessão WhatsApp — use com cuidado)
docker compose down -v
```

## Estrutura do stack

| Serviço | Imagem | Porta | Descrição |
|---------|--------|-------|-----------|
| `evolution-api` | `evoapicloud/evolution-api:latest` | `8080` | API REST da Evolution |
| `evolution-postgres` | `postgres:15` | interno | Banco de dados |
| `evolution-redis` | `redis:7-alpine` | interno | Cache de sessão |

Os dados persistem em três volumes Docker nomeados:
- `evolution_pgdata` — dados do PostgreSQL
- `evolution_instances` — arquivos de sessão WhatsApp (não perca este volume!)
- `evolution_redis_data` — cache Redis

## Solução de problemas

| Sintoma | Causa provável | Solução |
|---------|---------------|---------|
| `curl` retorna `Connection refused` | API ainda inicializando | Aguarde 20–30s e tente novamente |
| Erro `password authentication failed` | `.env` com senha errada | Ajuste `.env`, rode `docker compose down -v && docker compose up -d` |
| QR Code expira antes de escanear | Timeout da sessão | Gere um novo com o comando de connect |
| Sessão desconecta após restart | Volume `evolution_instances` perdido | Não use `down -v`; verifique `docker volume ls` |

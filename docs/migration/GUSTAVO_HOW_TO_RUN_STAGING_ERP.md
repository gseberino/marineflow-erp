# Como Rodar o ERP Marineflow em STAGING

Este guia explica como rodar o ambiente de staging localmente para testes e validações.

## 🚀 Passo a Passo

1. **Abrir o Terminal** (PowerShell ou Command Prompt).
2. **Navegar até a pasta do projeto**:
   ```powershell
   cd "C:\Users\PC\.gemini\antigravity\scratch\marineflow-erp"
   ```
3. **Iniciar o servidor de desenvolvimento**:
   ```powershell
   npm run dev
   ```
4. **Acessar a URL no navegador**:
   ```text
   http://localhost:8082
   ```

## 🔐 Autenticação (Bypass de Staging)

O aplicativo está configurado com um **bypass de autenticação** para facilitar testes locais contra o banco de staging.

- **Email**: Pode usar qualquer email cadastrado (ex: `g.seberino@hotmail.com`).
- **Senha**: Pode digitar qualquer senha (será ignorada pelo bypass).
- **Segurança**: Este bypass **só funciona em localhost** e quando conectado ao projeto de staging (`okurngvcodmljjicopdp`).

## 📊 Módulos Validados em Staging

Os seguintes módulos foram testados e estão carregando dados reais do banco de staging:

- **Dashboard**: Indicadores financeiros e widgets de ordens de serviço.
- **Clientes**: Listagem completa (500+ registros) e detalhes.
- **Embarcações**: Listagem, perfis técnicos e histórico.
- **Ordens de Serviço**: Listagem, filtros e visualização detalhada.
- **Financeiro**: Contas a receber e a pagar.
- **Estoque / Produtos**: Catálogo de peças com controle de estoque mínimo.
- **Serviços**: Catálogo de serviços de manutenção.
- **Agenda**: Visualização de cronograma técnico.

## 🚫 O que NÃO fazer

- **NÃO fazer git push**: A branch `codex/migration-audit` contém ajustes específicos para o schema de staging que não devem ir para o repositório principal sem revisão.
- **NÃO fazer deploy**: Não tente publicar esta versão na Vercel ou Lovable.
- **NÃO apagar .env.local**: Este arquivo contém as chaves necessárias para conectar ao banco de staging.
- **NÃO alterar o Supabase de Produção**: Certifique-se de que está operando apenas no projeto `okurngvcodmljjicopdp`.

## 🛠️ Próximos Passos

1. **Substituir Bypass**: Assim que os testes funcionais terminarem, convidar usuários reais no Supabase Staging e remover o flag `VITE_ENABLE_STAGING_AUTH_BYPASS`.
2. **Testar PDFs**: Validar a geração de PDFs de Ordens de Serviço (ajustar mapeamentos de colunas se necessário).
3. **Auditoria de Policies**: Revisar RLS policies no banco de staging antes de qualquer promoção para produção.

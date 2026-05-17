<!-- HBR_PERMANENT_AGENT_INSTRUCTIONS_START -->
# HBR permanent agent instructions - Marineflow ERP

## Instrucoes permanentes para agentes neste repositorio

Projeto: Marineflow ERP

Este repositorio deve seguir o padrao operacional HBR com registro obrigatorio no Obsidian.

Fonte oficial global:

D:\IA-HBR\Knowledge-Base-Obsidian\00-System\INSTRUCOES-PERMANENTES-AGENTES-HBR.md

Contexto do projeto:

D:\IA-HBR\Knowledge-Base-Obsidian\10-Projects\Marineflow-ERP\

## Regras obrigatorias

Antes de qualquer alteracao:

1. Confirmar branch, HEAD e status Git.
2. Ler contexto do projeto no Obsidian quando disponivel.
3. Mapear causa raiz antes de alterar codigo.
4. Inspecionar repositorio, hooks, componentes, servicos, Supabase, Edge Functions e fluxos relacionados quando aplicavel.
5. Nao alterar main.
6. Nao fazer force push.
7. Nao criar tag sem autorizacao explicita.
8. Nao alterar remote.
9. Nao ler .env.
10. Nao expor secrets.
11. Nao rodar migration sem plano explicito e autorizacao.
12. Nao fazer deploy sem autorizacao explicita.
13. Nao usar Lovable.
14. Nao executar comandos destrutivos.
15. Nao alterar projetos fora do escopo.
16. Rodar build antes de commit.
17. Rodar testes quando existirem e forem aplicaveis.
18. Salvar relatorio operacional no Obsidian ao final.
19. Atualizar ESTADO-ATUAL.md, PENDENCIAS.md e DECISOES-TECNICAS.md se o estado funcional mudar.

## Branches e seguranca

Branch funcional atual conhecida:

- staging/marineflow-functional

Regras:

- Nao tocar em main.
- Nao fazer merge sem autorizacao.
- Nao fazer rebase sem autorizacao.
- Nao fazer push sem autorizacao explicita.
- Nao fazer deploy sem autorizacao explicita.
- Nao rodar migration sem diagnostico, plano e autorizacao.

## Registro operacional obrigatorio

Ao final de toda sessao relevante, salvar relatorio em:

D:\IA-HBR\Knowledge-Base-Obsidian\10-Projects\Marineflow-ERP\SESSOES\

ou, quando for retorno de agente:

D:\IA-HBR\Knowledge-Base-Obsidian\10-Projects\Marineflow-ERP\RETURNS\

O relatorio deve conter:

1. Objetivo.
2. Estado inicial.
3. Branch inicial/final.
4. HEAD inicial/final.
5. Status Git inicial/final.
6. Diagnostico.
7. Causa raiz, quando aplicavel.
8. Arquivos lidos.
9. Arquivos alterados.
10. Arquivos criados.
11. Comandos executados.
12. Testes/build/validacoes.
13. Resultado.
14. Commits criados.
15. Push/deploy/migration, se houve.
16. Riscos e limitacoes.
17. Proximos passos.
18. Confirmacoes finais.

## Confirmacoes finais obrigatorias

Confirmar explicitamente:

- nao fez push, salvo se autorizado;
- nao criou tag;
- nao fez force push;
- nao alterou main;
- nao rodou migration sem autorizacao;
- nao fez deploy sem autorizacao;
- nao leu .env;
- nao expos secrets;
- nao usou Lovable;
- nao alterou projeto fora do escopo;
- nao executou comandos destrutivos;
- rodou build antes de commit quando houve alteracao de codigo.

## Fluxos sensiveis do Marineflow ERP

Atenção especial para:

- WhatsApp/Z-API;
- Inbox;
- leads;
- clientes;
- OS / service orders;
- PDFs / orcamentos;
- Supabase;
- Edge Functions;
- Vercel;
- UI/UX preview routes;
- branches staging.

Antes de corrigir sintomas, sempre mapear o fluxo completo e a causa raiz.
<!-- HBR_PERMANENT_AGENT_INSTRUCTIONS_END -->

---
description: Coordena VÁRIAS sessões de IA trabalhando no mesmo repositório MarineFlow ao mesmo tempo, para que nenhuma sobrescreva ou reverta o trabalho da outra. Rodar no INÍCIO de qualquer sessão neste repo quando houver (ou puder haver) outra sessão/agente ativo na mesma pasta, e sempre que aparecer o sintoma de "arquivo modificado no disco"/edições revertidas, commits de outra origem no seu git log, ou dúvida sobre quem está deployando. Isola cada sessão em um git worktree próprio e serializa a integração/deploy com um lock.
---

# Multi-session guard — trabalho paralelo seguro no mesmo repo

## Por que isto existe

Duas sessões de IA na MESMA pasta compartilham **uma** árvore de trabalho e **um** `.git`
(index, refs). Git não trava arquivos: se as duas editam o mesmo arquivo, a última escrita
vence e a outra some; um `git checkout .`/`reset --hard`/`stash` de uma **apaga o trabalho
não-commitado** da outra; um `git add -A` estagia arquivos alheios; e um `deploy` empacota o
que está no disco — podendo subir código pela metade da outra sessão. Já aconteceu neste repo
(um `prompt.ts` reverteu no meio de uma edição enquanto outra sessão commitava fiscal).

**A segurança vem do ISOLAMENTO durante o trabalho, não de juntar tudo no fim.** Cada sessão
trabalha em um `git worktree` separado (pasta física própria) e só a etapa de integrar+deployar
é serializada por um lock global.

Helper: `bash .claude/skills/multi-session-guard/guard.sh <comando>` (rode da raiz do repo).
Estado em `$(git-common-dir)/mf-sessions` — dentro do `.git`, nunca versionado.

## Protocolo

### 1. No início da sessão — detectar e isolar
```
bash .claude/skills/multi-session-guard/guard.sh status      # quem está ativo? lock livre?
```
- Se `guard.sh others` retornar **0** e você já está num worktree dedicado → siga normal, só `register`.
- Se há OUTRA sessão ativa (ou você está na pasta `main` compartilhada e pode surgir outra):
  ```
  bash .claude/skills/multi-session-guard/guard.sh worktree ai   # cria ../<repo>--ai no branch session/ai
  ```
  A partir daí, **trabalhe SEMPRE com caminhos dentro dessa pasta nova** (o comando imprime o caminho). Nunca mais edite/rode git na pasta compartilhada.
- Registre-se e deixe um heartbeat de tempos em tempos:
  ```
  bash .claude/skills/multi-session-guard/guard.sh register
  ```

### 2. Durante o trabalho — regras invioláveis
- **Nunca** `git add -A` / `git add .` — estagie arquivo por arquivo e confira `git status` (o index é compartilhado; regra já valia neste repo).
- **Nunca** rode, na pasta compartilhada, comandos que mexem na árvore alheia: `git reset --hard`, `git checkout .`/`git restore .`, `git stash` global, `git checkout <branch>`, `git clean`. No SEU worktree, sem problema.
- **Commite cedo e em pedaços pequenos** — quanto menor a janela de trabalho não-commitado, menor o risco. Um `deno check`/teste verde por commit.
- Rode `guard.sh heartbeat` a cada poucos passos (mantém você "vivo" no registro).
- Antes de qualquer operação destrutiva, rode `git status` e confirme que só há SEU trabalho ali. Se aparecer mudança que não é sua, **pare e investigue** — não sobrescreva.

### 3. No fim — integrar + deployar (seção crítica, sob lock)
Faça isto no SEU branch, com tudo já commitado:
```
bash .claude/skills/multi-session-guard/guard.sh lock        # espera a vez (serializa)
git fetch origin 2>/dev/null || true
git rebase origin/main || git rebase main                    # traz o trabalho já integrado das outras
# resolva conflitos AQUI, no seu branch, com calma — nunca com -X ours/theirs cego
deno test --allow-all supabase/functions/_shared/ai/         # gate: testes verdes antes de integrar
git switch main && git merge --ff-only session/ai            # integra (fast-forward; sem merge-commit sujo)
# deploy A PARTIR da main recém-integrada — só das funções cujos arquivos mudaram no seu branch:
#   npx supabase functions deploy <fn> --project-ref okurngvcodmljjicopdp
bash .claude/skills/multi-session-guard/guard.sh unlock
bash .claude/skills/multi-session-guard/guard.sh done        # sai do registro
git worktree remove ../<repo>--ai                            # opcional: limpa o worktree
```
Como integrar+deployar roda **dentro do lock**, as sessões se serializam: quem integra por
último tem a `main` com **tudo** e o deploy dela reflete o conjunto completo. É o "quem termina
por último faz o certo" — sem bookkeeping frágil, porque cada uma sempre parte da main atual.

## Comandos do guard.sh
| Comando | O que faz |
|---|---|
| `status` | worktree/branch atual, sessões ativas, estado do lock |
| `others` | nº de OUTRAS sessões ativas (0 = você está sozinho) |
| `worktree <nome>` | cria/reaproveita `../<repo>--<nome>` no branch `session/<nome>` |
| `register` / `heartbeat` / `done` | entra / sinaliza vivo / sai do registro |
| `lock` / `unlock` | adquire / libera o lock de integração (mkdir atômico; quebra lock stale > 45min) |

## Limitação (honesta)
É **cooperativo**: protege plenamente entre sessões que rodam ESTA skill. Se a outra ferramenta
(Codex, Gemini, Copilot…) não seguir, o worktree ainda **te isola** (você sai da pasta
compartilhada e ela não te alcança), mas você não consegue impedir que ELA corrompa a própria
cópia. Nesse caso: peça que a outra também trabalhe em worktree/branch próprio, ou rode-as em
horários separados.

## Sinais de que você PRECISA desta skill agora
- Aviso "arquivo modificado no disco desde a última leitura" / suas edições sumiram.
- `git log` mostra commits que você não fez, intercalados com os seus, no mesmo branch.
- Você vai deployar e não tem certeza se outra sessão está deployando a mesma função.

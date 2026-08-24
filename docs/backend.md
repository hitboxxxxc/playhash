# PlayHash — Backend Econômico (plano Spark, sem Blaze)

> **Zero Cloud Functions. Zero Firebase Storage. Zero plano Blaze.**
> A autoridade econômica vive em um módulo Node 20 + TypeScript (`backend/`)
> executado por **GitHub Actions** contra o Firestore via Admin SDK.

## 1. Arquitetura

```
┌──────────────┐   intenções (não confiáveis)   ┌─────────────────────────┐
│ App Flutter  │ ─────────────────────────────▶ │ Firestore (Spark)       │
│ (cliente)    │  gameSessions / purchaseIntents│                         │
└──────────────┘                                │  config/economy         │
                                                │  config/catalog/machines/* │
┌──────────────────────────────────┐            │  games/*                │
│ GitHub Actions (cron */5 +       │  Admin SDK │  power / tempGrants     │
│ workflow_dispatch) — repo PÚBLICO│ ─────────▶ │  wallets / transactions │
│ backend/: npm ci → build → runner│            │  blocks / auditLogs     │
└──────────────────────────────────┘            └─────────────────────────┘
```

### Princípios (todo dado enviado pelo cliente pode ser falsificado)

1. **O runner é a ÚNICA autoridade econômica.** O cliente só escreve
   *intenções* (`gameSessions` open/finished, `purchaseIntents` pending),
   com campos exatos validados por `firestore.rules`.
2. **Precisão inteira (BigInt)** em toda aritmética econômica
   ([`core/precision.ts`](../backend/src/core/precision.ts)). Proibido float.
3. **Tempo somente do servidor**: durações usam timestamps já ancorados no
   servidor pelas rules (`startedAt`/`finishedAt` ≈ `request.time`); blocos usam
   `Date.now()` do runner.
4. **Idempotência**: doc IDs determinísticos (grant = sessionId, transação =
   `{periodKey}_{uid}`, auditoria = `${type}:${referenceId}`), flags
   `processed`, guardas `status='finalized'` e dedupe por `clientRequestId`.
5. **Auditoria append-only** em `auditLogs` para toda operação econômica:
   `GAME_POWER_GRANTED`, `GAME_POWER_EXPIRED`, `GAME_SESSION_REJECTED`,
   `MACHINE_PURCHASED`, `PURCHASE_FAILED`, `BLOCK_CREATED`,
   `BLOCK_FINALIZED`, `REWARD_CREDITED`.
6. **Fail-safe**: `config/economy` ausente/inválida ⇒ processadores abortam
   (nunca inventam parâmetros).

### Fluxos

| Processador | Entrada | Saída |
|---|---|---|
| `processGameSessions` | `gameSessions{status=finished, processed=false}` | grant temporário 24h em `tempGrants/{sessionId}`, `power/{uid}.totalPower` recalculado, sessão marcada `processed=true` + `serverResult` |
| `processPurchaseIntents` | `purchaseIntents{status=pending}` | transação atômica: débito em `wallets`, item em `machines/{uid}/items`, soma `permanentPower`, intent `done/failed` |
| `closeBlocks` | períodos completos não finalizados | `blocks/{periodKey}` finalized, `transactions/{txId}`, `wallets.availableBalance/lifetimeEarned`, resíduo → próximo bloco |

### Fórmulas

- **Poder por sessão**: `rawPower = floor(score × powerBaseReward / maxExpectedScore)`,
  limitado por `powerCapPerSession` (config do game).
- **Recompensa por bloco (5 min)**:
  `USER_REWARD = floor(BLOCK_REWARD × USER_POWER / NETWORK_POWER)`
- **Resíduo determinístico**: `residue = BLOCK_REWARD − Σ rewards` é carregado
  para o bloco seguinte via `config/economy.residueUnits` (nada se perde).

## 2. Segredos (runbook)

Segredos vivem **apenas** em GitHub Secrets ou `backend/.secrets/` (gitignored).
**Nunca** no Git, nunca no APK, nunca em logs.

1. **Criar repositório público separado** no GitHub (ex.: `playhash-econ`) e
   copiar para ele `backend/` + `.github/workflows/econ-cron.yml`.
   *Motivo: repos públicos têm minutos ilimitados de Actions; o cron `*/5`
   consumiria 8.640 execuções/mês num repo privado.*
2. **Google Cloud Console → IAM & Admin → Service Accounts → Create**:
   - Nome: `playhash-econ-runner`.
   - Papel mínimo: `roles/datastore.user` (Firestore only).
3. **Keys → Add key → JSON** e salvar como `backend/.secrets/serviceAccount.json`
   (local). Rodar `npm run seed` uma vez para criar configs dev.
4. **GitHub → repo econ → Settings → Secrets and variables → Actions**:
   - New repository secret: `FIREBASE_SERVICE_ACCOUNT_KEY` = conteúdo completo
     do JSON. O workflow grava-o em `$RUNNER_TEMP/serviceAccount.json`
     (chmod 600, apagado ao final, jamais ecoado no log).
5. **Push do backend** para o repo público e disparar
   **Actions → econ-cron → Run workflow** (workflow_dispatch) para validar E2E.

Rotação: gere nova chave, atualize o secret, remova a antiga no GCP.

## 3. Portabilidade futura para Cloud Functions

O núcleo foi desenhado para migrar sem reescrita:

- Toda lógica pura está em `core/` (sem I/O): `precision.ts`, `power.ts`
  (funções puras), `config.ts` (cache), validações exportadas dos processors.
- Os processadores recebem `Firestore` por injeção — basta trocar o chamador
  (`runner.ts`) por triggers `onDocumentWritten` chamando os mesmos handlers.
- `admin.ts` já usa `initializeApp()` padrão do firebase-admin.
- Migração sugerida: (1) deploy das functions com o mesmo código de
  `processors/`; (2) desligar o cron; (3) remover `lastFinalizedPeriodKey`
  guardas duplicados (functions são idempotentes pelos mesmos doc IDs).

## 4. Cotas gratuitas e gatilhos de escala

| Recurso | Cota gratuita Spark/free tier | Consumo estimado |
|---|---|---|
| Firestore leituras | 50k/dia | power scan por bloco (~288/dia × usuários ativos) |
| Firestore escritas | 20k/dia | ~4 escritas/sessão + 3/reward/bloco |
| GH Actions (repo público) | ilimitado | 288 jobs/dia × ~1–2 min |

**Gatilhos de escala** (quando atingir ~60% da cota):

1. Ativar **App Check** (reduz abuso de intents; pendência atual).
2. Mover `processGameSessions`/`processPurchaseIntents` para Cloud Functions
   (plano Blaze) — ver §3 — eliminando polling.
3. Cache de `power` agregado (shards) para reduzir leituras do bloco.
4. Paginar `maxUsersPerBlock` e distribuir fechamento entre execuções.
5. Compressão de `auditLogs` (TTL/export para BigQuery).

## 5. Validação local (sem emuladores)

```bash
cd backend
npm ci
npm run build
npm test        # precision, blockDistribution, session, purchase
```

E2E no Firestore real depende das ações humanas do runbook (§2).

## 6. Apêndice — Correções 5.6 (2026-08-24)

### A. Workflow scheduled vermelho — causa raiz e correção

**Sintoma**: runs `action=run` (manual e scheduled) falhavam com exit 1;
`closeBlocks` OK, `gameSessions`/`purchaseIntents` com
`FAILED_PRECONDITION: The query requires an index`.

**Causa raiz**: as queries de batch exigem índices compostos que não
existiam no projeto (`firestore.indexes.json` vazio):

- `gameSessions`: `status ==` + `processed ==` + `orderBy finishedAt`
- `purchaseIntents`: `status ==` + `orderBy createdAt`

As runs "verdes" anteriores eram apenas `seed`, que não executa essas
queries — por isso o problema só apareceu no primeiro `run`.

**Correção**:
- `backend/src/ensureIndexes.ts`: cria os índices via API Admin do
  Firestore de forma IDEMPOTENTE (409 ALREADY_EXISTS = ok), aguardando
  a operação até done (tolera resposta síncrona e 404 em polling).
  Executado pelo workflow ANTES do runner (passo "Ensure Firestore
  indexes"), usando o secret existente. Nenhum segredo no log.
- `firestore.indexes.json`: declara os dois índices compostos.
- `backend/src/runner.ts`: `serializeForLog` converte BigInt→string
  (JSON.stringify cru lança TypeError com bigint) e `main()` só roda
  quando invocado direto (`require.main === module`).

**Tolerância já correta (sem mudança)**: rede vazia/zero elegíveis em
`distributeBlockReward` finaliza o bloco com distribuição vazia e
resíduo 100% carregado (testado); config ausente falha seguro com
`ECONOMY_CONFIG_MISSING` auditável.

### B. Autenticação no dispositivo físico

**Achados**:
1. `android/app/google-services.json` existe, `project_id =
   playhash-70742`, package `com.mustarda.playhash` — porém SEM nenhum
   `oauth_client` registrado (`oauth_client_types=[]`). Isso quebra o
   Google Sign-In com DEVELOPER_ERROR (ApiException 10).
2. Mapeamento anterior exibia "Sem conexão" para qualquer erro cujo
   texto contivesse 'connection'/'socket' — falso negativo de rede.

**Correção**: `lib/core/services/auth_error_messages.dart` mapeia cada
código para mensagem PT-BR específica; "sem conexão" SOMENTE para
códigos de rede reais; DEVELOPER_ERROR/operation-not-allowed → mensagem
clara de configuração. Testes: `test/auth_error_messages_test.dart`.

**SHAs debug do keystore local** (registrar no Firebase Console →
Project settings → Your apps → Android):
- SHA-1: `7F:14:73:7E:FF:7F:23:8C:E2:54:E5:5F:10:D7:1D:C5:40:02:27:C2`
- SHA-256: `8C:6C:1C:17:24:98:70:30:38:6E:28:BD:57:31:B4:BE:EE:21:F5:F3:2C:6A:78:52:96:FA:FD:5F:F7:4F:D5:4B`

Após registrar os SHAs, re-baixar `google-services.json` para
`android/app/` (deve passar a conter `oauth_client` tipo 1) e rebuild.

**users/{uid}**: `_ensureUserDoc` grava exatamente o whitelist das rules
(`displayName, email, photoUrl, createdAt, lastLoginAt, status,
settings, termsAcceptedAt`) — conforme `firestore.rules`.

### C. NOVA SWARM — config do game e fórmula `linear_cap` (2026-08-24)

1. **`games/nova-swarm`** semeado (idempotente) com a config autoridade:
   `durationSeconds 60, baseEnemies 8, enemiesPerWaveStep 4, enemyHp 2,
   lives 3, pointsPerKill 150, pointsPerHit 25, waveBonus 500,
   maxScore 30000, maxScorePerSecond 500, minDurationSeconds 5,
   maxExpectedScore 12000, powerCapPerSessionBaseUnits 100000
   (= 100 H/s com powerBasePerHs 1000), powerFormula "linear_cap"`.
2. **`validateGameSession`** estendida (compatível com games legados):
   - teto de score = `maxScore` (se definido) senão `maxExpectedScore`;
   - duração mínima = `minDurationSeconds` do game (morte antecipada ≥5s é
     vitória legítima); máxima = `durationSeconds + 3s` (tolerância de
     relógio; pausas longas no cliente ⇒ `DURATION_TOO_LONG`);
   - taxa = `maxScorePerSecond` do game senão o limite da economia;
   - poder: `linear_cap` ⇒ `floor(min(score/maxExpectedScore,1) ×
     powerCapPerSessionBaseUnits)`; legado ⇒ fórmula proporcional antiga.
3. **`firestore.rules`**: update de `gameSessions` usa `gameMaxScore()`
   (`maxScore` quando presente). **PENDÊNCIA (ação humana)**: publicar as
   rules (Console do Firebase → Rules, ou `firebase deploy --only
   firestore:rules` com conta autorizada — a conta local recebeu 403
   serviceusage). Enquanto não publicadas, scores > 12.000 do nova-swarm
   são rejeitados pelo teto antigo (`maxExpectedScore`).
4. `firebase.json` adicionado na raiz para `firebase deploy
   --only firestore:rules` apontar para `firestore.rules` +
   `firestore.indexes.json`.

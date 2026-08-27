# PlayHash — Runbook de Pagamentos (Saques / FaucetPay)

> Autoridade: runner econômico (`backend/src/runner.ts` + `backend/src/processors/processWithdrawals.ts`).
> Docs de referência: 05 §26–27 (saques/PayoutProvider), 04 (release/segurança).

> **DECISÃO DO DONO (14.8):** Saque padrão: mínimo 50 COIN, taxa 25 COIN. Assinante: mínimo 10 COIN, taxa 0 (placeholder premium=false hoje; NADA de Google Play Billing/UI de assinatura agora). Mínimo efetivo exibido/validado = max(mínimo da regra, ceil(providerMinLitoshi / litoshiPerCoin) + taxa) — para o FaucetPay nunca receber pedido abaixo do mínimo dele.

## 1. Visão geral

| Componente | Papel |
|---|---|
| `config/payouts` (Firestore, **version 2**) | Autoridade de ativos, conversão COIN→cripto, mínimos e taxas |
| `PAYOUT_MODE` (repo variable) | `test` (padrão; simulação auditada `SIM-*`) ou `live` (FaucetPay real) |
| `FAUCETPAY_API_KEY` (repo secret) | Chave da conta FaucetPay — NUNCA em logs/APK/Git |
| `payoutProbe` (action) | Validação READ-ONLY: chave + saldos + taxas. Nunca envia dinheiro |
| `payoutLiveTest` (action) | Micro-payout REAL opcional para o endereço do DONO. Default: não executa |

## 2. Variáveis e secrets (nomes apenas)

- Repo variable `ENV` — atual: `dev`.
- Repo variable `PAYOUT_MODE` — atual: `test`. Ausente/inválida ⇒ runner usa `test`.
- Repo secret `FAUCETPAY_API_KEY` — já cadastrada (valor nunca exibido).
- Repo secret `FIREBASE_SERVICE_ACCOUNT_KEY` — credencial admin do runner.

Comandos:

```bash
gh variable list --repo hitboxxxxc/playhash
gh variable set PAYOUT_MODE --body test --repo hitboxxxxc/playhash   # rollback p/ test
gh variable set PAYOUT_MODE --body live --repo hitboxxxxc/playhash   # virar live
```

## 3. Modelo de conversão (config/payouts v2)

Regra única (helper `coinToAsset` em `core/precision.ts`, BigInt puro):

```
grossAsset    = floor(coins × assetUnitPerCoinScaled / coinPrecision)
receivedAsset = grossAsset − providerFeeAssetUnits
validação     = grossAsset ≥ providerMinAssetUnits + providerFeeAssetUnits
                (senão falha segura BELOW_PROVIDER_MIN — sem reserva/estorno)
```

Arredondamento sempre para BAIXO (floor): a conversão **nunca cria valor**.

### Premissas iniciais (conservadoras e AJUSTÁVEIS no doc `config/payouts`)

| Ativo | Rede | assetUnitPerCoinScaled | 1 COIN ≈ | providerMin | providerFee | minWithdraw (plataforma) |
|---|---|---|---|---|---|---|
| BTC | Bitcoin | 25 (8 dec.) | 25 sat | 10 000 sat (0.0001 BTC) | 500 sat | 450 coins → 11 250 sat bruto |
| LTC | Litecoin | 2 000 (8 dec.) | 0.00002 LTC | 100 000 loshi (0.001 LTC) | 5 000 loshi | 60 coins → 120 000 loshi bruto |
| DOGE | Dogecoin | 2 000 000 (8 dec.) | 0.02 DOGE | 5 DOGE | 0.5 DOGE | 300 coins → 6 DOGE bruto |
| USDT | TRC20 | 5 000 (6 dec.) | 0.005 USDT | 5 USDT | 1 USDT | 1300 coins → 6.5 USDT bruto |

**Premissas registradas:** taxas de câmbio internas conservadoras (não são cotação de mercado);
mínimos/taxas do provedor aproximados da FaucetPay — confirmar na prática com o `payoutProbe`
e ajustar os campos direto no doc `config/payouts` (merge, sem redeploy).

Campos v2 por ativo: `assetDecimals`, `assetUnitPerCoinScaled`,
`providerMinAssetUnits`, `providerFeeAssetUnits` (+ `minWithdrawUnits` realinhado).
O seed (`upgradePayoutsToV2`) faz MERGE idempotente; rodar novamente = no-op.

## 4. payoutProbe (read-only)

Executa SOMENTE endpoints de leitura (`/balance`, `/fees`) com o secret.
**Nunca envia payout**; imprime status da chave (válida/inválida), saldos por ativo e
taxas reportadas — nunca a chave nem endereços.

```bash
# Via GitHub UI: Actions → econ-cron → Run workflow → action=payoutProbe
gh workflow run econ-cron --repo hitboxxxxc/playhash -f action=payoutProbe
```

Gate: exige repo variable `ENV=dev`. Qualquer `PAYOUT_MODE` é aceito (o probe não depende do modo).
Interpretação do log:

- `payoutProbe key=VALID` + saldos ⇒ integração OK.
- `FAILED=INVALID_CREDENTIALS` ⇒ chave inválida/expirada — re-cadastrar secret.
- `FAILED=FAUCETPAY_API_KEY_MISSING` ⇒ secret ausente no repo.
- `fees UNAVAILABLE=...` ⇒ best-effort; saldo já provou a chave.

## 5. Como virar LIVE (checklist pré-live)

1. [ ] `payoutProbe` verde mostrando saldo disponível na FaucetPay.
2. [ ] Depositar fundos na conta FaucetPay (saldo por ativo ≥ volume esperado).
3. [ ] Revisar `config/payouts` v2: mínimos/taxas/conversão por ativo (tabela acima).
4. [ ] Revisar antifraude: cooldown 24h, maxPerDay 3, idade mínima 24h, ≥1 jogo finalizado,
       lock `review` após 3 falhas de elegibilidade/dia (§36).
5. [ ] Testar ESTORNO: criar intent inválido pós-reserva em dev e confirmar
       `REVERSAL` íntegro (available += amount, pending −= amount).
6. [ ] Micro-teste real (opcional, endereço do DONO):
       ```bash
       gh workflow run econ-cron --repo hitboxxxxc/playhash \
         -f action=payoutLiveTest -f payoutAsset=DOGE \
         -f payoutAddress=<endereço-do-dono> -f payoutAmount=
       # payoutAmount vazio = providerMin da config (menor envio possível)
       ```
       Gate duplo: só executa com `PAYOUT_MODE=live` **E** inputs explícitos.
       Não reserva saldo de usuário (usa a conta do provedor); auditoria `WITHDRAWAL_TEST`;
       falha ⇒ log seguro, sem crash, sem estorno necessário.
7. [ ] Virar live: `gh variable set PAYOUT_MODE --body live --repo hitboxxxxc/playhash`.

## 6. Rollback para TEST

```bash
gh variable set PAYOUT_MODE --body test --repo hitboxxxxc/playhash
```

Efeito imediato na próxima run do cron: saques voltam a ser simulação auditada (`SIM-*`,
`payoutSimulated=true`). Intents `processing` em aberto podem concluir payout real em
andamento — acompanhar até zerar pendências antes/depois do rollback.

## 7.5 v3 — SAQUE POR E-MAIL FAUCETPAY (atual; 2026-08-25)

- **Destino**: e-mail da conta FaucetPay do usuário (transferência INTERNA).
  NUNCA endereço externo de carteira. Campos do intent:
  `{uid, asset, amountUnits, destinationEmail, destinationMasked,
   clientRequestId, createdAt, clientVersion}`.
- **Conversão FIXA** (`config/payouts` version 3): `1 COIN = 100 litoshi`
  (= 0,000001 LTC). Aritmética inteira: `litoshi = (coins − feeCoins) × 100`.
  Mínimo 20 COIN · taxa 2 COIN ⇒ mínimo líquido 1800 litoshi (0,000018 LTC).
  LTC é o ÚNICO ativo habilitado (BTC/DOGE/USDT "conversão em definição").
  `futureRateSource: 'usd_auto'` é DOCUMENTAL (futuro; sem feed implementado).
- **Confirmação explícita**: sheet `WithdrawConfirmSheet` OBRIGATÓRIA antes de
  criar o intent (resumo + e-mail mascarado + CANCELAR/CONFIRMAR SAQUE).
- **providerMinLitoshi**: `null` — a API da FaucetPay não expõe o mínimo do
  envio interno (`fees UNAVAILABLE=PROVIDER_ERROR` no probe de 2026-08-25;
  chave VÁLIDA, saldo LTC presente). O mínimo da plataforma (20 COIN) é a
  barreira ativa; erro tipado `BELOW_MIN` cobre rejeição do provedor.
- **CORREÇÃO 12.8 (2026-08-25) — causa raiz do "bloqueado pela configuração
  do servidor"**: o gate `dailyQuotaOk` das rules negava a CRIAÇÃO de
  withdrawalIntents para qualquer usuário com doc `rateLimits/{uid}` criado por
  OUTRO contador (`sessions_*`/`claims_*`): acesso a chave INEXISTENTE de map
  nas rules retorna ERRO (não null) ⇒ PERMISSION_DENIED. Agravante: `dayKey`
  das rules era sem zero-pad ('2026-8-25') vs backend ISO padded
  ('2026-08-25'). Fix em `firestore.rules`: guard `!(k in data)` + dayKey
  zero-padded alinhado ao backend. **PENDÊNCIA (ação humana)**: publicar as
  rules corrigidas (`firebase deploy --only firestore:rules --project
  playhash-70742` com conta autorizada — conta local e service account
  receberam 403 IAM). Enquanto não publicadas, intents continuam recebendo
  PERMISSION_DENIED no cliente.
- **Blindagens 12.8 no processador** (`processWithdrawals.ts`): ids de ativo
  normalizados (`normalizeAssetId`, 'ltc' ⇒ 'LTC'); gate por modo
  (`validateProviderMinForMode`): test + providerMinLitoshi null ⇒ passa
  (default seguro documentado), live + null ⇒ BELOW_PROVIDER_MIN até o probe
  gravar o mínimo real. Upgrade idempotente v1/v2→v3 extraído p/
  `core/payoutsUpgrade.ts` (testado; seed confirmou doc v3 no Firestore).
- **Mensagem do cliente 12.8**: permission-denied na criação da intent NUNCA
  mais mostra "atualize o app" — agora: "Saque indisponível para este ativo no
  momento. Tente novamente mais tarde." ("atualize o app" só existiria para
  incompatibilidade real de clientVersion, gate que não existe nas rules).
- **Micro-teste LIVE do dono**: (1) `gh variable set PAYOUT_MODE --body live`;
  (2) no app, solicitar o saque MÍNIMO digitando o próprio e-mail FaucetPay;
  (3) aguardar ≤5 min e conferir status + chegada do saldo na FaucetPay;
  (4) voltar para `test` para pausar pagamentos.

## 7.6 v4/12.10 — rulesProbe + providerMinLitoshi gravado pelo probe

- **rulesProbe** (action nova; ENV=dev): verifica se as Security Rules estão
  PUBLICADAS criando uma `withdrawalIntents` EXATAMENTE como o cliente —
  custom token admin ⇒ ID token real (Identity Toolkit REST) ⇒ Firestore REST.
  Admin SDK bypassaria as rules, então a prova é feita com credencial de
  USUÁRIO. OK ⇒ `rulesProbe OK`; 403 ⇒ `PERMISSION_DENIED` (rules não
  publicadas). Limpa a intent de teste + usuário probe ao final.
- **payoutProbe agora GRAVA o mínimo**: a API da FaucetPay não expõe o mínimo
  do envio interno por e-mail (`/fees` traz só taxas de carteira externa).
  Quando indisponível, o probe grava em `config/payouts` (v4, MERGE seguro)
  `assets.LTC.providerMinLitoshi = 1800` — o LÍQUIDO exato do saque mínimo da
  plataforma ((20 − 2 COIN) × 100 litoshi), com `providerMinSource=payoutProbe`.
  Garantias: nunca ABAIXA um mínimo já confirmado (`applyProbeMinimum`);
  desbloqueia o gate LIVE; rejeição real do provedor continua coberta pelo
  erro tipado `BELOW_MIN` + estorno integral. Se um dia a API expuser o
  mínimo (`minUnits`), ele prevalece (e sobe a barreira se maior).
- **Ordem recomendada de testes LIVE** (cooldown 24h após SUCESSO):
  (1) caminho de FALHA primeiro (e-mail inexistente na FaucetPay ⇒ failed +
  estorno integral, sem cooldown); (2) depois o saque mínimo de sucesso.
- **CORREÇÃO 12.10 — causa raiz do PERMISSION_DENIED universal no saque**:
  a regra de `withdrawalIntents` usava `destinationMasked.contains('***@')`,
  mas **`contains()` NÃO EXISTE na linguagem das Security Rules**. O Console
  publica sem reclamar, porém a função indefinida derruba a expressão inteira
  ⇒ TODA criação de intent era negada (o fingerprint mostrou users/
  gameSessions/adRewardIntents/claims OK e SOMENTE withdrawalIntents DENIED).
  Fix: `matches('.*[*][*][*]@.*')` (classes de caractere, sem barras
  invertidas). Validado no EMULADOR (auth+firestore) com 4 casos:
  válido ⇒ ALLOW; e-mail inválido / máscara sem `***@` / uid alheio ⇒ DENY
  (`backend/scripts/rules_e2e_check.cjs`; rodar com JAVA_HOME do Android
  Studio: `npx firebase emulators:exec --only auth,firestore --project
  playhash-70742 "node backend/scripts/rules_e2e_check.cjs"`).
  **Lição**: SEMPRE validar rules no emulador antes de publicar — o Console
  não detecta função inexistente.

## 7.7 v5/12.18 — PAYOUT FAUCETPAY NO CLIENTE (CHAVE TEMPORÁRIA), SEM COOLDOWN

> **DECISÃO ABSOLUTA DO DONO (registrada nesta data):** o payout FaucetPay foi
> movido para o CLIENTE. O runner continua existindo para TODA a economia
> (créditos, missões, ligas, loja), mas o fluxo de saque LTC agora executa no
> app: **reserva → payout → conclusão OU estorno integral**.

### Parâmetros (config local; exibição derivada)

| Parâmetro | Valor |
|---|---|
| `kLitoshiPerCoin` | 100 (1 COIN = 0,000001 LTC) |
| `kFeeCoins` | 2 COIN |
| `kMinWithdrawCoins` | 3 COIN (recebido mínimo = 1 COIN = 0,000001 LTC) |
| `kMaxPerWithdrawalCoins` | 100.000 COIN (teto do dono, ajustável) |
| Cooldown 24h | **REMOVIDO** — sem trava entre saques |

Arquivo de config: `lib/core/config/payout_config.dart` (**GITIGNORED**) +
`payout_config.example.dart` (commitado, sem chave). A chave efetiva é
`String.fromEnvironment('FAUCETPAY_API_KEY', defaultValue: kTempKey)` — em
release a oficial entra por `--dart-define` SEM editar código:

```bash
flutter build apk --release --dart-define=FAUCETPAY_API_KEY=<chave-oficial>
```

### Arquitetura nova

- `lib/core/services/payout/payout_provider.dart` — abstração §27 mantida;
- `lib/core/services/payout/faucetpay_provider.dart` — POST
  `https://faucetpay.io/api/v1/send` `{api_key, currency:'LTC',
   amount:<litoshi int>, to_user:<email>}`; timeout 15s; SEM retry automático;
   erros mapeados p/ códigos seguros (`PROVIDER_ERROR`, `INVALID_AMOUNT`,
   `INSUFFICIENT_PROVIDER_BALANCE`, `EMAIL_NOT_FOUND`, `RATE_LIMIT`);
- `withdrawal_service.withdraw()`:
  1. transação em `wallets/{uid}`: available ≥ amount ⇒ reserva
     (available −= amount, pending += amount); senão SALDO_INSUFICIENTE;
  2. payout com `litoshi = (amountCoins − feeCoins) × 100` (inteiro §20);
  3. SUCESSO: pending −= amount (total diminui) + `withdrawals/{clientRequestId}`
     `{uid, asset:'LTC', amountCoins, feeCoins, litoshi, destinationMasked,
      status:'completed', providerReference, createdAt}`;
  4. FALHA: estorno INTEGRAL (pending −= amount, available += amount) +
     registro `status:'failed'` + errorCode seguro;
- Idempotência por clientRequestId: o MESMO id NUNCA é reenviado ao provedor;
- Timeout de UI 10s: o botão nunca fica em loop; sem resultado em 10s o app
  avisa "ainda processando" e continua aguardando o resultado real.

### Rules publicadas (12.18)

- `wallets/{uid}`: update pelo DONO somente se
  `(available+pending)` NUNCA aumentar **e** `lifetimeEarned` intacto
  (anti-inflação; saldos são strings decimais ⇒ conversão `int()` nas rules).
  Crédito continua EXCLUSIVAMENTE via Admin SDK.
- `withdrawals/{id}`: create se `data.uid == auth.uid` com status final tipado
  (`completed`/`failed`); read owner; update/delete negados ao cliente.
- Publicadas via CLI (`npx firebase-tools deploy --only firestore:rules`,
  conta mustarda0245) — o caminho da service account segue 403 IAM.

### RISCOS aceitos pela decisão

1. **Chave no APK**: debug/local usa a chave temporária gitignored; qualquer
   build distribuído expõe a chave embutida (ofuscamento não é segredo).
   Mitigação: chave temporária de saldo quase zero + troca por --dart-define.
2. **Timeout ambíguo**: se o HTTP estourar o timeout após o provedor aceitar o
   envio, o cliente pode estornar um pagamento que aconteceu. Valores mínimos
   tornam o prejuízo máximo desprezível; monitorar `withdrawals`.
3. **Cliente escreve withdrawals**: um usuário malicioso só consegue criar
   registros do PRÓPRIO uid com status final — sem impacto em saldo alheio.

## 7.8 v6/12.20 — ESPEC OFICIAL + MODO MANUAL DE OPERADOR ALTERNÁVEL

### Provider automático na espec oficial

- POST `https://facetpay.io/api/v1/send`, body **form-urlencoded**
  `{api_key, currency:'LTC', amount:<litoshi INTEIRO>, to_user:<email>}`;
  timeout 15s; NUNCA JSON body; NUNCA GET.
- Sucesso SOMENTE se `JSON.status == 200` (a API NÃO retorna campo `success` —
  parsing anterior gerava falso-negativo e estorno indevido).
- Erros lidos de `JSON.message`; mapeamento: "Invalid API key"→INVALID_API_KEY;
  "Insufficient funds"→INSUFFICIENT_PROVIDER_BALANCE; "invalid amount"→
  INVALID_AMOUNT; "does not exist"/username→EMAIL_NOT_FOUND; rede/5xx→
  PROVIDER_ERROR (indisponível). UI mostra detalhe curto SEM segredo:
  `http=<status> fp=<status json> msg=<message>`.
- Balance opcional no sheet: POST `/api/v1/balance {api_key, currency:'LTC'}`
  exibe "Disponível no provedor: X LTC" e BLOQUEIA valor acima disso.

### MODO MANUAL (`kPayoutMode = 'auto' | 'manual'` em payout_config.dart)

Fluxo manual (provider `ManualProvider`, mesma interface PayoutProvider):

1. Usuário saca ⇒ RESERVA (available−=X, pending+=X; soma constante) +
   doc `withdrawals/{clientRequestId}` com `status:'pending'`;
2. UI: "aguardando pagamento manual do operador";
3. Operador paga na FaucetPay e edita o doc no Console;
4. O app OBSERVA o doc e finaliza sozinho:
   - status → `'completed'` ⇒ pending −= X (**total DIMINUI**) + histórico completed;
   - status → `'failed'` ⇒ pending −= X e available += X (**estorno integral**)
     + histórico failed.

Rules: `withdrawals/{id}` create owner com status `pending|completed|failed`;
read owner; **update/delete NEGADOS ao cliente** (só o Console/Admin muda o
status — Console bypassa rules).

### GUIA DO OPERADOR (pagamento manual passo a passo)

1. **Consultar pendentes**: Firebase Console → Firestore → coleção
   `withdrawals` → filtre docs com `status == 'pending'`. Campos relevantes:
   `destinationMasked` (e-mail mascarado), `litoshi` (valor a pagar),
   `amountCoins`, `createdAt`.
2. **Pagar na FaucetPay**: login na FaucetPay → Withdraw → para o e-mail
   COMPLETO correspondente à máscara do doc (o e-mail completo está no app do
   usuário; a máscara identifica o dono) → valor EXATO em LTC
   (`litoshi ÷ 100.000.000`).
3. **Finalizar no Console**: editar o MESMO doc `withdrawals/{id}`:
   - pago com sucesso ⇒ `status: 'completed'` + `providerReference: '<id da
     FaucetPay, ex.: 123456>'`;
   - não pagou / erro ⇒ `status: 'failed'` (o app estorna sozinho).
4. Em ≤ instantes o app do usuário liquida: débito final (completed) ou
   estorno visível no saldo disponível (failed) + entrada no histórico.

> Alternância de modo: editar `kPayoutMode` em
> `lib/core/config/payout_config.dart` (gitignored) ou buildar com
> `--dart-define=PAYOUT_MODE=manual`. Default: 'auto'.

### Procedimento de TROCA DA CHAVE (pós-testes — AÇÃO HUMANA)

1. Confirmar as duas provas E2E no dispositivo (completed + failed/estorno);
2. **Queimar a chave temporária**: painel FaucetPay → API Keys → excluir;
3. Gerar/inserir a chave OFICIAL **somente** via:
   - release: `--dart-define=FAUCETPAY_API_KEY=<chave-oficial>`; ou
   - edição local do `payout_config.dart` (gitignored — nunca commitar);
4. Verificar que `git status` NUNCA lista `payout_config.dart`.

## 8. Responsáveis e incidentes

- **Owner:** dono do repo (único com acesso aos secrets no GitHub).
- **Troca de chave:** `gh secret set FAUCETPAY_API_KEY` (nome apenas; valor nunca em chat/log).
- **Suspeita de chave vazrada:** revogar na FaucetPay → cadastrar nova → rodar `payoutProbe`
   → se necessário rollback para `test` durante a troca.
- **Falha de payout de usuário:** código seguro em `withdrawals/{id}.errorCode`;
   estorno automático + auditoria `WITHDRAWAL_FAILED`/`REWARD_REVERSED`.

## 9. Garantias de segurança

- A chave da FaucetPay existe SOMENTE como secret do runner; nunca é impressa.
- Destino completo (e-mail/endereço) nunca vai para logs/auditoria — apenas a
  máscara (`ow***@example.com` / `bc1q…080`).
- Nenhum payout real por padrão: exige `PAYOUT_MODE=live` + ação humana explícita.
- Idempotência: `clientRequestId` como ID do withdrawal ⇒ crash entre reserva e payout
   retoma SEM duplicar pagamento.

## COMPRA E UPGRADE IMEDIATOS (DECISÃO DO DONO)

Compras e upgrades de máquinas são processados IMEDIATAMENTE no cliente via transação
Firestore; valida-se apenas o saldo real (wallets/{uid}) e os valores ancorados no
catálogo config/machines pelas rules. Exceção deliberada à autoridade do runner (doc 05
§15) por decisão do dono. Runner mantém blocos/sessões/missões.

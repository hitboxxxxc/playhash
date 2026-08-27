// payout_config.dart — ARQUIVO GITIGNORED (NUNCA versionar!).
//
// DECISÃO DO DONO (12.18): o payout FaucetPay roda NO CLIENTE com uma chave
// TEMPORÁRIA de saldo quase zero para testes. A chave OFICIAL entra depois
// por --dart-define no build release (sem editar código) ou editando este
// arquivo localmente (gitignored).
//
// ⚠ SEGUANÇA:
//  - Esta chave NUNCA deve aparecer em logs, relatórios, chat ou Git.
//  - Após os testes, EXCLUIR a chave temporária no painel da FaucetPay
//    ("queimar" a chave) e inserir a oficial via --dart-define.
//
// Build release com a chave oficial (exemplo):
//   flutter build apk --release \
//     --dart-define=FAUCETPAY_API_KEY=<chave-oficial>

/// Chave TEMPORÁRIA da FaucetPay (saldo quase zero) — SOMENTE para testes
/// locais/debug. Queimar no painel FaucetPay após o E2E.
const String kTempFaucetPayApiKey =
    '247fb26094a10ef9c51496c6d6ce0fc281995846723d97081518f84893557ed0';

/// Chave efetiva usada pelo cliente: a oficial vence via --dart-define;
/// em ausência dela (debug local), usa a temporária deste arquivo.
const String kFaucetPayApiKey = String.fromEnvironment(
  'FAUCETPAY_API_KEY',
  defaultValue: kTempFaucetPayApiKey,
);

// ---- MODO DE OPERAÇÃO DO PAYOUT (12.20) -------------------------------------

/// 'auto'   = FaucetPay direto do cliente (provider automático);
/// 'manual' = operador paga pelo Console/FaucetPay e define o status do doc
///            `withdrawals/{id}` ('completed'/'failed'); o app finaliza ou
///            estorna sozinho ao observar a transição.
/// Default 'auto'. Em release também aceita --dart-define=PAYOUT_MODE=manual.
const String kPayoutMode = String.fromEnvironment(
  'PAYOUT_MODE',
  defaultValue: 'auto',
);

// ---- PARÂMETROS DE SAQUE (config local; exibição derivada) -----------------

/// Conversão FIXA: 1 COIN = 100 litoshi = 0,000001 LTC.
const int kLitoshiPerCoin = 100;

/// Taxa da plataforma: 25 COIN por saque.
const int kFeeCoins = 25;

/// Mínimo de saque: 50 COIN (recebido mínimo = 25 COIN = 0,000025 LTC).
const int kMinWithdrawCoins = 50;

/// Teto por saque (ajustável pelo dono): 100.000 COIN.
const int kMaxPerWithdrawalCoins = 100000;

/// Placeholder futuro para regras de assinante (premium).
const int kSubscriberMinWithdrawCoins = 10;
const int kSubscriberFeeCoins = 0;

/// Rótulo de exibição da conversão.
const String kDisplayRate = '1 COIN = 0,000001 LTC';

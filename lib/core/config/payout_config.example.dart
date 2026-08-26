// payout_config.example.dart — MODELO commitado SEM chave (seguro).
//
// Para rodar o app com payout no cliente, copie este arquivo para
// `payout_config.dart` (GITIGNORED — nunca versionar a chave!) e cole a sua
// chave temporária/de teste no placeholder abaixo.
//
// Em RELEASE, prefira injetar a chave oficial sem editar código:
//   flutter build apk --release \
//     --dart-define=FAUCETPAY_API_KEY=<chave-oficial>

/// Placeholder — SUBSTITUA pela chave temporária de TESTES (saldo ~zero).
const String kTempFaucetPayApiKey = '<COLE_A_CHAVE_TEMPORARIA_AQUI>';

/// Chave efetiva: oficial via --dart-define vence; senão usa a temporária.
const String kFaucetPayApiKey = String.fromEnvironment(
  'FAUCETPAY_API_KEY',
  defaultValue: kTempFaucetPayApiKey,
);

// ---- MODO DE OPERAÇÃO DO PAYOUT (12.20) -------------------------------------

/// 'auto' = payout direto na FaucetPay | 'manual' = operador paga e define o
/// status do doc withdrawals/{id} pelo Firebase Console (app finaliza/estorna
/// sozinho). Default 'auto'; release aceita --dart-define=PAYOUT_MODE=manual.
const String kPayoutMode = String.fromEnvironment(
  'PAYOUT_MODE',
  defaultValue: 'auto',
);

// ---- PARÂMETROS DE SAQUE (config local; exibição derivada) -----------------

/// Conversão FIXA: 1 COIN = 100 litoshi = 0,000001 LTC.
const int kLitoshiPerCoin = 100;

/// Taxa da plataforma: 2 COIN por saque.
const int kFeeCoins = 2;

/// Mínimo de saque: 3 COIN (recebido mínimo = 1 COIN = 0,000001 LTC).
const int kMinWithdrawCoins = 3;

/// Teto por saque (ajustável pelo dono): 100.000 COIN.
const int kMaxPerWithdrawalCoins = 100000;

/// Rótulo de exibição da conversão.
const String kDisplayRate = '1 COIN = 0,000001 LTC';

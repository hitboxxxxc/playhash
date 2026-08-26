import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/config/payout_config.dart';
import 'payout_provider.dart';

/// Mapeia a mensagem crua da API FaucetPay (`/api/v1/send`) para um código
/// SEGURO (`PayoutErrorCodes`). Função PURA — testável sem rede.
///
/// ESPEC OFICIAL (12.20): sucesso SOMENTE com JSON `status == 200`; erros
/// lidos de JSON `message`. Matching por substring em caixa baixa, na ORDEM
/// de especificidade ("Invalid API key" antes de tudo; "does not exist" /
/// username ⇒ e-mail não cadastrado). NUNCA inclui e-mail/chave no retorno.
///
/// 12.22: fp=456 ("The recipient is not payable — no user owns that
/// address") ⇒ DESTINO_NAO_VINCULADO (e-mail/endereço sem conta FaucetPay).
String mapFaucetPaySendError(String rawMessage, {Object? fpStatus}) {
  final String msg = rawMessage.toLowerCase();
  // fp=456 ⇒ destino (e-mail OU endereço) NÃO vinculado a uma conta
  // FaucetPay. Checado ANTES de tudo — mensagem específica na UI.
  if (fpStatus == 456 ||
      msg.contains('does not belong') ||
      msg.contains('no user owns')) {
    return PayoutErrorCodes.unlinkedDestination;
  }
  if (msg.contains('invalid api key') || msg.contains('missing api key')) {
    return PayoutErrorCodes.invalidApiKey;
  }
  if (msg.contains('insufficient')) {
    return PayoutErrorCodes.insufficientProviderBalance;
  }
  if (msg.contains('invalid amount') ||
      msg.contains('amount too low') ||
      msg.contains('amount_too_low')) {
    return PayoutErrorCodes.invalidAmount;
  }
  if (msg.contains('does not exist') ||
      msg.contains('username') ||
      msg.contains('user_not_found') ||
      msg.contains('email')) {
    return PayoutErrorCodes.emailNotFound;
  }
  if (msg.contains('rate limit') || msg.contains('too many')) {
    return PayoutErrorCodes.rateLimit;
  }
  return PayoutErrorCodes.providerError;
}

/// Parsing PURO do campo `balance` da resposta de saldo (12.22): o valor
/// bruto JÁ está na MENOR unidade do ativo (litoshi p/ LTC — ex.: raw
/// `1270355` ⇒ 0,01270355 LTC). NUNCA multiplica por 1e8 para inteiro.
/// Tolerante a string numérica; decimal legado (ex.: "0.00012345") é
/// convertido por 1e8 por segurança. Retorna null se não parseável.
BigInt? parseBalanceRawToLitoshi(Object? raw) {
  if (raw is int) return BigInt.from(raw);
  if (raw is num) {
    final double d = raw.toDouble();
    if (d == d.truncateToDouble()) return BigInt.from(d.toInt());
    return BigInt.from((d * 1e8).round());
  }
  if (raw is String) {
    final BigInt? asInt = BigInt.tryParse(raw.trim());
    if (asInt != null) return asInt;
    final double? asDouble = double.tryParse(raw.trim());
    if (asDouble != null) return BigInt.from((asDouble * 1e8).round());
  }
  return null;
}

/// Detalhe técnico CURTO e SEGURO p/ UI/log: `http=... fp=... msg=...`
/// (status HTTP, status JSON e message do provedor). Truncado; NUNCA contém
/// chave/e-mail (a message do provedor não os inclui; truncagem limita
/// qualquer surpresa).
String buildFaucetPayDetail({
  required int httpStatus,
  Object? fpStatus,
  required String message,
}) {
  final String msg = message.length > 120
      ? '${message.substring(0, 120)}…'
      : message;
  return 'http=$httpStatus fp=${fpStatus ?? '-'} msg=$msg';
}

/// Cliente FaucetPay NO CLIENTE (decisão do dono, 12.18).
///
/// POST `https://faucetpay.io/api/v1/send` (form-urlencoded) com os campos
/// `api_key`, `currency:'LTC'`, `amount` (litoshi inteiro) e o recipiente:
/// conforme a doc oficial, o destino pode ser e-mail/username OU endereço
/// vinculado (linked address). A doc traz o parâmetro `to` na tabela e
/// `to_user` no exemplo curl — enviamos AMBOS com o mesmo valor para
/// compatibilidade com as duas gerações da API (12.22).
///
/// Segurança:
///  - timeout fixo de 15s; SEM retry automático (idempotência: resposta
///    ambígua não é reenviada pelo próprio cliente — o serviço de saque
///    decide o estorno);
///  - a chave vem de [kFaucetPayApiKey] (--dart-define ou config local
///    gitignored) e JAMAIS aparece em logs/erros;
///  - o destino vai SOMENTE no corpo da requisição — nunca em logs/erros.
class FaucetPayProvider implements PayoutProvider {
  FaucetPayProvider({
    String? apiKey,
    http.Client? client,
    Uri? endpoint,
    this.requestTimeout = const Duration(seconds: 15),
  })  : _apiKey = apiKey ?? kFaucetPayApiKey,
        _clientOverride = client,
        _endpointOverride = endpoint;

  final String _apiKey;
  final http.Client? _clientOverride;
  final Uri? _endpointOverride;

  /// Timeout fixo por tentativa (15s).
  final Duration requestTimeout;

  static const String sendUrl = 'https://faucetpay.io/api/v1/send';

  /// Consulta OPCIONAL de saldo: POST /api/v1/getbalance (doc oficial
  /// 12.22), com fallback legado para /api/v1/balance.
  static const String getBalanceUrl =
      'https://faucetpay.io/api/v1/getbalance';
  static const String balanceUrl = 'https://faucetpay.io/api/v1/balance';

  http.Client get _client => _clientOverride ?? http.Client();

  @override
  Future<PayoutResult> sendPayout({
    required String destination,
    required int amountLitoshi,
  }) async {
    // Validação local do valor (inteiro positivo — §20 precisão inteira).
    if (amountLitoshi <= 0) {
      return const PayoutResult.failed(PayoutErrorCodes.invalidAmount);
    }
    final String dest = destination.trim();
    if (dest.isEmpty) {
      return const PayoutResult.failed(PayoutErrorCodes.unlinkedDestination);
    }

    final Uri endpoint =
        _endpointOverride ?? Uri.parse(sendUrl);
    try {
      final http.Response res = await _client
          .post(
            endpoint,
            headers: <String, String>{
              'content-type': 'application/x-www-form-urlencoded',
            },
            body: <String, String>{
              'api_key': _apiKey,
              'currency': 'LTC',
              // INTEIRO em litoshi — nunca float, nunca string decimal.
              'amount': amountLitoshi.toString(),
              // Recipiente conforme doc oficial: tabela usa `to`
              // ("email, username, or wallet address"); exemplo curl usa
              // `to_user`. Enviados AMBOS com o mesmo valor (12.22).
              'to': dest,
              'to_user': dest,
            },
          )
          .timeout(requestTimeout);

      // ESPEC OFICIAL: sucesso SOMENTE se JSON.status == 200. A API NÃO
      // retorna campo `success` — parsing anterior era falso-negativo.
      final Map<String, dynamic>? body = _decodeBody(res.body);
      final Object? fpStatus = body?['status'];
      if (fpStatus == 200) {
        final String payoutId = body?['payout_id']?.toString() ?? '';
        return PayoutResult.completed(
          payoutId.isEmpty ? 'FP-unknown' : 'FP-$payoutId',
        );
      }
      // Resposta DEFINITIVA de erro — sem retry (evita pagamento duplicado).
      final String rawMessage = body?['message']?.toString() ?? '';
      final String detail = buildFaucetPayDetail(
        httpStatus: res.statusCode,
        fpStatus: fpStatus,
        message: rawMessage,
      );
      developer.log('faucetpay send failed $detail',
          name: 'FaucetPayProvider');
      return PayoutResult.failed(
          mapFaucetPaySendError(rawMessage, fpStatus: fpStatus),
          detail: detail);
    } on TimeoutException {
      developer.log('faucetpay send timeout', name: 'FaucetPayProvider');
      return const PayoutResult.failed(PayoutErrorCodes.providerError,
          detail: 'http=- fp=- msg=timeout 15s');
    } on SocketException catch (_) {
      developer.log('faucetpay send socket error',
          name: 'FaucetPayProvider');
      return const PayoutResult.failed(PayoutErrorCodes.providerError,
          detail: 'http=- fp=- msg=socket error');
    } on http.ClientException catch (_) {
      developer.log('faucetpay send client error',
          name: 'FaucetPayProvider');
      return const PayoutResult.failed(PayoutErrorCodes.providerError,
          detail: 'http=- fp=- msg=client error');
    } on Exception catch (e) {
      // Qualquer outro erro: log seguro (tipo apenas), código genérico.
      developer.log('faucetpay send error type=${e.runtimeType}',
          name: 'FaucetPayProvider');
      return PayoutResult.failed(PayoutErrorCodes.providerError,
          detail: 'http=- fp=- msg=type=${e.runtimeType}');
    }
  }

  /// Saldo LTC disponível no provedor (OPCIONAL — espec oficial):
  /// POST form-urlencoded `{api_key, currency:'LTC'}` em `/api/v1/getbalance`
  /// (doc oficial 12.22), com fallback para `/api/v1/balance`.
  ///
  /// A resposta traz `balance` como INTEIRO na MENOR unidade do ativo
  /// (litoshi p/ LTC; ex.: `"balance": 1270355` = 0,01270355 LTC). O parsing
  /// ([parseBalanceRawToLitoshi]) NUNCA multiplica por 1e8 — o valor bruto
  /// JÁ está em litoshi. Retorna litoshi inteiro ou null (best-effort).
  Future<BigInt?> fetchBalanceLitoshi() async {
    for (final Uri url in <Uri>[Uri.parse(getBalanceUrl), Uri.parse(balanceUrl)]) {
      try {
        final http.Response res = await _client
            .post(
              url,
              headers: <String, String>{
                'content-type': 'application/x-www-form-urlencoded',
              },
              body: <String, String>{'api_key': _apiKey, 'currency': 'LTC'},
            )
            .timeout(requestTimeout);
        final Map<String, dynamic>? body = _decodeBody(res.body);
        if (body?['status'] != 200) continue; // tenta endpoint alternativo
        final BigInt? litoshi = parseBalanceRawToLitoshi(body?['balance']);
        if (litoshi != null) return litoshi;
      } on Exception catch (e) {
        developer.log('faucetpay balance error type=${e.runtimeType}',
            name: 'FaucetPayProvider');
      }
    }
    return null;
  }

  /// Decodifica o JSON da resposta com tolerância (corpo inválido ⇒ null).
  static Map<String, dynamic>? _decodeBody(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException catch (_) {
      // corpo não-JSON
    }
    return null;
  }
}

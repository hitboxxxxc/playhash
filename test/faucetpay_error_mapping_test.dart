import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:playhash/core/services/payout/faucetpay_provider.dart';
import 'package:playhash/core/services/payout/payout_provider.dart';

void main() {
  group('mapFaucetPaySendError (mapeamento puro p/ códigos seguros)', () {
    test('mensagens de usuário/e-mail inexistente ⇒ EMAIL_NOT_FOUND', () {
      expect(
        mapFaucetPaySendError('Invalid or missing username/email'),
        PayoutErrorCodes.emailNotFound,
      );
      expect(
        mapFaucetPaySendError('USER_NOT_FOUND'),
        PayoutErrorCodes.emailNotFound,
      );
      expect(
        mapFaucetPaySendError('Email not found'),
        PayoutErrorCodes.emailNotFound,
      );
    });

    test('valor baixo/inválido ⇒ INVALID_AMOUNT', () {
      expect(
        mapFaucetPaySendError('Amount too low'),
        PayoutErrorCodes.invalidAmount,
      );
      expect(
        mapFaucetPaySendError('invalid amount'),
        PayoutErrorCodes.invalidAmount,
      );
    });

    test('chave inválida ⇒ INVALID_API_KEY (prioridade máxima)', () {
      expect(
        mapFaucetPaySendError('Invalid API key'),
        PayoutErrorCodes.invalidApiKey,
      );
      expect(
        mapFaucetPaySendError('Missing API key'),
        PayoutErrorCodes.invalidApiKey,
      );
    });

    test('"User does not exist" ⇒ EMAIL_NOT_FOUND', () {
      expect(
        mapFaucetPaySendError('User does not exist'),
        PayoutErrorCodes.emailNotFound,
      );
    });

    test('fp=456 destino não vinculado ⇒ DESTINO_NAO_VINCULADO (12.22)',
        () {
      expect(
        mapFaucetPaySendError(
          'The address does not belong to any user',
          fpStatus: 456,
        ),
        PayoutErrorCodes.unlinkedDestination,
      );
      // Também pela mensagem, sem o status.
      expect(
        mapFaucetPaySendError('The address does not belong to any user'),
        PayoutErrorCodes.unlinkedDestination,
      );
      // Redação da doc oficial ("recipient is not payable").
      expect(
        mapFaucetPaySendError('No user owns that address', fpStatus: 456),
        PayoutErrorCodes.unlinkedDestination,
      );
    });

    test('saldo do provedor ⇒ INSUFFICIENT_PROVIDER_BALANCE', () {
      expect(
        mapFaucetPaySendError('Insufficient funds'),
        PayoutErrorCodes.insufficientProviderBalance,
      );
    });

    test('rate limit ⇒ RATE_LIMIT', () {
      expect(
        mapFaucetPaySendError('Rate limit exceeded'),
        PayoutErrorCodes.rateLimit,
      );
      expect(
        mapFaucetPaySendError('Too many requests'),
        PayoutErrorCodes.rateLimit,
      );
    });

    test('mensagem desconhecida/vazia ⇒ PROVIDER_ERROR (código genérico)', () {
      expect(mapFaucetPaySendError(''), PayoutErrorCodes.providerError);
      expect(
        mapFaucetPaySendError('weird unexpected failure'),
        PayoutErrorCodes.providerError,
      );
    });
  });

  group('FaucetPayProvider (cliente HTTP)', () {
    const String fakeKey = 'test-key-not-real';
    late List<http.Request> captured;

    FaucetPayProvider providerWith(MockClientHandler handler) {
      captured = <http.Request>[];
      return FaucetPayProvider(
        apiKey: fakeKey,
        client: MockClient((http.Request request) async {
          captured.add(request);
          return handler(request);
        }),
      );
    }

    http.Response jsonBody(Map<String, dynamic> body, [int status = 200]) =>
        http.Response(jsonEncode(body), status,
            headers: <String, String>{
              'content-type': 'application/json',
            });

    test('sucesso SOMENTE com JSON.status==200 (espec oficial) ⇒ FP-<id>',
        () async {
      final FaucetPayProvider provider = providerWith(
        (_) async =>
            jsonBody(<String, dynamic>{'status': 200, 'payout_id': 12345}),
      );
      final PayoutResult result = await provider.sendPayout(
        destination: 'owner@example.com',
        amountLitoshi: 800,
      );
      expect(result.success, isTrue);
      expect(result.providerReference, 'FP-12345');
      // Corpo form-urlencoded com campos EXATOS e litoshi INTEIRO.
      expect(captured, hasLength(1));
      final http.Request req = captured.first;
      expect(req.method, 'POST');
      expect(req.headers['content-type'],
          contains('application/x-www-form-urlencoded'));
      final String body = req.body;
      expect(body, contains('currency=LTC'));
      expect(body, contains('amount=800'));
      // Recipiente DUPLO conforme doc oficial: `to` (tabela) e `to_user`
      // (exemplo curl) com o MESMO valor (12.22).
      expect(body, contains(RegExp(r'to_user=owner%40example\.com')));
      expect(body, contains(RegExp(r'[?&]to=owner%40example\.com')));
      expect(body, contains('api_key='));
    });

    test('JSON.status != 200 NUNCA é sucesso (mesmo com payout_id)', () async {
      final FaucetPayProvider provider = providerWith(
        (_) async => jsonBody(<String, dynamic>{
          'status': 400,
          'message': 'Invalid API key',
          'payout_id': 999,
        }),
      );
      final PayoutResult result = await provider.sendPayout(
        destination: 'owner@example.com',
        amountLitoshi: 800,
      );
      expect(result.success, isFalse);
      expect(result.errorCode, PayoutErrorCodes.invalidApiKey);
    });

    test('detalhe técnico SEGURO na falha: http/fp/msg sem segredo', () async {
      final FaucetPayProvider provider = providerWith(
        (_) async => jsonBody(<String, dynamic>{
          'status': 400,
          'message': 'Invalid API key',
        }),
      );
      final PayoutResult result = await provider.sendPayout(
        destination: 'owner@example.com',
        amountLitoshi: 800,
      );
      expect(result.detail, isNotNull);
      expect(result.detail, contains('http=200'));
      expect(result.detail, contains('fp=400'));
      expect(result.detail, contains('msg=Invalid API key'));
      expect(result.detail, isNot(contains(fakeKey)));
    });

    test(
        'balance: POST /api/v1/getbalance ⇒ raw JÁ em litoshi '
        '(1270355 raw ⇒ 0,01270355 LTC — SEM multiplicar por 1e8)', () async {
      late http.Request capturedRequest;
      final FaucetPayProvider provider = FaucetPayProvider(
        apiKey: fakeKey,
        client: MockClient((http.Request request) async {
          capturedRequest = request;
          return jsonBody(<String, dynamic>{
            'status': 200,
            'balance': 1270355,
            'currency': 'LTC',
          });
        }),
      );
      final BigInt? litoshi = await provider.fetchBalanceLitoshi();
      expect(litoshi, BigInt.from(1270355)); // 0.01270355 LTC
      expect(capturedRequest.method, 'POST');
      expect(capturedRequest.url.toString(),
          'https://faucetpay.io/api/v1/getbalance');
      expect(capturedRequest.headers['content-type'],
          contains('application/x-www-form-urlencoded'));
      expect(capturedRequest.body, contains('currency=LTC'));
    });

    test('balance: string numérica inteira também é aceita', () async {
      final FaucetPayProvider provider = FaucetPayProvider(
        apiKey: fakeKey,
        client: MockClient((_) async => jsonBody(<String, dynamic>{
              'status': 200,
              'balance': '49900',
              'currency': 'LTC',
            })),
      );
      expect(await provider.fetchBalanceLitoshi(), BigInt.from(49900));
    });

    test('balance: decimal legado ("0.00012345") ⇒ convertido p/ litoshi',
        () async {
      final FaucetPayProvider provider = FaucetPayProvider(
        apiKey: fakeKey,
        client: MockClient((_) async => jsonBody(<String, dynamic>{
              'status': 200,
              'balance': '0.00012345',
              'currency': 'LTC',
            })),
      );
      expect(await provider.fetchBalanceLitoshi(), BigInt.from(12345));
    });

    test('balance: getbalance indisponível ⇒ fallback /api/v1/balance',
        () async {
      final List<String> urls = <String>[];
      final FaucetPayProvider provider = FaucetPayProvider(
        apiKey: fakeKey,
        client: MockClient((http.Request request) async {
          urls.add(request.url.toString());
          if (request.url.toString().endsWith('/getbalance')) {
            return jsonBody(<String, dynamic>{
              'status': 401,
              'message': 'Invalid API key',
            });
          }
          return jsonBody(<String, dynamic>{
            'status': 200,
            'balance': 777,
            'currency': 'LTC',
          });
        }),
      );
      expect(await provider.fetchBalanceLitoshi(), BigInt.from(777));
      expect(urls, hasLength(2));
      expect(urls.first, endsWith('/getbalance'));
      expect(urls.last, endsWith('/balance'));
    });

    test('balance indisponível/erro ⇒ null (best-effort)', () async {
      final FaucetPayProvider provider = providerWith(
        (_) async => jsonBody(<String, dynamic>{
          'status': 401,
          'message': 'Invalid API key',
        }),
      );
      expect(await provider.fetchBalanceLitoshi(), isNull);
    });

    test('amount <= 0 ⇒ INVALID_AMOUNT sem chamada HTTP', () async {
      bool called = false;
      final FaucetPayProvider provider = FaucetPayProvider(
        apiKey: fakeKey,
        client: MockClient((http.Request request) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      final PayoutResult result = await provider.sendPayout(
        destination: 'owner@example.com',
        amountLitoshi: 0,
      );
      expect(result.success, isFalse);
      expect(result.errorCode, PayoutErrorCodes.invalidAmount);
      expect(called, isFalse);
    });

    test('e-mail inexistente na FaucetPay ⇒ EMAIL_NOT_FOUND', () async {
      final FaucetPayProvider provider = providerWith(
        (_) async => jsonBody(<String, dynamic>{
          'success': false,
          'message': 'Invalid or missing username/email',
        }),
      );
      final PayoutResult result = await provider.sendPayout(
        destination: 'ghost@example.com',
        amountLitoshi: 800,
      );
      expect(result.success, isFalse);
      expect(result.errorCode, PayoutErrorCodes.emailNotFound);
    });

    test('provedor sem saldo ⇒ INSUFFICIENT_PROVIDER_BALANCE', () async {
      final FaucetPayProvider provider = providerWith(
        (_) async => jsonBody(<String, dynamic>{
          'success': false,
          'message': 'Insufficient funds',
        }),
      );
      final PayoutResult result = await provider.sendPayout(
        destination: 'owner@example.com',
        amountLitoshi: 800,
      );
      expect(result.errorCode, PayoutErrorCodes.insufficientProviderBalance);
    });

    test('HTTP 500 ⇒ PROVIDER_ERROR (sem retry no cliente)', () async {
      final FaucetPayProvider provider =
          providerWith((_) async => http.Response('server error', 500));
      final PayoutResult result = await provider.sendPayout(
        destination: 'owner@example.com',
        amountLitoshi: 800,
      );
      expect(result.success, isFalse);
      expect(result.errorCode, PayoutErrorCodes.providerError);
      // SEM retry automático: exatamente UMA chamada.
      expect(captured, hasLength(1));
    });

    test('exceção de rede ⇒ PROVIDER_ERROR', () async {
      final FaucetPayProvider provider = FaucetPayProvider(
        apiKey: fakeKey,
        client: MockClient((http.Request request) async {
          throw Exception('network down');
        }),
      );
      final PayoutResult result = await provider.sendPayout(
        destination: 'owner@example.com',
        amountLitoshi: 800,
      );
      expect(result.success, isFalse);
      expect(result.errorCode, PayoutErrorCodes.providerError);
    });

    test('erros NUNCA contêm a chave nem o e-mail completo', () async {
      final FaucetPayProvider provider = providerWith(
        (_) async => jsonBody(<String, dynamic>{
          'success': false,
          'message': 'Invalid or missing username/email',
        }),
      );
      final PayoutResult result = await provider.sendPayout(
        destination: 'secret.owner@example.com',
        amountLitoshi: 800,
      );
      expect(result.errorCode, isNot(contains(fakeKey)));
      expect(result.errorCode, isNot(contains('secret.owner@example.com')));
      expect(result.providerReference, isNull);
    });
  });
}

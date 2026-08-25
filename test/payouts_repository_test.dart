import 'package:flutter_test/flutter_test.dart';
import 'package:playhash/data/repositories/payouts_repository.dart';

/// 12.9 — parser TOLERANTE a legado de config/payouts:
/// - assets como LISTA (v1–v3) ou MAPA keyed por id (v4);
/// - ids em qualquer caixa ⇒ UPPERCASE;
/// - aliases antigos: assetUnitPerCoinScaled→litoshiPerCoin,
///   minWithdrawUnits/feeUnits (units) → coins ×1e6;
/// - doc ausente/ilegível NUNCA bloqueia (lista vazia ⇒ UI usa fallback).
void main() {
  group('PayoutsConfigModel.fromMap — legado ARRAY (v1–v3)', () {
    test('ids lower/upper normalizados; campos v3 lidos', () {
      final PayoutsConfigModel cfg = PayoutsConfigModel.fromMap(<String, dynamic>{
        'version': 3,
        'assets': <dynamic>[
          <String, dynamic>{
            'id': 'ltc',
            'network': 'FaucetPayEmail',
            'enabled': true,
            'litoshiPerCoin': 100,
            'minWithdrawCoins': 20,
            'feeCoins': 2,
          },
          <String, dynamic>{'id': 'BTC', 'enabled': false},
        ],
      });
      expect(cfg.assets, hasLength(2));
      expect(cfg.assets[0].id, 'LTC');
      expect(cfg.assets[0].enabled, isTrue);
      expect(cfg.assets[0].minWithdrawUnits, BigInt.from(20000000));
      expect(cfg.assets[0].feeUnits, BigInt.from(2000000));
      expect(cfg.assets[0].litoshiPerCoin, 100);
      expect(cfg.assets[1].id, 'BTC');
      expect(cfg.assets[1].enabled, isFalse);
    });

    test('aliases antigos (assetUnitPerCoinScaled/minWithdrawUnits) mapeados', () {
      final PayoutsConfigModel cfg = PayoutsConfigModel.fromMap(<String, dynamic>{
        'assets': <dynamic>[
          <String, dynamic>{
            'id': 'LTC',
            'enabled': true,
            'assetUnitPerCoinScaled': 100, // alias de litoshiPerCoin
            'minWithdrawUnits': 20000000, // units ⇒ 20 coins
            'feeUnits': 2000000, // units ⇒ 2 coins
          },
        ],
      });
      expect(cfg.assets.single.litoshiPerCoin, 100);
      expect(cfg.assets.single.minWithdrawUnits, BigInt.from(20000000));
      expect(cfg.assets.single.feeUnits, BigInt.from(2000000));
    });
  });

  group('PayoutsConfigModel.fromMap — canônico MAPA (v4)', () {
    test('mapa keyed por id UPPER lido direto', () {
      final PayoutsConfigModel cfg = PayoutsConfigModel.fromMap(<String, dynamic>{
        'version': 4,
        'assets': <String, dynamic>{
          'LTC': <String, dynamic>{
            'enabled': true,
            'litoshiPerCoin': 100,
            'minWithdrawCoins': 20,
            'feeCoins': 2,
            'providerMinLitoshi': null,
            'displayRate': '1 COIN = 0,000001 LTC',
          },
          'DOGE': <String, dynamic>{'enabled': false},
        },
      });
      expect(cfg.assets, hasLength(2));
      final PayoutAsset ltc = cfg.assets.firstWhere((PayoutAsset a) => a.id == 'LTC');
      expect(ltc.enabled, isTrue);
      expect(ltc.minWithdrawUnits, BigInt.from(20000000));
      expect(ltc.feeUnits, BigInt.from(2000000));
      expect(ltc.displayRate, '1 COIN = 0,000001 LTC');
      expect(cfg.assets.firstWhere((PayoutAsset a) => a.id == 'DOGE').enabled, isFalse);
    });
  });

  group('tolerância a falha — NUNCA bloqueia o saque por parse', () {
    test('doc sem assets ⇒ lista vazia (UI aplica fallback LTC)', () {
      final PayoutsConfigModel cfg = PayoutsConfigModel.fromMap(<String, dynamic>{
        'version': 4,
      });
      expect(cfg.assets, isEmpty);
    });

    test('entries malformadas são ignoradas sem crash', () {
      final PayoutsConfigModel cfg = PayoutsConfigModel.fromMap(<String, dynamic>{
        'assets': <dynamic>[
          <String, dynamic>{'enabled': true}, // sem id ⇒ ignorado
          'lixo', // não-mapa ⇒ ignorado
        ],
      });
      expect(cfg.assets, isEmpty);
    });
  });
}

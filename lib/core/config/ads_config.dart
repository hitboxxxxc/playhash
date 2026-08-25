import 'package:flutter/foundation.dart';

/// Configuração de ANÚNCIOS (doc 04) — fonte única de verdade no cliente.
///
/// PROTEÇÃO DA CONTA ADMOB:
/// - Builds DEBUG usam SEMPRE as unidades de TESTE do Google (nunca geram
///   receita nem violam políticas — cliques em anúncios reais em dev podem
///   suspender a conta);
/// - IDs REAIS só entram em RELEASE (kDebugMode == false).
///
/// O APPLICATION_ID (manifest) é o mesmo para debug/release — exigência do
/// SDK; as UNITS é que são trocadas aqui.
abstract final class AdsConfig {
  /// APPLICATION_ID declarado no AndroidManifest.xml (não é segredo).
  static const String applicationId =
      'ca-app-pub-9000000707740805~6197161075';

  /// Unidade REWARDED de TESTE do Google (fixa, pública, segura p/ debug).
  static const String rewardedUnitIdTest =
      'ca-app-pub-3940256099942544/5224354917';

  /// Unidade REWARDED REAL (release) da conta PlayHash.
  static const String rewardedUnitIdRelease =
      'ca-app-pub-9000000707740805/2267700524';

  /// Unit ID do rewarded conforme o modo de build.
  static String get rewardedUnitId =>
      kDebugMode ? rewardedUnitIdTest : rewardedUnitIdRelease;

  /// ENCAIXE FUTURO (banner): ainda NÃO existe bloco de banner na conta
  /// AdMob. Quando existir, adicionar `bannerUnitIdRelease` e expor
  /// `bannerUnitId` com o mesmo padrão kDebugMode. Por ora, sempre null
  /// (nenhum banner é carregado em nenhum build).
  static const String? bannerUnitId = null;

  /// Dispositivos de teste registrados SOMENTE em debug (hash do dispositivo
  /// de desenvolvimento). Em release a lista fica vazia.
  static List<String> get testDevices =>
      kDebugMode ? <String>['EMULATOR'] : const <String>[];
}

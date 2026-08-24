import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cache_policy.dart';
import '../data/repositories/machines_repository.dart';
import '../data/repositories/mining_repository.dart';
import '../data/repositories/power_repository.dart';
import '../data/repositories/profile_repository.dart';
import '../data/repositories/wallet_repository.dart';
import 'services/auth_service.dart';
import 'services/cloud_functions_service.dart';

/// Provider único do serviço de autenticação (Riverpod é o state management
/// exclusivo do projeto). Em testes, as telas aceitam override deste provider
/// ou injeção direta via construtor.
final Provider<AuthServiceApi> authServiceProvider =
    Provider<AuthServiceApi>((Ref ref) => FirebaseAuthService());

/// Política de cache compartilhada da camada de dados.
final Provider<CachePolicy> cachePolicyProvider =
    Provider<CachePolicy>((Ref ref) => CachePolicy());

/// Repositório de perfil próprio (`users/{uid}`), cache-first.
final Provider<ProfileRepositoryApi> profileRepositoryProvider =
    Provider<ProfileRepositoryApi>(
  (Ref ref) => ProfileRepository(ref.watch(cachePolicyProvider)),
);

/// Serviço de chamadas ao backend via Cloud Functions (stub até o deploy).
final Provider<CloudFunctionsServiceApi> cloudFunctionsServiceProvider =
    Provider<CloudFunctionsServiceApi>((Ref ref) => CloudFunctionsService());

/// Repositório de poder próprio (`power/{uid}`), cache-first, só leitura.
final Provider<PowerRepositoryApi> powerRepositoryProvider =
    Provider<PowerRepositoryApi>(
  (Ref ref) => PowerRepository(ref.watch(cachePolicyProvider)),
);

/// Repositório de carteira própria (`wallets/{uid}`), cache-first, só leitura.
final Provider<WalletRepositoryApi> walletRepositoryProvider =
    Provider<WalletRepositoryApi>(
  (Ref ref) => WalletRepository(ref.watch(cachePolicyProvider)),
);

/// Repositório de máquinas (`machines/{uid}/items`), cache-first, só leitura.
final Provider<MachinesRepositoryApi> machinesRepositoryProvider =
    Provider<MachinesRepositoryApi>(
  (Ref ref) => MachinesRepository(ref.watch(cachePolicyProvider)),
);

/// Repositório de mineração (blocos/ligas/histórico), tolerante a ausência
/// de backend: toda falha vira estado vazio — nunca valor inventado.
final Provider<MiningRepositoryApi> miningRepositoryProvider =
    Provider<MiningRepositoryApi>(
  (Ref ref) => MiningRepository(ref.watch(cachePolicyProvider)),
);

/// Stream do perfil próprio (`users/{uid}`) para consumo nas telas.
///
/// Tolerante a falhas: qualquer erro (Firebase indisponível, sessão ausente)
/// resulta em `null` — estado vazio, nunca crash. Atualiza em tempo real se
/// o usuário editar o displayName em outra tela.
final StreamProvider<Map<String, dynamic>?> profileStreamProvider =
    StreamProvider<Map<String, dynamic>?>((Ref ref) async* {
  try {
    final dynamic user = await ref.watch(authServiceProvider).currentUser();
    if (user == null) {
      yield null;
      return;
    }
    yield* ref.watch(profileRepositoryProvider).watchOwnProfile(user.uid as String);
  } catch (_) {
    yield null; // fallback seguro: perfil vazio, sem quebrar a tela
  }
});

/// Uid do usuário autenticado (ou `null`). Tolerante a falhas para uso em
/// telas que precisam salvar preferências.
final FutureProvider<String?> currentUidProvider =
    FutureProvider<String?>((Ref ref) async {
  try {
    final dynamic user = await ref.watch(authServiceProvider).currentUser();
    return user?.uid as String?;
  } catch (_) {
    return null;
  }
});

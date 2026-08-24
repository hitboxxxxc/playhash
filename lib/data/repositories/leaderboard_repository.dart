import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/league_model.dart';

/// Contrato do repositório de ranking — permite fakes nos testes.
abstract interface class LeaderboardRepositoryApi {
  /// Top 100 da liga (`leaderboards/{leagueId}/entries` ordenado por
  /// totalPower desc — query de campo único permitida pelas rules).
  /// Erro/offline propagam para a tela tratar (estados próprios).
  Stream<List<LeaderboardEntry>> watchLeaderboard(String leagueId);
}

/// Repositório do RANKING de ligas. SOMENTE LEITURA — entradas mantidas
/// exclusivamente pelo backend (league_sweep) com maskedName (sem dados
/// pessoais; rules: `allow write: if false`).
class LeaderboardRepository implements LeaderboardRepositoryApi {
  LeaderboardRepository({FirebaseFirestore? firestore}) : _dbOverride = firestore;

  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  @override
  Stream<List<LeaderboardEntry>> watchLeaderboard(String leagueId) {
    return _db
        .collection('leaderboards')
        .doc(leagueId)
        .collection('entries')
        .orderBy('totalPower', descending: true)
        .limit(100)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snap) => <LeaderboardEntry>[
              for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in snap.docs)
                LeaderboardEntry.fromMap(doc.id, doc.data()),
            ]);
  }
}

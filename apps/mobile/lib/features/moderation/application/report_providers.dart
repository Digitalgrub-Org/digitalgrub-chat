import 'package:dg_chat/features/moderation/data/matrix_report_repository.dart';
import 'package:dg_chat/features/moderation/domain/report_repository.dart';
import 'package:dg_chat/matrix/client/matrix_client_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final reportRepositoryProvider = FutureProvider<ReportRepository>((ref) async {
  return MatrixReportRepository(await ref.watch(matrixClientProvider.future));
});

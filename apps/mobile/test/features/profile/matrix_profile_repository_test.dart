import 'dart:typed_data';

import 'package:dg_chat/features/moderation/data/matrix_report_repository.dart';
import 'package:dg_chat/features/moderation/domain/report_repository.dart';
import 'package:dg_chat/features/profile/data/matrix_profile_repository.dart';
import 'package:dg_chat/features/profile/domain/profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide UserProfile;
import 'package:mocktail/mocktail.dart';

class _MockClient extends Mock implements Client {}

void main() {
  late _MockClient client;
  late MatrixProfileRepository profiles;
  late MatrixReportRepository reports;

  setUp(() {
    client = _MockClient();
    profiles = MatrixProfileRepository(client);
    reports = MatrixReportRepository(client);
    when(() => client.userID).thenReturn('@current:test');
    when(() => client.accessToken).thenReturn('token');
    when(() => client.ignoredUsers).thenReturn(const []);
  });

  group('profile edits', () {
    test('rejects a blank display name before contacting the server', () async {
      await expectLater(
        profiles.updateDisplayName('   '),
        throwsA(_hasProfileCode(ProfileFailureCode.invalidDisplayName)),
      );
      verifyNever(() => client.setProfileField(any(), any(), any()));
    });

    test('rejects an over-long about text', () async {
      await expectLater(
        profiles.updateAbout('x' * (maxAboutLength + 1)),
        throwsA(_hasProfileCode(ProfileFailureCode.invalidAbout)),
      );
    });

    test('rejects a malformed mobile number', () async {
      await expectLater(
        profiles.updateMobileNumber('not a number'),
        throwsA(_hasProfileCode(ProfileFailureCode.invalidMobileNumber)),
      );
    });

    test('trims the display name before sending it', () async {
      when(
        () => client.setProfileField(any(), any(), any()),
      ).thenAnswer((_) async => <String, Object?>{});

      await profiles.updateDisplayName('  Renamed user  ');

      verify(
        () => client.setProfileField('@current:test', 'displayname', {
          'displayname': 'Renamed user',
        }),
      ).called(1);
    });

    test('merges private profile fields instead of replacing them', () async {
      when(() => client.accountData).thenReturn({
        MatrixProfileRepository.privateProfileType: BasicEvent(
          type: MatrixProfileRepository.privateProfileType,
          content: {'mobile_number': '+911234567', 'about': 'Existing'},
        ),
      });
      when(
        () => client.setAccountData(any(), any(), any()),
      ).thenAnswer((_) async {});

      await profiles.updateAbout('Updated about');

      final captured =
          verify(
                () => client.setAccountData(
                  '@current:test',
                  MatrixProfileRepository.privateProfileType,
                  captureAny(),
                ),
              ).captured.single
              as Map<String, Object?>;
      expect(captured['about'], 'Updated about');
      // The unrelated field survives the edit.
      expect(captured['mobile_number'], '+911234567');
    });

    test('rejects an avatar above the size ceiling', () async {
      await expectLater(
        profiles.updateAvatar(
          AvatarUpload(bytes: Uint8List(3 * 1024 * 1024), fileName: 'big.jpg'),
        ),
        throwsA(_hasProfileCode(ProfileFailureCode.avatarTooLarge)),
      );
      verifyNever(() => client.setAvatar(any()));
    });
  });

  group('blocking', () {
    test('refuses to block yourself', () async {
      await expectLater(
        profiles.blockUser('@current:test'),
        throwsA(_hasProfileCode(ProfileFailureCode.notPermitted)),
      );
      verifyNever(() => client.ignoreUser(any()));
      verifyNever(() => client.reportUser(any(), any()));
    });

    test('refuses a malformed user id', () async {
      await expectLater(
        profiles.blockUser('not-a-matrix-id'),
        throwsA(_hasProfileCode(ProfileFailureCode.notPermitted)),
      );
    });

    test('blocks and unblocks through the ignore list', () async {
      when(() => client.ignoreUser(any())).thenAnswer((_) async {});
      when(() => client.unignoreUser(any())).thenAnswer((_) async {});
      when(
        () => client.reportUser(any(), any()),
      ).thenAnswer((_) async => <String, Object?>{});

      await profiles.blockUser('@maya:test');
      await profiles.unblockUser('@maya:test');

      verify(() => client.ignoreUser('@maya:test')).called(1);
      verify(() => client.unignoreUser('@maya:test')).called(1);
    });

    // App Review guideline 1.2: blocking also notifies the developer.
    test('reports every block to the moderators', () async {
      when(() => client.ignoreUser(any())).thenAnswer((_) async {});
      when(
        () => client.reportUser(any(), any()),
      ).thenAnswer((_) async => <String, Object?>{});

      await profiles.blockUser('@maya:test');

      final reason =
          verify(
                () => client.reportUser('@maya:test', captureAny()),
              ).captured.single
              as String;
      expect(reason, contains('category: blocked'));
      expect(reason, contains('reported_user: @maya:test'));
    });

    test('keeps the block when the report is refused', () async {
      when(() => client.ignoreUser(any())).thenAnswer((_) async {});
      when(
        () => client.reportUser(any(), any()),
      ).thenThrow(Exception('report endpoint down'));

      // Completes normally: the block is what the person asked for.
      await profiles.blockUser('@maya:test');

      verify(() => client.ignoreUser('@maya:test')).called(1);
    });

    test('does not report a block that failed', () async {
      when(
        () => client.ignoreUser(any()),
      ).thenThrow(Exception('server unavailable'));

      await expectLater(profiles.blockUser('@maya:test'), throwsA(anything));
      verifyNever(() => client.reportUser(any(), any()));
    });
  });

  group('reports', () {
    test('sends a message report against the room event', () async {
      when(
        () => client.reportEvent(any(), any(), reason: any(named: 'reason')),
      ).thenAnswer((_) async {});

      await reports.submit(
        ContentReport(
          reportedUserId: '@maya:test',
          category: ReportCategory.harassment,
          createdAt: DateTime.utc(2026, 8, 2, 9, 30),
          roomId: '!room:test',
          eventId: 'event-1',
          comment: 'Repeated messages',
        ),
      );

      final reason =
          verify(
                () => client.reportEvent(
                  '!room:test',
                  'event-1',
                  reason: captureAny(named: 'reason'),
                ),
              ).captured.single
              as String;
      expect(reason, contains('category: harassment'));
      expect(reason, contains('reported_user: @maya:test'));
      expect(reason, contains('event: event-1'));
      expect(reason, contains('comment: Repeated messages'));
      expect(reason, contains('2026-08-02T09:30:00.000Z'));
    });

    test('sends a user report when no message is named', () async {
      when(() => client.reportUser(any(), any())).thenAnswer((_) async => {});

      await reports.submit(
        ContentReport(
          reportedUserId: '@maya:test',
          category: ReportCategory.spam,
          createdAt: DateTime.utc(2026, 8, 2),
        ),
      );

      verify(() => client.reportUser('@maya:test', any())).called(1);
      verifyNever(
        () => client.reportEvent(any(), any(), reason: any(named: 'reason')),
      );
    });

    test('rejects an over-long comment before sending', () async {
      await expectLater(
        reports.submit(
          ContentReport(
            reportedUserId: '@maya:test',
            category: ReportCategory.other,
            createdAt: DateTime.utc(2026, 8, 2),
            comment: 'x' * (maxReportCommentLength + 1),
          ),
        ),
        throwsA(
          isA<ReportFailure>().having(
            (failure) => failure.code,
            'code',
            ReportFailureCode.invalidComment,
          ),
        ),
      );
      verifyNever(() => client.reportUser(any(), any()));
    });

    test('rejects a malformed target', () async {
      await expectLater(
        reports.submit(
          ContentReport(
            reportedUserId: 'not-a-matrix-id',
            category: ReportCategory.other,
            createdAt: DateTime.utc(2026, 8, 2),
          ),
        ),
        throwsA(
          isA<ReportFailure>().having(
            (failure) => failure.code,
            'code',
            ReportFailureCode.invalidTarget,
          ),
        ),
      );
    });
  });
}

Matcher _hasProfileCode(ProfileFailureCode code) =>
    isA<ProfileFailure>().having((failure) => failure.code, 'code', code);

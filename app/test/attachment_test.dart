import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_contacts/features/media/domain/attachment.dart';
import 'package:sbc_contacts/features/media/presentation/attachment_widgets.dart';
import 'package:sbc_contacts/features/requests/domain/request_models.dart';
import 'package:sbc_contacts/features/requests/presentation/request_widgets.dart';

const _path = '/api/v1/media/8573cf6e-031d-456c-b43d-e7c8b88d9eb3?exp=1796256000&sig=i4mx_yi-Ig';

Map<String, dynamic> _json({String kind = 'IMAGE', String? fileName = 'photo.jpg'}) => {
      'id': '8573cf6e-031d-456c-b43d-e7c8b88d9eb3',
      'kind': kind,
      'mimeType': 'image/jpeg',
      'size': 30432,
      'fileName': fileName,
      'width': 600,
      'height': 400,
      'durationSec': null,
      'url': _path,
    };

void main() {
  group('Attachment', () {
    test('parses the backend AttachmentView', () {
      final a = Attachment.fromJson(_json());
      expect(a.kind, AttachmentKind.image);
      expect(a.size, 30432);
      expect(a.aspectRatio, 1.5);
      expect(a.displayName, 'photo.jpg');
      expect(Attachment.fromJson(_json(kind: 'VIDEO', fileName: null)).displayName, 'Vidéo');
      expect(Attachment.fromJson(_json(kind: 'FILE')).kind, AttachmentKind.file);
    });

    test('resolves the signed path against the API origin, keeping the signature', () {
      final u = resolveMediaUrl(_path, apiBase: 'https://contacts.sniperbusinesscenterlive.com/api/v1');
      expect(
        u.toString(),
        'https://contacts.sniperbusinesscenterlive.com/api/v1/media/8573cf6e-031d-456c-b43d-e7c8b88d9eb3'
        '?exp=1796256000&sig=i4mx_yi-Ig',
      );
      expect(resolveMediaUrl(_path, apiBase: 'http://10.0.2.2:3099/api/v1').authority, '10.0.2.2:3099');
      expect(resolveMediaUrl('https://cdn.example.org/x.jpg').toString(), 'https://cdn.example.org/x.jpg');
    });

    test('formats sizes and durations in French', () {
      expect(formatBytes(30432), '30 Ko');
      expect(formatBytes(2516582), '2,4 Mo');
      expect(formatDuration(65.4), '1:05');
    });
  });

  group('attachments in requests', () {
    test('are read on the request, the offer, the pro side and each message', () {
      final request = ServiceRequestItem.fromJson({
        'id': 'r1',
        'rawText': 'Réparer mon évier',
        'status': 'RESPONDED',
        'attachments': [_json()],
        'responses': [
          {
            'dispatchId': 'd1',
            'status': 'INTERESTED',
            'pro': {'profession': 'Plombier', 'city': 'Douala'},
            'attachments': [_json(kind: 'FILE', fileName: 'devis.pdf')],
            'messages': [
              {'id': 'm1', 'author': 'REQUESTER', 'text': '', 'attachments': [_json()]},
            ],
          },
        ],
      });
      expect(request.attachments, hasLength(1));
      expect(request.responses.single.attachments.single.displayName, 'devis.pdf');
      final m = request.responses.single.messages.single;
      expect(m.text, isEmpty);
      expect(m.attachments, hasLength(1));

      final inbox = InboxItem.fromJson({
        'dispatchId': 'd1',
        'status': 'INTERESTED',
        'request': {'id': 'r1', 'rawText': 'x', 'status': 'SENT', 'attachments': [_json()]},
        'attachments': [_json(kind: 'VIDEO')],
      });
      expect(inbox.request.attachments, hasLength(1));
      expect(inbox.attachments.single.isVideo, isTrue);
    });

    test('older payloads without attachments still parse', () {
      final r = ServiceRequestItem.fromJson({'id': 'r1', 'rawText': 'x', 'status': 'SENT'});
      expect(r.attachments, isEmpty);
    });
  });

  testWidgets('an attachments-only message shows the file and no empty bubble', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConversationThread(
          meIsPro: false,
          otherName: 'Le pro',
          messages: [
            ConversationMessage(
              id: 'm1',
              fromPro: true,
              text: '',
              createdAt: DateTime.now(),
              attachments: [Attachment.fromJson(_json(kind: 'FILE', fileName: 'devis.pdf'))],
            ),
          ],
        ),
      ),
    ));
    expect(find.byType(AttachmentGallery), findsOneWidget);
    expect(find.text('devis.pdf'), findsOneWidget);
    expect(find.text('PDF · 30 Ko'), findsOneWidget);
  });
}

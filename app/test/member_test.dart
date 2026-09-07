import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_contacts/features/directory/domain/member.dart';

void main() {
  group('Member.fromJson', () {
    test('parses a full backend MemberView', () {
      final m = Member.fromJson({
        'id': 'uuid-1',
        'sbcId': 'm1',
        'name': 'Kamga',
        'firstName': 'Marie',
        'profession': 'Designer',
        'city': 'Douala',
        'country': 'CM',
        'sex': 'F',
        'age': 29,
        'interests': ['business'],
        'skills': ['figma', 'ux'],
        'avatarUrl': 'https://x/1',
        'phoneNumber': '2376900001',
        'isFavorite': true,
        'isSynced': false,
      });
      expect(m.sbcId, 'm1');
      expect(m.displayName, 'Marie Kamga');
      expect(m.initials, 'M');
      expect(m.location, 'Douala, CM');
      expect(m.skills, ['figma', 'ux']);
      expect(m.isFavorite, isTrue);
    });

    test('tolerates missing/partial fields', () {
      final m = Member.fromJson({'id': 'uuid-2'});
      expect(m.sbcId, 'uuid-2'); // falls back to id
      expect(m.displayName, 'Membre SBC');
      expect(m.initials, '?');
      expect(m.interests, isEmpty);
      expect(m.location, isEmpty);
      expect(m.isFavorite, isFalse);
    });

    test('copyWith toggles favorite without touching other fields', () {
      final m = Member.fromJson({'id': 'x', 'firstName': 'Jo'}).copyWith(isFavorite: true);
      expect(m.isFavorite, isTrue);
      expect(m.firstName, 'Jo');
    });
  });
}

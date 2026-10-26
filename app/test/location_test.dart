import 'package:flutter_test/flutter_test.dart';
import 'package:sbc_contacts/features/requests/domain/request_models.dart';
import 'package:sbc_contacts/shared/services/location.dart';

void main() {
  test('shows a rounded distance the French way', () {
    expect(formatKm(9), '9 km');
    expect(formatKm(1.5), '1,5 km');
    expect(formatKm(0.5), '0,5 km');
  });

  test('reads the distance on an answer and on an inbox item, when there is one', () {
    final answer = RequestResponse.fromJson({
      'dispatchId': 'd1',
      'status': 'INTERESTED',
      'pro': {'profession': 'Coiffeuse', 'city': 'Douala', 'distanceKm': 9},
    });
    expect(answer.distanceKm, 9.0);

    final inbox = InboxItem.fromJson({'dispatchId': 'd1', 'status': 'SENT', 'distanceKm': null, 'request': <String, dynamic>{}});
    expect(inbox.distanceKm, isNull);
  });
}

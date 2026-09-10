import 'package:flutter_test/flutter_test.dart';
import 'package:wasla/core/models/transfer_models.dart';

void main() {
  test('transfer models retain core metadata', () {
    const file = TransferFile(name: 'photo.jpg', path: '/tmp/photo.jpg', size: 1024);
    expect(file.name, 'photo.jpg');
    expect(file.size, 1024);
    expect(TransferDirection.sent.name, 'sent');
  });
}

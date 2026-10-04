import 'package:arabic_bidi/arabic_bidi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Arabic station names are shaped into connected presentation forms', () {
    final shaped = ArabicBidi.reshape('وزارة التعليم');

    expect(shaped, isNot('وزارة التعليم'));
    expect(RegExp(r'[\uFB50-\uFEFF]').hasMatch(shaped), isTrue);
  });
}

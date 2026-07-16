import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybill/app.dart';

void main() {
  testWidgets('App boots to the MyBill home screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyBillApp()));
    await tester.pumpAndSettle();

    // The shell renders the brand + tagline via GoRouter → HomeScreen.
    expect(find.text('MyBill'), findsWidgets);
    expect(find.text('Grocery Bill Intelligence'), findsOneWidget);
  });
}

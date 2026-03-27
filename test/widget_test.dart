import 'package:flutter_test/flutter_test.dart';

import 'package:pregnancy_care_app/main.dart';
import 'package:pregnancy_care_app/services/notification_service.dart';

void main() {
  testWidgets('firebase setup screen renders safely', (tester) async {
    await tester.pumpWidget(
      PregnancyCareApp(
        firebaseInitializationError: 'setup pending',
        notificationService: NotificationService(),
      ),
    );

    expect(find.text('Firebase setup required'), findsOneWidget);
  });
}

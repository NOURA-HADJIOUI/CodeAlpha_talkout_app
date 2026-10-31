import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkout_app/models/chat.dart';
import 'package:talkout_app/main.dart';
import 'package:talkout_app/screens/profile_screen.dart';

void main() {
  test('unread message badge count totals unread conversations', () {
    final testStore = AppStore()
      ..chats.addAll([
        Chat(1, 'One', unread: 2),
        Chat(2, 'Two', unread: 3),
      ]);

    expect(testStore.unreadMessageCount, 5);
  });

  testWidgets('TalkOut starts on the splash screen', (tester) async {
    await tester.pumpWidget(const TalkOutApp());
    expect(find.text('Get Started'), findsOneWidget);
  });

  testWidgets('Profile avatar opens photo actions', (tester) async {
    store.avatarUrl = null;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ProfileScreen())),
    );

    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    expect(find.text('Add profile photo'), findsOneWidget);
  });
}

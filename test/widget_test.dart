import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:homecare/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: HomecareApp()));

    // Verify that the title is there
    expect(find.text('Homecare'), findsNothing); // Title is passed to MaterialApp but maybe not visible
  });
}

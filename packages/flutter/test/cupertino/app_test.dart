// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/cupertino.dart';

void main() {
  testWidgets('Heroes work', (WidgetTester tester) async {
    await tester.pumpWidget(CupertinoApp(
      home:
        ListView(
          children: <Widget>[
            const Hero(tag: 'a', child: Text('foo')),
            Builder(builder: (BuildContext context) {
              return CupertinoButton(
                child: const Text('next'),
                onPressed: () {
                  Navigator.push(
                    context,
                    CupertinoPageRoute<void>(
                      builder: (BuildContext context) {
                        return const Hero(tag: 'a', child: Text('foo'));
                      }
                    ),
                  );
                },
              );
            }),
          ],
        ),
    ));

    await tester.tap(find.text('next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // During the hero transition, the hero widget is lifted off of both
    // page routes and exists as its own overlay on top of both routes.
    expect(find.widgetWithText(CupertinoPageRoute, 'foo'), findsNothing);
    expect(find.widgetWithText(Navigator, 'foo'), findsOneWidget);
  });

  testWidgets('Has default cupertino localizations', (WidgetTester tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (BuildContext context) {
            return Column(
              children: <Widget>[
                Text(CupertinoLocalizations.of(context).selectAllButtonLabel),
                Text(CupertinoLocalizations.of(context).datePickerMediumDate(
                  DateTime(2018, 10, 4),
                )),
              ],
            );
          },
        ),
      ),
    );

    expect(find.text('Select All'), findsOneWidget);
    expect(find.text('Thu Oct 4 '), findsOneWidget);
  });

  testWidgets('Can use dynamic color', (WidgetTester tester) async {
    const CupertinoDynamicColor dynamicColor = CupertinoDynamicColor.withBrightness(
      color: Color(0xFF000000),
      darkColor: Color(0xFF000001),
    );
    await tester.pumpWidget(const CupertinoApp(
      theme: CupertinoThemeData(brightness: Brightness.light),
      color: dynamicColor,
      home: Placeholder(),
    ));

    expect(tester.widget<Title>(find.byType(Title)).color.value, 0xFF000000);

    await tester.pumpWidget(const CupertinoApp(
      theme: CupertinoThemeData(brightness: Brightness.dark),
      color: dynamicColor,
      home: Placeholder(),
    ));

    expect(tester.widget<Title>(find.byType(Title)).color.value, 0xFF000001);
  });

  testWidgets('Can customize initial routes', (WidgetTester tester) async {
    final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      CupertinoApp(
        navigatorKey: navigatorKey,
        onGenerateInitialRoutes: (String initialRoute) {
          expect(initialRoute, '/abc');
          return <Route<void>>[
            PageRouteBuilder<void>(
              pageBuilder: (
                BuildContext context,
                Animation<double> animation,
                Animation<double> secondaryAnimation) {
                return const Text('non-regular page one');
              }
            ),
            PageRouteBuilder<void>(
              pageBuilder: (
                BuildContext context,
                Animation<double> animation,
                Animation<double> secondaryAnimation) {
                return const Text('non-regular page two');
              }
            ),
          ];
        },
        initialRoute: '/abc',
        routes: <String, WidgetBuilder>{
          '/': (BuildContext context) => const Text('regular page one'),
          '/abc': (BuildContext context) => const Text('regular page two'),
        },
      )
    );
    expect(find.text('non-regular page two'), findsOneWidget);
    expect(find.text('non-regular page one'), findsNothing);
    expect(find.text('regular page one'), findsNothing);
    expect(find.text('regular page two'), findsNothing);
    navigatorKey.currentState.pop();
    await tester.pumpAndSettle();
    expect(find.text('non-regular page two'), findsNothing);
    expect(find.text('non-regular page one'), findsOneWidget);
    expect(find.text('regular page one'), findsNothing);
    expect(find.text('regular page two'), findsNothing);
  });

  testWidgets('CupertinoApp.navigatorKey can be updated', (WidgetTester tester) async {
    final GlobalKey<NavigatorState> key1 = GlobalKey<NavigatorState>();
    await tester.pumpWidget(CupertinoApp(
      navigatorKey: key1,
      home: const Placeholder(),
    ));
    expect(key1.currentState, isA<NavigatorState>());
    final GlobalKey<NavigatorState> key2 = GlobalKey<NavigatorState>();
    await tester.pumpWidget(CupertinoApp(
      navigatorKey: key2,
      home: const Placeholder(),
    ));
    expect(key2.currentState, isA<NavigatorState>());
    expect(key1.currentState, isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timebuddy/app/widgets/responsive_layout.dart';

import 'helpers.dart';
import 'pump_app.dart';

// A test for the harness, which is unusual and is here for a specific reason.
//
// `pumpApp`'s `surfaceSize` used to go through
// `tester.binding.setSurfaceSize`, which moves the render surface and leaves
// the view — and therefore `MediaQuery` — at the default 800x600. Pages asked
// for a phone were laid out 400px wide while every `ResponsiveLayout` question
// in them answered for a desktop, so the whole mobile half of the app went
// untested by tests that named a phone surface in their first line. A
// `RenderFlex` overflow reached production through that gap.
//
// Nothing in the suite would notice that regression coming back: reverting
// `surfaceSize` to `setSurfaceSize` leaves every other test green, because a
// test that silently exercises the desktop layout still passes its desktop
// assertions. These three do notice, which is the whole of what they are for.

/// The viewport `flutter_test` starts every test in: 2400x1800 at dpr 3.
const Size _defaultViewport = Size(800, 600);

/// Below `ResponsiveLayout.mobileBreakpoint`, and unlike [_defaultViewport] in
/// both dimensions — a viewport that failed to move is then visible in the
/// numbers rather than only in the breakpoint answer.
const Size _phoneViewport = Size(400, 720);

/// A page-sized nothing, mounted only to be measured.
class _Viewport extends StatelessWidget {
  const _Viewport();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

/// What `MediaQuery` tells the page it is being drawn in.
Size _mediaSize(WidgetTester tester) =>
    MediaQuery.sizeOf(tester.element(find.byType(_Viewport)));

/// What the render surface actually gave the page.
///
/// Read off a `SizedBox.expand` under `MaterialApp.home`, so it is the size
/// layout arrived at rather than a number read back out of the binding.
Size _renderedSize(WidgetTester tester) =>
    tester.getSize(find.byType(_Viewport));

bool _isMobile(WidgetTester tester) =>
    ResponsiveLayout.isMobile(tester.element(find.byType(_Viewport)));

void main() {
  setUpAll(initTestTimeZones);

  testWidgets('with no surfaceSize the viewport is the 800x600 default', (
    tester,
  ) async {
    await pumpApp(tester, const _Viewport());

    expect(_mediaSize(tester), _defaultViewport);
    expect(_renderedSize(tester), _defaultViewport);
    expect(_isMobile(tester), isFalse);
  });

  testWidgets('surfaceSize moves MediaQuery and not just the surface', (
    tester,
  ) async {
    await pumpApp(tester, const _Viewport(), surfaceSize: _phoneViewport);

    // The two have to agree. `setSurfaceSize` passes the second expectation
    // and fails the first, which is exactly the shape of the bug: a page laid
    // out at phone width that every `ResponsiveLayout` call answers for a
    // desktop.
    expect(_mediaSize(tester), _phoneViewport);
    expect(_renderedSize(tester), _phoneViewport);
    expect(
      _isMobile(tester),
      isTrue,
      reason: 'a 400px viewport is a phone, and the page has to be told so',
    );
  });

  testWidgets('the phone viewport above did not leak into this test', (
    tester,
  ) async {
    // Ordering is the assertion. The view is process-wide and survives the
    // test that set it, so without `pumpApp`'s tear-down this body — which
    // never mentions a width — would run at 400x720 and quietly answer for the
    // wrong side of the breakpoint.
    await pumpApp(tester, const _Viewport());

    expect(_mediaSize(tester), _defaultViewport);
    expect(_renderedSize(tester), _defaultViewport);
    expect(_isMobile(tester), isFalse);
  });
}

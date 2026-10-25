import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiview_desktop/src/lifecycle/hidden_reemit.dart';

/// Stands in for the root's observer: re-emits on `hidden`, either through
/// the deferred helper or synchronously (the shape the helper replaces).
class _ReemitObserver with WidgetsBindingObserver {
  _ReemitObserver({required this.deferred});

  final bool deferred;
  bool windowsOpen = true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.hidden) return;
    if (deferred) {
      reemitInactiveAfterHidden(() => windowsOpen);
    } else {
      final binding = SchedulerBinding.instance;
      // ignore: invalid_use_of_protected_member
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
  }
}

/// Delivers a lifecycle message the way the embedder does, then lets
/// pending microtasks run, as they do between two platform messages.
Future<void> _send(AppLifecycleState state) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    SystemChannels.lifecycle.name,
    SystemChannels.lifecycle.codec.encodeMessage(state.toString()),
    (_) {},
  );
  await Future<void>.delayed(Duration.zero);
}

/// Registers [observer] and then an [AppLifecycleListener] (the order an
/// `EditableText` mounted after the root produces), drives [states], and
/// returns the errors the framework reported and the states the listener saw.
Future<(List<String>, List<AppLifecycleState>)> _drive(
  _ReemitObserver observer,
  List<AppLifecycleState> states,
) async {
  final errors = <String>[];
  final seen = <AppLifecycleState>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (d) => errors.add(d.exceptionAsString());
  WidgetsBinding.instance.resetInternalState();
  WidgetsBinding.instance.addObserver(observer);
  final listener = AppLifecycleListener(onStateChange: seen.add);
  try {
    for (final state in states) {
      await _send(state);
    }
  } finally {
    FlutterError.onError = previous;
    listener.dispose();
    WidgetsBinding.instance.removeObserver(observer);
  }
  return (errors, seen);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const resumed = AppLifecycleState.resumed;
  const inactive = AppLifecycleState.inactive;
  const hidden = AppLifecycleState.hidden;

  test('a later listener sees hidden -> inactive -> resumed in order',
      () async {
    final (errors, seen) = await _drive(
      _ReemitObserver(deferred: true),
      [resumed, hidden, resumed],
    );
    expect(errors, isEmpty);
    expect(seen, [resumed, inactive, hidden, inactive, resumed]);
    expect(WidgetsBinding.instance.lifecycleState, resumed);
  });

  test('the re-emit keeps the binding inactive while windows remain',
      () async {
    final (errors, _) = await _drive(
      _ReemitObserver(deferred: true),
      [resumed, hidden],
    );
    expect(errors, isEmpty);
    expect(WidgetsBinding.instance.lifecycleState, inactive);
  });

  test('no re-emit once the last window has closed', () async {
    final observer = _ReemitObserver(deferred: true)..windowsOpen = false;
    final (errors, _) = await _drive(observer, [resumed, hidden]);
    expect(errors, isEmpty);
    expect(WidgetsBinding.instance.lifecycleState, hidden);
  });

  test('control: a synchronous re-emit trips the later listener', () async {
    // Without this, the tests above would also pass against a harness that
    // never reproduced the bug.
    final (errors, _) = await _drive(
      _ReemitObserver(deferred: false),
      [resumed, hidden, resumed],
    );
    expect(errors, [contains('Invalid state transition from $hidden to $resumed')]);
  });
}

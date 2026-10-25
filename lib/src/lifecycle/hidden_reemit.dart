import 'dart:async';

import 'package:flutter/scheduler.dart';

/// Re-emits [AppLifecycleState.inactive] after the binding reported
/// [AppLifecycleState.hidden], so frames keep rendering while other windows
/// remain open.
///
/// The re-emit is deferred to a microtask. Called synchronously from a
/// `didChangeAppLifecycleState` observer, it would nest an `inactive` pass
/// inside the binding's `hidden` pass: observers registered later would
/// receive `hidden` after `inactive`, their recorded state would diverge from
/// the binding's, and an [AppLifecycleListener] (one per `EditableText`)
/// would assert "Invalid state transition from hidden to resumed" on the next
/// resume. Deferred, every observer sees `hidden -> inactive` in order.
///
/// [shouldReemit] is read when the microtask runs, and the re-emit is skipped
/// if the binding has left `hidden` by then.
void reemitInactiveAfterHidden(bool Function() shouldReemit) {
  scheduleMicrotask(() {
    final binding = SchedulerBinding.instance;
    if (binding.lifecycleState != AppLifecycleState.hidden) return;
    if (!shouldReemit()) return;
    // ignore: invalid_use_of_protected_member
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  });
}

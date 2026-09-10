import 'dart:async';

enum EmergencyState {
  idle,
  armed,
  emergencyTriggered,
  locationAcquisition,
  localDiscovery,
  alertBroadcast,
  contactNotification,
  serverSync,
  activeEmergency,
  cancelled,
  resolved,
  expired,
}

class StateTransitionLog {
  const StateTransitionLog({
    required this.fromState,
    required this.toState,
    required this.timestamp,
    this.reason,
  });

  final EmergencyState fromState;
  final EmergencyState toState;
  final DateTime timestamp;
  final String? reason;
}

class EmergencyStateMachine {
  EmergencyStateMachine._();
  static final EmergencyStateMachine _instance = EmergencyStateMachine._();
  factory EmergencyStateMachine() => _instance;

  EmergencyState _currentState = EmergencyState.idle;
  final List<StateTransitionLog> _history = [];
  final StreamController<EmergencyState> _stateStreamController = StreamController<EmergencyState>.broadcast();

  EmergencyState get currentState => _currentState;
  List<StateTransitionLog> get history => List.unmodifiable(_history);
  Stream<EmergencyState> get stateStream => _stateStreamController.stream;

  void transitionTo(EmergencyState newState, {String? reason}) {
    if (_currentState == newState) return;

    final log = StateTransitionLog(
      fromState: _currentState,
      toState: newState,
      timestamp: DateTime.now().toUtc(),
      reason: reason,
    );
    _history.add(log);
    _currentState = newState;
    _stateStreamController.add(newState);
  }

  void reset() {
    transitionTo(EmergencyState.idle, reason: 'System Reset');
    _history.clear();
  }
}

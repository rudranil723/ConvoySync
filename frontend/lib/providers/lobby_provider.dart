import 'package:flutter_riverpod/flutter_riverpod.dart';

class LobbyState {
  final String? activeConvoyId;
  final String? activeConvoyCode;
  final String role; // 'leader' or 'member'
  final bool isConnecting;
  final String? errorMessage;

  LobbyState({
    this.activeConvoyId,
    this.activeConvoyCode,
    this.role = 'member',
    this.isConnecting = false,
    this.errorMessage,
  });

  LobbyState copyWith({
    String? activeConvoyId,
    String? activeConvoyCode,
    String? role,
    bool? isConnecting,
    String? errorMessage,
  }) {
    return LobbyState(
      activeConvoyId: activeConvoyId ?? this.activeConvoyId,
      activeConvoyCode: activeConvoyCode ?? this.activeConvoyCode,
      role: role ?? this.role,
      isConnecting: isConnecting ?? this.isConnecting,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class LobbyNotifier extends StateNotifier<LobbyState> {
  LobbyNotifier() : super(LobbyState());

  void selectConvoy(String id, String code, String role) {
    state = state.copyWith(
      activeConvoyId: id,
      activeConvoyCode: code,
      role: role,
      errorMessage: null,
    );
  }

  void leaveLobby() {
    state = LobbyState();
  }

  void setError(String message) {
    state = state.copyWith(errorMessage: message);
  }
}

final lobbyProvider = StateNotifierProvider<LobbyNotifier, LobbyState>((ref) {
  return LobbyNotifier();
});

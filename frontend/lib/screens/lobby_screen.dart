import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:frontend/theme.dart';
import 'package:frontend/providers/lobby_provider.dart';
import 'package:frontend/providers/telemetry_provider.dart';
import 'map_screen.dart';

class ConvoySession {
  final String name;
  final String code;
  final int riderCount;
  final double thresholdKm;

  ConvoySession({
    required this.name,
    required this.code,
    required this.riderCount,
    required this.thresholdKm,
  });
}

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  // Initialize with a mock active convoy session
  final List<ConvoySession> _convoys = [
    ConvoySession(
      name: 'Test1',
      code: 'J6LU80',
      riderCount: 4,
      thresholdKm: 1.5,
    )
  ];

  final _joinCodeController = TextEditingController();

  @override
  void dispose() {
    _joinCodeController.dispose();
    super.dispose();
  }

  // Open the Join Convoy bottom sheet
  void _showJoinBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ConvoyTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24.0,
            right: 24.0,
            top: 24.0,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24.0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Bottom sheet drag indicator/line
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: ConvoyTheme.textSecondary.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Join Convoy',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: ConvoyTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter the 6-character room code to sync telemetry',
                style: TextStyle(
                  fontSize: 14,
                  color: ConvoyTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              // Alphanumeric Text Field
              TextField(
                controller: _joinCodeController,
                decoration: const InputDecoration(
                  labelText: 'Session Code',
                  hintText: 'e.g. J6LU80',
                  prefixIcon: Icon(Icons.vpn_key_outlined, color: ConvoyTheme.textSecondary),
                ),
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  color: ConvoyTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  final enteredCode = _joinCodeController.text.trim().toUpperCase();
                  if (enteredCode.isNotEmpty) {
                    setState(() {
                      _convoys.add(
                        ConvoySession(
                          name: 'Lobby ${enteredCode}',
                          code: enteredCode,
                          riderCount: 1,
                          thresholdKm: 1.5,
                        ),
                      );
                    });
                    _joinCodeController.clear();
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Joined Convoy $enteredCode successfully!'),
                        backgroundColor: ConvoyTheme.primary,
                      ),
                    );
                  }
                },
                child: const Text('Join convoy'),
              ),
            ],
          ),
        );
      },
    );
  }

  // Create a new mock convoy
  void _handleCreateConvoy() {
    // Generate a random mock code
    final newCode = 'C${(DateTime.now().millisecondsSinceEpoch % 100000).toString().padLeft(5, '0')}';
    setState(() {
      _convoys.add(
        ConvoySession(
          name: 'Convoy ${_convoys.length + 1}',
          code: newCode,
          riderCount: 1,
          thresholdKm: 1.5,
        ),
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Created Convoy $newCode successfully!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ConvoyTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Dashboard Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hey, Rudranil',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: ConvoyTheme.textPrimary,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Safe travels today',
                        style: TextStyle(
                          fontSize: 14,
                          color: ConvoyTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  // Circular Avatar
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: ConvoyTheme.primary.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: ConvoyTheme.primary, width: 1.5),
                    ),
                    child: const Center(
                      child: Text(
                        'R',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: ConvoyTheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // 2. Action Cards Grid Row
              Row(
                children: [
                  // CREATE CARD (Vivid Orange)
                  Expanded(
                    child: GestureDetector(
                      onTap: _handleCreateConvoy,
                      child: Container(
                        height: 120,
                        decoration: BoxDecoration(
                          color: ConvoyTheme.primary,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: ConvoyTheme.primary.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_circle_outline, size: 36, color: Colors.white),
                            SizedBox(height: 12),
                            Text(
                              'Create',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // JOIN CODE CARD (Muted Dark Grey)
                  Expanded(
                    child: GestureDetector(
                      onTap: _showJoinBottomSheet,
                      child: Container(
                        height: 120,
                        decoration: BoxDecoration(
                          color: ConvoyTheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: ConvoyTheme.inputBg),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.vpn_key_outlined, size: 36, color: Colors.white),
                            SizedBox(height: 12),
                            Text(
                              'Join Code',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              // Active Convoys Header with dynamic clear button to toggle empty state
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Active Convoys',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: ConvoyTheme.textPrimary,
                    ),
                  ),
                  if (_convoys.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _convoys.clear();
                        });
                      },
                      child: const Text(
                        'Clear All',
                        style: TextStyle(color: ConvoyTheme.textSecondary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // 3. Main Area: Convoy List or Empty State
              Expanded(
                child: _convoys.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        itemCount: _convoys.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final session = _convoys[index];
                          return _buildSessionTile(session, index);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 4. Empty State Widget
  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Stylized dual-arrow signpost graphic representation
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: ConvoyTheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: ConvoyTheme.inputBg),
          ),
          child: const Icon(
            Icons.alt_route_rounded,
            color: ConvoyTheme.primary,
            size: 64,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Empty road ahead',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: ConvoyTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.0),
          child: Text(
            'Create your first convoy or join one with a code.',
            style: TextStyle(
              fontSize: 14,
              color: ConvoyTheme.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 20),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _convoys.add(
                ConvoySession(
                  name: 'Test1',
                  code: 'J6LU80',
                  riderCount: 4,
                  thresholdKm: 1.5,
                ),
              );
            });
          },
          icon: const Icon(Icons.refresh, color: ConvoyTheme.primary),
          label: const Text(
            'Restore Demo Session',
            style: TextStyle(color: ConvoyTheme.primary, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  // 5. Active Session list tile
  Widget _buildSessionTile(ConvoySession session, int index) {
    return Container(
      decoration: BoxDecoration(
        color: ConvoyTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ConvoyTheme.inputBg),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: ConvoyTheme.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ConvoyTheme.inputBg),
          ),
          child: Text(
            session.code.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: ConvoyTheme.primary,
              letterSpacing: 1.0,
            ),
          ),
        ),
        title: Text(
          session.name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: ConvoyTheme.textPrimary,
            fontSize: 16,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Row(
            children: [
              const Icon(Icons.people_outline, size: 16, color: ConvoyTheme.textSecondary),
              const SizedBox(width: 4),
              Text(
                '${session.riderCount} riders',
                style: const TextStyle(color: ConvoyTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.notification_important_outlined, size: 16, color: ConvoyTheme.textSecondary),
              const SizedBox(width: 4),
              Text(
                '${session.thresholdKm} km alert',
                style: const TextStyle(color: ConvoyTheme.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.chevron_right, color: ConvoyTheme.textSecondary),
          onPressed: () {
            // Update lobby provider with selected convoy and navigate to MapScreen
            ref.read(lobbyProvider.notifier).selectConvoy(
              'convoy-${session.code}',
              session.code,
              'leader',
            );
            ref.read(telemetryProvider.notifier).clearTelemetry();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const MapScreen()),
            );
          },
        ),
      ),
    );
  }
}

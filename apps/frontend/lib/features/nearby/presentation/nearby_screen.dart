import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/battery_optimizer.dart';
import '../domain/proximity_user.dart';
import '../../chat/presentation/chat_controller.dart';

final batteryStateProvider = StateProvider<ActivityState>((ref) => ActivityState.stationary);
final gpsSettingsProvider = StateProvider<String>((ref) => 'Low Accuracy (50m filter)');
final bleDutyCycleProvider = StateProvider<String>((ref) => 'Scanning 5s / 2min');

class NearbyScreen extends ConsumerWidget {
  const NearbyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(proximityUsersProvider);
    final activity = ref.watch(batteryStateProvider);
    final gpsInfo = ref.watch(gpsSettingsProvider);
    final bleInfo = ref.watch(bleDutyCycleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Proximity Discovery'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Trigger reload / scanning
            },
          )
        ],
      ),
      body: Column(
        children: [
          // Proximity Sensor Duty-Cycle Optimization State Panel
          Card(
            margin: const EdgeInsets.all(12),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.battery_charging_full, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        'Power Optimization Registry',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('User Activity:'),
                      Chip(
                        label: Text(activity == ActivityState.moving ? 'Moving' : 'Stationary'),
                        backgroundColor: activity == ActivityState.moving
                            ? Colors.orange.shade100
                            : Colors.blue.shade100,
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('GPS Resolution:'),
                      Text(gpsInfo, style: const TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('BLE Scan Interval:'),
                      Text(bleInfo, style: const TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                const Icon(Icons.sensors, color: Colors.blueGrey, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Discovered Clients',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                      ),
                ),
              ],
            ),
          ),

          // User Discovery Cards List
          Expanded(
            child: ListView.builder(
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.grey.shade300,
                      child: Text(user.username[0]),
                    ),
                    title: Row(
                      children: [
                        Text(
                          user.username,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        // Real-time Presence Indicators
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: user.isOnline ? Colors.green : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      'Distance: ${user.distanceMeters.toStringAsFixed(1)}m • Last seen: '
                      '${user.lastSeen.hour}:${user.lastSeen.minute}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      // Show loading spinner dialog
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Center(
                          child: CircularProgressIndicator(),
                        ),
                      );

                      try {
                        final chatRepo = ref.read(chatRepositoryProvider);
                        final roomUuid = await chatRepo.getOrCreateRoom(
                          chatRepo.currentUserId,
                          user.userId,
                        );

                        // Pop loading spinner
                        if (context.mounted) {
                          Navigator.of(context).pop();
                          // Navigate to Chat Screen with room UUID and peer ID
                          context.push('/chat/$roomUuid?peerId=${user.userId}');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to initialize chat room: $e')),
                          );
                        }
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

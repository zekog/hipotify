import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import 'package:flutter/services.dart';
import '../utils/snackbar_helper.dart';

class ListenTogetherScreen extends StatefulWidget {
  const ListenTogetherScreen({super.key});

  @override
  State<ListenTogetherScreen> createState() => _ListenTogetherScreenState();
}

class _ListenTogetherScreenState extends State<ListenTogetherScreen> {
  final TextEditingController _roomCodeController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, child) {
        final isInRoom = player.isInRoom;
        
        return Scaffold(
          appBar: AppBar(
            title: const Text('Listen Together'),
          ),
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.people, size: 80, color: Color(0xFF1DB954)),
                const SizedBox(height: 24),
                
                if (!isInRoom) ...[
                  const Text(
                    'Host a session and share your music in real-time with others.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: player.currentTrack == null 
                        ? null 
                        : () => player.hostRoom(),
                    icon: const Icon(Icons.radio),
                    label: const Text('START HOSTING'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFF1DB954),
                      foregroundColor: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (player.currentTrack == null)
                    const Text(
                      'Play a track first to start hosting!',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 48),
                  const Text(
                    'Or join a friend\'s session:',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _roomCodeController,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Enter Room ID',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          if (_roomCodeController.text.isNotEmpty) {
                            player.joinRoom(_roomCodeController.text.trim());
                          }
                        },
                        child: const Text('JOIN'),
                      ),
                    ],
                  ),
                ] else ...[
                  // Already in room
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF1DB954)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          player.isHost ? 'You are Hosting' : 'You have Joined',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              player.roomId ?? '',
                              style: const TextStyle(
                                fontSize: 24, 
                                fontWeight: FontWeight.bold, 
                                letterSpacing: 2
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: player.roomId ?? ''));
                                showSnackBar(context, 'Room ID copied!');
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text('Share this ID with your friends to join.', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (player.currentTrack != null)
                    ListTile(
                      leading: Image.network(player.currentTrack!.coverUrl, width: 50, height: 50),
                      title: Text(player.currentTrack!.title),
                      subtitle: Text(player.currentTrack!.artistName),
                    ),
                  const Spacer(),
                  if (player.participants.isNotEmpty) ...[
                    const Text(
                      'Participants',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 100,
                      child: ListView.builder(
                        itemCount: player.participants.length,
                        itemBuilder: (context, index) {
                          final p = player.participants[index] as dynamic;
                          String username = 'User';
                          try {
                            username = p.payload['username'] ?? 'User';
                          } catch (_) {}
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.person, size: 16, color: Colors.grey),
                                const SizedBox(width: 8),
                                Text(username, style: const TextStyle(fontSize: 14)),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => player.leaveRoom(),
                    icon: const Icon(Icons.logout),
                    label: Text(player.isHost ? 'STOP SESSION' : 'LEAVE SESSION'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[900],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

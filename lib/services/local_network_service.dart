import 'dart:io';
import 'dart:convert';
import 'dart:async';

class DiscoveredDevice {
  final String id;
  final String name;
  final String ip;
  final int port;
  final DateTime lastSeen;

  DiscoveredDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.lastSeen,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ip': ip,
    'port': port,
  };
}

class LocalNetworkService {
  static final LocalNetworkService _instance = LocalNetworkService._internal();
  factory LocalNetworkService() => _instance;
  LocalNetworkService._internal();

  static const int _discoveryPort = 45455;
  static const String _magicHeader = 'HIPOTIFY_SYNC';

  RawDatagramSocket? _udpSocket;
  HttpServer? _httpServer;
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;

  final Map<String, DiscoveredDevice> _devices = {};
  final _devicesController = StreamController<List<DiscoveredDevice>>.broadcast();

  final List<WebSocket> _clientSockets = [];
  WebSocket? _targetSocket;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<List<DiscoveredDevice>> get discoveredDevicesStream => _devicesController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  DiscoveredDevice? getDevice(String id) => _devices[id];

  String? _deviceId;
  String? _deviceName;

  int? _serverPort;
  String? _localIp;

  String? get localQrData {
    if (_localIp == null || _serverPort == null || _deviceId == null || _deviceName == null) return null;
    return '$_deviceId|$_deviceName|$_serverPort|$_localIp';
  }

  Future<void> start(String deviceId, String deviceName) async {
    _deviceId = deviceId;
    _deviceName = deviceName;

    await _resolveLocalIp();
    await _startWebSocketServer();
    await _startUdpDiscovery();

    _cleanupTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _cleanupStaleDevices();
    });
  }

  Future<void> _resolveLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLinkLocal: true);
      for (var interface in interfaces) {
         if (interface.name.contains('wlan') || interface.name.contains('eth') || interface.name.contains('en')) {
            _localIp = interface.addresses.first.address;
            break;
         }
      }
      if (_localIp == null && interfaces.isNotEmpty) {
          _localIp = interfaces.first.addresses.first.address;
      }
    } catch (e) {
      print('LocalNetworkService: could not resolve local IP - $e');
    }
  }

  String? get localIp => _localIp;

  Future<void> _startWebSocketServer() async {
    try {
      try {
        _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 45456);
      } catch (e) {
        // Fallback to random if 45456 is somehow occupied
        _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      }
      
      _serverPort = _httpServer!.port;
      print('LocalNetworkService: WebSocket Server listening on $_serverPort');

      _httpServer!.listen((HttpRequest request) async {
        if (request.uri.path == '/ws') {
          final socket = await WebSocketTransformer.upgrade(request);
          _clientSockets.add(socket);
          
          socket.listen(
            (data) {
              try {
                final message = jsonDecode(data);
                _messageController.add(message);
              } catch (e) {
                print('LocalNetworkService: Error parsing message: $e');
              }
            },
            onDone: () => _clientSockets.remove(socket),
            onError: (e) => _clientSockets.remove(socket),
          );
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
        }
      });
    } catch (e) {
      print('LocalNetworkService: Error starting server: $e');
    }
  }

  Future<void> _startUdpDiscovery() async {
    final bindAddress = _localIp != null ? InternetAddress(_localIp!) : InternetAddress.anyIPv4;
    try {
      _udpSocket = await RawDatagramSocket.bind(bindAddress, _discoveryPort, reuseAddress: true);
      _udpSocket!.broadcastEnabled = true;
    } catch (e) {
      print('LocalNetworkService: could not bind UDP to $_discoveryPort, falling back to random port');
      try {
         _udpSocket = await RawDatagramSocket.bind(bindAddress, 0, reuseAddress: true);
         _udpSocket!.broadcastEnabled = true;
      } catch (e) {
          print('LocalNetworkService: failed to bind UDP completely.');
          return;
      }
    }

    _udpSocket!.broadcastEnabled = true;

    _udpSocket!.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final datagram = _udpSocket!.receive();
        if (datagram != null) {
          final message = utf8.decode(datagram.data);
          if (message.startsWith(_magicHeader)) {
            final parts = message.split('|');
            if (parts.length >= 4) {
              final id = parts[1];
              final name = parts[2];
              final port = int.tryParse(parts[3]);

              if (id != _deviceId && port != null) {
                _devices[id] = DiscoveredDevice(
                  id: id,
                  name: name,
                  ip: datagram.address.address,
                  port: port,
                  lastSeen: DateTime.now(),
                );
                _notifyDevices();
              }
            }
          }
        }
      }
    }, onError: (e) {
      print('LocalNetworkService: UDP listen error: $e');
    });

    _broadcastTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _broadcastPresence();
    });
    _broadcastPresence(); // Initial ping
  }

  void _broadcastPresence() {
    if (_udpSocket == null || _serverPort == null) return;
    
    final message = '$_magicHeader|$_deviceId|$_deviceName|$_serverPort';
    final data = utf8.encode(message);
    
    if (_localIp != null && _localIp!.contains('.')) {
      try {
         final parts = _localIp!.split('.');
         parts[3] = '255';
         final subnetBroadcast = InternetAddress(parts.join('.'));
         _udpSocket!.send(data, subnetBroadcast, _discoveryPort);
      } catch(e) {
         print('LocalNetworkService: Broadcast failed completely');
      }
    }
  }

  void _cleanupStaleDevices() {
    final now = DateTime.now();
    bool changed = false;
    _devices.removeWhere((id, device) {
      final isStale = now.difference(device.lastSeen).inSeconds > 15;
      if (isStale) changed = true;
      return isStale;
    });
    if (changed) _notifyDevices();
  }

  void _notifyDevices() {
    _devicesController.add(_devices.values.toList());
  }

  void addManualDevice(String id, String name, int port, String ip) {
    if (id != _deviceId) {
      _devices[id] = DiscoveredDevice(
          id: id,
          name: name,
          ip: ip,
          port: port,
          lastSeen: DateTime.now().add(const Duration(hours: 1)), // keep it alive a bit
      );
      _notifyDevices();
    }
  }

  final _targetConnectionController = StreamController<bool>.broadcast();
  Stream<bool> get targetConnectionStream => _targetConnectionController.stream;

  Future<bool> connectToTarget(String ip, int port) async {
    disconnectTarget();
    try {
      _targetSocket = await WebSocket.connect('ws://$ip:$port/ws').timeout(const Duration(seconds: 3));
      
      _targetConnectionController.add(true);

      _targetSocket!.listen(
        (data) {
          try {
            final message = jsonDecode(data);
            _messageController.add(message);
          } catch (e) {
             print('LocalNetworkService: err parsing remote data: $e');
          }
        },
        onDone: () => disconnectTarget(),
        onError: (e) => disconnectTarget(),
      );
      
      return true;
    } catch (e) {
      print('LocalNetworkService: Failed to connect to target: $e');
      _targetConnectionController.add(false);
      return false;
    }
  }

  void disconnectTarget() {
    if (_targetSocket != null) {
      _targetSocket?.close();
      _targetSocket = null;
      _targetConnectionController.add(false);
    }
  }

  // Sends data to the targeted device (we are controlling it)
  void sendToTarget(Map<String, dynamic> data) {
    if (_targetSocket != null && _targetSocket!.readyState == WebSocket.open) {
      _targetSocket!.add(jsonEncode(data));
    }
  }

  Future<bool> sendOneOffCommand(String ip, int port, Map<String, dynamic> data) async {
    try {
       final socket = await WebSocket.connect('ws://$ip:$port/ws').timeout(const Duration(seconds: 2));
       socket.add(jsonEncode(data));
       await socket.close();
       return true;
    } catch (e) {
       print('LocalNetworkService: error sending one-off command: $e');
       return false;
    }
  }


  // Broadcasts data to all connected clients (we are being controlled)
  void broadcastToClients(Map<String, dynamic> data) {
    final msg = jsonEncode(data);
    for (var socket in List.of(_clientSockets)) {
      if (socket.readyState == WebSocket.open) {
        socket.add(msg);
      } else {
        _clientSockets.remove(socket);
      }
    }
  }

  void stop() {
    _cleanupTimer?.cancel();
    _broadcastTimer?.cancel();
    _udpSocket?.close();
    _httpServer?.close();
    disconnectTarget();
    for (var socket in _clientSockets) {
      socket.close();
    }
    _clientSockets.clear();
  }
}

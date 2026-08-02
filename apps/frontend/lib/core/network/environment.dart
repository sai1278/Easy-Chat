enum Environment {
  emulator,
  usb,
  wifi,
  production,
}

class ApiConfig {
  final Environment environment;
  final String customHost;
  final int gatewayPort;
  final String? overrideApiBaseUrl;
  final String? overrideWsBaseUrl;

  const ApiConfig({
    required this.environment,
    this.customHost = '192.168.31.60',
    this.gatewayPort = 8090,
    this.overrideApiBaseUrl,
    this.overrideWsBaseUrl,
  });

  factory ApiConfig.fromEnvironment() {
    const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
    const wsBaseUrl = String.fromEnvironment('WS_BASE_URL');
    const envStr = String.fromEnvironment('APP_ENV', defaultValue: 'usb');
    const customHost = String.fromEnvironment('HOST_IP', defaultValue: '192.168.31.60');
    const portStr = String.fromEnvironment('GATEWAY_PORT');
    
    // In USB mode default to 18080 (ADB reverse), in LAN/WiFi mode default to 8090 (Gateway direct port)
    final isWifi = envStr.toLowerCase() == 'wifi' || envStr.toLowerCase() == 'lan';
    final defaultPort = isWifi ? 8090 : 18080;
    final parsedPort = int.tryParse(portStr) ?? defaultPort;

    Environment env;
    switch (envStr.toLowerCase()) {
      case 'emulator':
        env = Environment.emulator;
        break;
      case 'wifi':
      case 'lan':
        env = Environment.wifi;
        break;
      case 'production':
        env = Environment.production;
        break;
      case 'usb':
      default:
        env = Environment.usb;
        break;
    }

    return ApiConfig(
      environment: env,
      customHost: customHost,
      gatewayPort: parsedPort,
      overrideApiBaseUrl: apiBaseUrl.isNotEmpty ? apiBaseUrl : null,
      overrideWsBaseUrl: wsBaseUrl.isNotEmpty ? wsBaseUrl : null,
    );
  }

  String get host {
    switch (environment) {
      case Environment.emulator:
        return '10.0.2.2';
      case Environment.usb:
        return '127.0.0.1';
      case Environment.wifi:
        return customHost;
      case Environment.production:
        return 'api.easychat.com';
    }
  }

  String get httpScheme => environment == Environment.production ? 'https' : 'http';
  String get wsScheme => environment == Environment.production ? 'wss' : 'ws';

  String get baseUrl {
    if (overrideApiBaseUrl != null && overrideApiBaseUrl!.isNotEmpty) {
      return overrideApiBaseUrl!;
    }
    if (environment == Environment.production) {
      return '$httpScheme://$host/api/v1';
    }
    return '$httpScheme://$host:$gatewayPort/api/v1';
  }

  String get wsUrl {
    if (overrideWsBaseUrl != null && overrideWsBaseUrl!.isNotEmpty) {
      return overrideWsBaseUrl!;
    }
    if (environment == Environment.production) {
      return '$wsScheme://$host/ws';
    }
    return '$wsScheme://$host:$gatewayPort/ws';
  }

  String get mediaUrl => '$baseUrl/media';
  String get nearbyUrl => '$baseUrl/nearby';
}

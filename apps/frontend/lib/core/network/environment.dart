import 'package:flutter/foundation.dart';

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

  const ApiConfig({
    required this.environment,
    this.customHost = '192.168.1.100',
    this.gatewayPort = 8090,
  });

  factory ApiConfig.fromEnvironment() {
    const envStr = String.fromEnvironment('APP_ENV', defaultValue: 'usb');
    const customHost = String.fromEnvironment('HOST_IP', defaultValue: '192.168.1.100');

    Environment env;
    switch (envStr.toLowerCase()) {
      case 'emulator':
        env = Environment.emulator;
        break;
      case 'wifi':
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
    if (environment == Environment.production) {
      return '$httpScheme://$host/api/v1';
    }
    return '$httpScheme://$host:$gatewayPort/api/v1';
  }

  String get wsUrl {
    if (environment == Environment.production) {
      return '$wsScheme://$host/ws';
    }
    return '$wsScheme://$host:$gatewayPort/ws';
  }

  String get mediaUrl => '$baseUrl/media';
  String get nearbyUrl => '$baseUrl/nearby';
}

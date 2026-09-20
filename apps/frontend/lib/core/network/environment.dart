import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';

enum Environment {
  local,
  usb,
  wifi,
  production,
}

class EnvironmentService {
  static ApiConfig? _cachedConfig;

  static ApiConfig get config {
    _cachedConfig ??= _resolveConfig();
    return _cachedConfig!;
  }

  static ApiConfig _resolveConfig() {
    const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
    const wsBaseUrl = String.fromEnvironment('WS_BASE_URL');
    const envStr = String.fromEnvironment('APP_ENV');
    const customHost = String.fromEnvironment('HOST_IP', defaultValue: '192.168.1.2');
    const portStr = String.fromEnvironment('GATEWAY_PORT');

    Environment env;

    if (envStr.isEmpty) {
      if (kReleaseMode) {
        dev.log(
          '====================================================\n'
          ' [INFO] APP_ENV compile-time flag not specified in Release build. Defaulting to Environment.production (HOST: api.easychat.com).\n'
          '====================================================',
          name: 'EnvironmentConfig',
        );
        env = Environment.production;
      } else {
        dev.log(
          '====================================================\n'
          ' [INFO] APP_ENV compile-time flag not specified. Defaulting to Environment.wifi (HOST: 192.168.1.2:8090).\n'
          '====================================================',
          name: 'EnvironmentConfig',
        );
        env = Environment.wifi;
      }
    } else {
      switch (envStr.toLowerCase()) {
        case 'local':
        case 'emulator':
          env = Environment.local;
          break;
        case 'usb':
          env = Environment.usb;
          break;
        case 'wifi':
        case 'lan':
          env = Environment.wifi;
          break;
        case 'production':
        case 'prod':
          env = Environment.production;
          break;
        default:
          throw StateError('CRITICAL: Invalid APP_ENV value "$envStr". Valid options are: local, usb, wifi, production');
      }
    }

    final int defaultPort;
    switch (env) {
      case Environment.local:
        defaultPort = 8090;
        break;
      case Environment.usb:
        defaultPort = 18080;
        break;
      case Environment.wifi:
        defaultPort = 8090;
        break;
      case Environment.production:
        defaultPort = 443;
        break;
    }

    final parsedPort = int.tryParse(portStr) ?? defaultPort;

    return ApiConfig(
      environment: env,
      customHost: customHost,
      gatewayPort: parsedPort,
      overrideApiBaseUrl: apiBaseUrl.isNotEmpty ? apiBaseUrl : null,
      overrideWsBaseUrl: wsBaseUrl.isNotEmpty ? wsBaseUrl : null,
    );
  }

  static void printStartupBanner() {
    final cfg = config;
    const mode = kReleaseMode ? 'Release' : (kProfileMode ? 'Profile' : 'Debug');
    final banner = '''

====================================================
Nearby Connect Application Boot
Build Mode  : $mode
Environment : ${cfg.environment.name.toUpperCase()}
API Base    : ${cfg.baseUrl}
WebSocket   : ${cfg.wsUrl}
====================================================
''';
    dev.log(banner, name: 'Bootstrap');
    debugPrint(banner);
  }
}

class ApiConfig {
  final Environment environment;
  final String customHost;
  final int gatewayPort;
  final String? overrideApiBaseUrl;
  final String? overrideWsBaseUrl;

  const ApiConfig({
    required this.environment,
    this.customHost = '192.168.1.2',
    this.gatewayPort = 8090,
    this.overrideApiBaseUrl,
    this.overrideWsBaseUrl,
  });

  factory ApiConfig.fromEnvironment() {
    return EnvironmentService.config;
  }

  String get host {
    switch (environment) {
      case Environment.local:
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

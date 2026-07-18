import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nearby_frontend/core/network/dio_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('HttpCache Management Tests', () {
    test('Cache Hit and Miss Behavior', () {
      final cache = HttpCache(maxEntries: 3, ttl: const Duration(seconds: 10));

      // 1. Initial Get -> Miss
      expect(cache.get('/path1'), isNull);

      // 2. Put entry
      cache.put('/path1', 'data1', 'etag1');

      // 3. Get entry -> Hit
      final entry = cache.get('/path1');
      expect(entry, isNotNull);
      expect(entry!.data, 'data1');
      expect(entry.etag, 'etag1');
    });

    test('TTL Expiration', () async {
      // Configure cache with very short TTL of 50ms
      final cache = HttpCache(maxEntries: 3, ttl: const Duration(milliseconds: 50));

      cache.put('/path1', 'data1', 'etag1');

      // Immediate read -> Hit
      expect(cache.get('/path1'), isNotNull);

      // Wait 100ms
      await Future.delayed(const Duration(milliseconds: 100));

      // Post-TTL read -> Miss (expired entry automatically evicted)
      expect(cache.get('/path1'), isNull);
      expect(cache.size, 0);
    });

    test('LRU Eviction Policy', () {
      final cache = HttpCache(maxEntries: 3, ttl: const Duration(seconds: 10));

      cache.put('/a', 'dataA', 'etagA');
      cache.put('/b', 'dataB', 'etagB');
      cache.put('/c', 'dataC', 'etagC');

      // Access '/a' to make it most recently used
      cache.get('/a');

      // Insert '/d' which forces eviction of least recently used (which is '/b')
      cache.put('/d', 'dataD', 'etagD');

      expect(cache.get('/b'), isNull); // Evicted!
      expect(cache.get('/a'), isNotNull); // Kept!
      expect(cache.get('/c'), isNotNull); // Kept!
      expect(cache.get('/d'), isNotNull); // Kept!
    });

    test('Memory Stability (Max Capacity Bounded)', () {
      final cache = HttpCache(maxEntries: 10, ttl: const Duration(seconds: 10));

      // Populate 50 entries
      for (int i = 0; i < 50; i++) {
        cache.put('/path$i', 'data$i', 'etag$i');
      }

      // Max capacity must be strictly respected
      expect(cache.size, 10);
    });
  });
}

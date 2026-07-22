import http from 'k6/http';
import ws from 'k6/ws';
import { check, sleep, group } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

// Custom Prometheus Performance Metrics
const authDuration = new Trend('auth_duration');
const nearbyDiscoveryDuration = new Trend('nearby_discovery_duration');
const chatMessageLatency = new Trend('chat_message_latency');
const mediaUploadDuration = new Trend('media_upload_duration');
const wsConnectionSuccessRate = new Rate('ws_connection_success_rate');
const failedRequests = new Counter('failed_requests');

export const options = {
  scenarios: {
    // 1. Ramp-up & Load Test (100 -> 500 -> 1000 -> 5000 VUs)
    capacity_load_test: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 100 },  // Tier 1: 100 VUs
        { duration: '5m', target: 100 },
        { duration: '3m', target: 500 },  // Tier 2: 500 VUs
        { duration: '5m', target: 500 },
        { duration: '3m', target: 1000 }, // Tier 3: 1000 VUs
        { duration: '5m', target: 1000 },
        { duration: '5m', target: 5000 }, // Tier 4: 5000 VUs
        { duration: '5m', target: 5000 },
        { duration: '3m', target: 0 },    // Cooldown
      ],
      gracefulStop: '30s',
    },
    // 2. Spike Test Scenario
    spike_test: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 100 },
        { duration: '30s', target: 3000 }, // Instantaneous traffic burst
        { duration: '2m', target: 3000 },
        { duration: '1m', target: 100 },
        { duration: '30s', target: 0 },
      ],
      startTime: '35m', // Executes after load test suite
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'], // < 1% error rate threshold
    http_req_duration: ['p(95)<200', 'p(99)<500'], // Latency SLIs
    ws_connection_success_rate: ['rate>0.99'],
  },
};

const BASE_URL = __ENV.TARGET_URL || 'http://gateway.easychat.local:8090';
const WS_URL = __ENV.WS_TARGET_URL || 'ws://chat.easychat.local:8085/ws';

export default function () {
  let token = '';
  let userId = `user_vu_${__VU}_${__ITER}`;

  group('1. Anonymous Authentication', function () {
    const payload = JSON.stringify({
      device_id: `device_${__VU}_${__ITER}`,
      password: 'Password123!',
    });

    const res = http.post(`${BASE_URL}/api/v1/auth/login`, payload, {
      headers: { 'Content-Type': 'application/json' },
    });

    const success = check(res, {
      'Auth status 200': (r) => r.status === 200,
      'Auth has access_token': (r) => r.json('access_token') !== undefined,
    });

    if (success) {
      token = res.json('access_token');
      authDuration.add(res.timings.duration);
    } else {
      failedRequests.add(1);
    }
  });

  sleep(1);

  group('2. Presence Heartbeat Dispatch', function () {
    const payload = JSON.stringify({
      user_id: userId,
      state: 'online',
      h3_index: '8a2a1072b59ffff',
      timestamp: new Date().toISOString(),
    });

    const res = http.post(`${BASE_URL}/api/v1/presence/heartbeat`, payload, {
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
    });

    check(res, {
      'Presence status 200': (r) => r.status === 200,
    });
  });

  sleep(1);

  group('3. Nearby Discovery (Uber H3 Spatial Index)', function () {
    const url = `${BASE_URL}/api/v1/nearby/discover?h3_index=8a2a1072b59ffff&radius=150`;
    const res = http.get(url, {
      headers: { Authorization: `Bearer ${token}` },
    });

    const success = check(res, {
      'Nearby discovery status 200': (r) => r.status === 200,
      'Nearby response is array': (r) => Array.isArray(r.json('users')),
    });

    if (success) {
      nearbyDiscoveryDuration.add(res.timings.duration);
    }
  });

  sleep(2);

  group('4. Real-time WebSocket Messaging & Receipts', function () {
    const url = `${WS_URL}?token=${token}`;
    const params = { tags: { my_tag: 'chat_websocket' } };

    const res = ws.connect(url, params, function (socket) {
      wsConnectionSuccessRate.add(1);

      socket.on('open', () => {
        // Send simulated instant message packet
        socket.send(
          JSON.stringify({
            type: 'MESSAGE',
            message: {
              message_id: `msg_${__VU}_${Date.now()}`,
              room_id: '00000000-0000-0000-0000-000000000001',
              sender_id: userId,
              encrypted_payload: 'SGVsbG8gTG9hZCBUZXN0!',
            },
          })
        );
      });

      socket.on('message', (data) => {
        const msg = JSON.parse(data);
        if (msg.type === 'RECEIPT') {
          chatMessageLatency.add(Date.now() - msg.receipt.timestamp);
          socket.close();
        }
      });

      socket.setTimeout(function () {
        socket.close();
      }, 5000);
    });

    check(res, {
      'WS Connected': (r) => r && r.status === 101,
    });
  });

  sleep(2);

  group('5. Encrypted Media Attachment Upload', function () {
    const dummyImage = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
    const payload = JSON.stringify({
      filename: `media_${__VU}.png`,
      content_type: 'image/png',
      data: dummyImage,
    });

    const res = http.post(`${BASE_URL}/api/v1/media/upload`, payload, {
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
    });

    const success = check(res, {
      'Media upload status 200': (r) => r.status === 200,
    });

    if (success) {
      mediaUploadDuration.add(res.timings.duration);
    }
  });

  sleep(3);
}

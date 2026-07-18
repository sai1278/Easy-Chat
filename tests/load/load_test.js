import http from 'k6/http';
import ws from 'k6/ws';
import { check, sleep } from 'k6';

// 1. Configure virtual users (VUs) stages for Load and Stress testing
export const options = {
  stages: [
    { duration: '1m', target: 500 },  // Ramp-up to load target
    { duration: '3m', target: 500 },  // Maintain stable load state
    { duration: '1m', target: 2000 }, // Stress test: peak surge traffic
    { duration: '2m', target: 2000 }, // Maintain peak stress load
    { duration: '1m', target: 0 },    // Ramp-down to zero
  ],
  thresholds: {
    http_req_duration: ['p(95)<200'], // 95% of HTTP requests must complete under 200ms
  },
};

const BASE_URL = 'https://easychat.local';
const WS_URL = 'wss://easychat.local/ws';

export default function () {
  const userId = `user_${__VU}_${__ITER}`;
  
  // A. Simulate HTTP API requests
  const payload = JSON.stringify({
    username: userId,
    password: 'SecurePassword123!',
  });
  const params = {
    headers: { 'Content-Type': 'application/json' },
  };

  // 1. Session Login
  const loginRes = http.post(`${BASE_URL}/api/v1/auth/login`, payload, params);
  check(loginRes, {
    'login status is 200': (r) => r.status === 200,
  });

  const authHeaders = {
    'X-User-Id': userId,
    'Authorization': 'Bearer mock-jwt-token-string',
  };

  // 2. Proximity lookup query
  const nearbyRes = http.get(`${BASE_URL}/api/v1/nearby?lat=37.7749&lng=-122.4194`, {
    headers: authHeaders,
  });
  check(nearbyRes, {
    'nearby query returns 200': (r) => r.status === 200,
  });

  // 3. Media multipart attachment upload
  const mediaData = {
    file: http.file('sample-file-bytes', 'attachment.txt', 'text/plain'),
  };
  const mediaRes = http.post(`${BASE_URL}/api/v1/media/upload`, mediaData, {
    headers: authHeaders,
  });
  check(mediaRes, {
    'media upload returns 201': (r) => r.status === 201,
  });

  sleep(1);

  // B. Simulate WebSocket persistent connections & real-time chat messages
  const wsUrl = `${WS_URL}?user_id=${userId}`;
  ws.connect(wsUrl, {}, function (socket) {
    socket.on('open', function () {
      // 1. Send connection handshake ping
      socket.send(JSON.stringify({ type: 'PING' }));

      // 2. Periodically send chat messages
      socket.setInterval(function () {
        socket.send(JSON.stringify({
          type: 'MESSAGE',
          message: {
            message_id: `msg_${userId}_${Date.now()}`,
            room_id: 'lobby_room',
            sender_id: userId,
            encrypted_payload: 'Hello Load Test secure message payload!',
            idempotency_key: `idemp_${userId}_${Date.now()}`,
            created_at: new Date().toISOString(),
          }
        }));
      }, 5000); // Send message every 5 seconds
    });

    socket.on('message', function (message) {
      const data = JSON.parse(message);
      check(data, {
        'message parsing is valid': (d) => d !== null,
      });

      if (data.type === 'MESSAGE') {
        // Automatically reply with delivery receipt ACK
        socket.send(JSON.stringify({
          type: 'RECEIPT',
          receipt: {
            message_id: data.message.message_id,
            room_id: data.message.room_id,
            status: 'DELIVERED',
            timestamp: new Date().toISOString(),
          }
        }));
      }
    });

    socket.on('close', function () {
      // Web socket terminated
    });

    socket.on('error', function (e) {
      // Handle socket error
    });

    // Close socket connection after 30 seconds of activity simulation
    socket.setTimeout(function () {
      socket.close();
    }, 30000);
  });

  sleep(2);
}

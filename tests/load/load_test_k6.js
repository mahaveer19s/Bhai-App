import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 50 },    // Ramp up to 50 users
    { duration: '1m', target: 500 },     // Ramp up to 500 users
    { duration: '2m', target: 1000 },    // Stress test at 1,000 users
    { duration: '30s', target: 0 },      // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<200'],    // 95% of requests must complete below 200ms
    http_req_failed: ['rate<0.01'],      // Failure rate under 1%
  },
};

const BASE_URL = __ENV.API_BASE_URL || 'http://localhost:8000';

export default function () {
  // Health probe check
  const healthRes = http.get(`${BASE_URL}/health`);
  check(healthRes, {
    'status is 200': (r) => r.status === 200,
  });

  // Version check
  const versionRes = http.get(`${BASE_URL}/api/version`);
  check(versionRes, {
    'version ok': (r) => r.status === 200,
  });

  sleep(1);
}

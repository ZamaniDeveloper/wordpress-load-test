import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const target = (__ENV.TARGET_URL || '').replace(/\/+$/, '');
const mode = (__ENV.MODE || 'vus').toLowerCase();
const vus = Number(__ENV.VUS || 25);
const rampUp = __ENV.RAMP_UP || '2m';
const hold = __ENV.HOLD || '5m';
const rampDown = __ENV.RAMP_DOWN || '1m';
const sleepSeconds = Number(__ENV.SLEEP || 1);
const rate = Number(__ENV.RATE || 50);
const duration = __ENV.DURATION || hold;
const timeUnit = __ENV.TIME_UNIT || '1s';
const preAllocatedVUs = Number(__ENV.PRE_ALLOCATED_VUS || Math.max(20, Math.ceil(rate / 2)));
const maxVUs = Number(__ENV.MAX_VUS || Math.max(100, rate * 2));

const paths = (__ENV.PATHS || '/')
  .split(',')
  .map((path) => path.trim())
  .filter(Boolean);

if (!target) {
  throw new Error('Set TARGET_URL, for example: https://example.com');
}

if (!['vus', 'rps'].includes(mode)) {
  throw new Error('MODE must be either "vus" or "rps"');
}

if (paths.length === 0) {
  throw new Error('PATHS must contain at least one request path');
}

const vusOptions = {
  stages: [
    { duration: rampUp, target: vus },
    { duration: hold, target: vus },
    { duration: rampDown, target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.05'],
    http_req_duration: ['p(95)<1500', 'p(99)<3000'],
    checks: ['rate>0.95'],
  },
  userAgent: 'k6 website load test',
  discardResponseBodies: true,
};

const rpsOptions = {
  scenarios: {
    fixed_request_rate: {
      executor: 'constant-arrival-rate',
      rate,
      timeUnit,
      duration,
      preAllocatedVUs,
      maxVUs,
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.20'],
    http_req_duration: ['p(95)<3000', 'p(99)<6000'],
    checks: ['rate>0.80'],
  },
  userAgent: 'k6 website load test',
  discardResponseBodies: true,
};

export const options = mode === 'rps' ? rpsOptions : vusOptions;

const pageDuration = new Trend('site_page_duration', true);
const serverErrors = new Rate('site_5xx_rate');

export default function () {
  const path = paths[Math.floor(Math.random() * paths.length)];
  const url = `${target}${path.startsWith('/') ? path : `/${path}`}`;

  const res = http.get(url, {
    timeout: '30s',
    tags: { path },
  });

  pageDuration.add(res.timings.duration, { path });
  serverErrors.add(res.status >= 500, { path });

  check(res, {
    'status is not 5xx': (r) => r.status < 500,
    'status is 2xx or 3xx': (r) => r.status >= 200 && r.status < 400,
  });

  sleep(sleepSeconds);
}

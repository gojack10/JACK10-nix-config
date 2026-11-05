"""GPU shader and memory-controller feed: uv run bridge.py.

One loopback owner, two isolated Apple-signed helpers. No injected workload,
root access, daemon attachment, or archive of ongoing captures.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import math
from pathlib import Path
import signal
import subprocess
import tempfile
import threading
import time

from helper import Helper, ROOT
from shader import derive

STOP = threading.Event()
LOCK = threading.Lock()
DEMAND = threading.Event()
LAST_REQUEST = 0.0
STATE = {'core': {'status': 'idle'}, 'controller': {'status': 'idle'}}
SOURCE = 'IOReport / AMC / PRIM GFX DCS'


def publish(key, value):
    with LOCK:
        previous = STATE[key]['status']
        STATE[key] = value
    if previous != value['status']:
        print(key + ': ' + value['status'], flush=True)


def shader_value(profile):
    if profile.get('error') != 0:
        raise ValueError('Shader parse failed')
    counts = [counter['count'] for counter in profile.get('counters', [])]
    # Jack selected zero for a valid quiet capture with no sampling interval.
    if counts and max(counts) <= 1:
        return 0.0
    report = derive(profile, metrics=['Shader Core Utilization'])
    metric = report['metrics'].get('Shader Core Utilization', {})
    value = metric.get('time_weighted_mean')
    if (not report['native_ok'] or report['native_error'] or
            not profile.get('timing', {}).get('native_timing_ok') or
            metric.get('count', 0) < 2 or metric.get('count') != metric.get('finite_count') or
            value is None or not math.isfinite(value) or
            not 0 <= metric.get('min', -1) <= metric.get('max', 2) <= 1.000001):
        raise ValueError('Shader timing or derived metric unavailable')
    return min(100.0, value * 100)


def decode_shader(directory):
    for path in directory.glob('profile-*.json'):
        path.unlink()
    subprocess.run([str(ROOT / 'shader-decode'), str(directory / 'catalog.json'),
                    str(directory / 'capture'), str(directory), '0', '--throughput'],
                   capture_output=True, timeout=15)
    values = []
    for index in range(40):
        ring = directory / 'capture' / f'ring-{index}.bin'
        profile = directory / f'profile-{index}.json'
        if ring.stat().st_size == 0:
            values.append(0.0)
            continue
        try:
            values.append(shader_value(json.loads(profile.read_text())))
        except (OSError, ValueError, KeyError):
            values.append(None)
    return values


def controller_value(directory):
    data = json.loads((directory / 'controller.json').read_text())
    read_bytes, write_bytes = data['read_bytes'], data['write_bytes']
    seconds, timestamp = data['seconds'], data['timestamp']
    if (type(read_bytes) is not int or type(write_bytes) is not int or
            min(read_bytes, write_bytes) < 0 or
            type(seconds) not in (int, float) or not math.isfinite(seconds) or not 0 < seconds <= 10 or
            type(timestamp) not in (int, float) or not math.isfinite(timestamp) or timestamp <= 0):
        raise ValueError('Invalid GPU controller interval')
    return {'status': 'live', 'source': SOURCE, 'unit': 'GB/s',
            'read_gb_s': read_bytes / seconds / 1e9,
            'write_gb_s': write_bytes / seconds / 1e9,
            'seconds': seconds, 'timestamp': timestamp}


def requested():
    with LOCK:
        return time.monotonic() - LAST_REQUEST < 5


def wait_for_request():
    while not STOP.is_set():
        DEMAND.wait()
        with LOCK:
            if time.monotonic() - LAST_REQUEST < 5:
                return True
            DEMAND.clear()
    return False


def collect(kind):
    key = 'core' if kind == 'shader' else 'controller'
    while wait_for_request():
        try:
            with tempfile.TemporaryDirectory(prefix='m5-gpu-' + kind + '-', dir='/private/tmp') as tmp:
                directory = Path(tmp)
                with Helper(directory, kind) as helper:
                    while not STOP.is_set() and requested():
                        started = time.monotonic()
                        helper.capture()
                        captured = time.time()
                        if kind == 'shader':
                            values = decode_shader(directory)
                            publish(key, {'values': values, 'timestamp': captured, 'window_ms': 20,
                                          'status': 'live' if all(v is not None for v in values) else 'partial'})
                        else:
                            publish(key, controller_value(directory))
                        STOP.wait(max(0, 1 - (time.monotonic() - started)))
            publish(key, {'status': 'idle'})
        except Exception as error:
            publish(key, {'status': 'unavailable', 'error': str(error)})
            STOP.wait(5)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        global LAST_REQUEST
        if self.headers.get('Host') not in ('127.0.0.1:8766', 'localhost:8766'):
            self.send_error(403)
            return
        if self.path != '/api':
            self.send_error(404)
            return
        with LOCK:
            LAST_REQUEST = time.monotonic()
            for key, value in STATE.items():
                if value['status'] == 'idle':
                    STATE[key] = {'status': 'starting'}
            DEMAND.set()
            states = [value['status'] for value in STATE.values()]
            status = 'live' if all(value == 'live' for value in states) else 'partial'
            body = json.dumps({'status': status, **STATE}, allow_nan=False).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


def main():
    # Bind before starting either helper; another owner of :8766 is a real error.
    server = ThreadingHTTPServer(('127.0.0.1', 8766), Handler)
    workers = [threading.Thread(target=collect, args=(kind,)) for kind in ('shader', 'controller')]

    def shutdown(*_):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, shutdown)
    try:
        for worker in workers:
            worker.start()
        print('GPU bridge | http://127.0.0.1:8766/api', flush=True)
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        STOP.set()
        DEMAND.set()
        server.server_close()
        for worker in workers:
            worker.join()


if __name__ == '__main__':
    main()

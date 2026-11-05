"""Own a fresh signed helper; detach LLDB after installing its FIFO sampler."""
import json
import os
from pathlib import Path
import re
import select
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parent
XCODE = '/Applications/Xcode.app/Contents/Developer'
SHADER_HOST = '/Applications/Xcode.app/Contents/SharedFrameworks/DVTInstrumentsFoundation.framework/Versions/A/Resources/DTServiceHub'
ENV = dict(os.environ, DEVELOPER_DIR=XCODE, TERM='dumb')


class Helper:
    def __init__(self, directory, kind):
        self.directory = directory
        self.kind = kind
        self.process = None
        self.control = None
        self.response = None
        self.helper_pid = None
        self.detached = False
        self.buffer = b''

    def __enter__(self):
        try:
            self.start()
            return self
        except BaseException:
            self.close()
            raise

    def start(self):
        control, response = self.directory / 'control', self.directory / 'response'
        os.mkfifo(control)
        os.mkfifo(response)
        self.control = os.open(control, os.O_RDWR)
        self.response = os.open(response, os.O_RDWR | os.O_NONBLOCK)
        sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], env=ENV, text=True).strip()
        commands = 'settings set auto-confirm true\nsettings set target.preload-symbols false\n'
        if self.kind == 'controller':
            commands += '''target create --arch arm64e /usr/libexec/perfpowermetricd
process launch --stop-at-entry
script t = lldb.debugger.GetSelectedTarget(); b = t.BreakpointCreateByAddress(t.GetModuleAtIndex(0).GetObjectFileEntryPointAddress().GetLoadAddress(t)); print('GPU_ENTRY=%d' % b.GetNumLocations())
'''
        else:
            commands += f'''target create {json.dumps(SHADER_HOST)}
settings set target.run-args --help
breakpoint set --name fclose --condition '$lr >= 0x100000000 && $lr < 0x100010000'
run
breakpoint disable 1
'''
        preparation = f'''settings set target.sdk-path {sdk}
expression -l objc++ -- @import Foundation
expression -l objc++ -- @import ObjectiveC
expression -l objc++ -- @import Darwin
expression -l objc++ --top-level -- #include {json.dumps(str(ROOT / (self.kind + '-capture.h')))}
expression -l objc++ -- int gpu_bridge_prepare(const char *); printf("GPU_READY=%d\\n", gpu_bridge_prepare({json.dumps(str(self.directory))})); fflush(__stdoutp)
'''
        script = self.directory / 'setup.lldb'
        script.write_text(commands)
        self.process = subprocess.Popen(['xcrun', 'lldb', '--no-lldbinit', '-s', str(script)],
                                        env=ENV, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, start_new_session=True)
        if self.kind == 'controller':
            # Do not resume a signed service unless its entry breakpoint exists.
            self.wait(b'\nGPU_ENTRY=')
            if self.wait(b'\n').strip() != '1':
                raise RuntimeError('Controller entry breakpoint unavailable')
            self.send('continue\n')
        self.send(preparation)
        self.wait(b'\nGPU_READY=')
        if self.wait(b'\n').strip() != '0':
            raise RuntimeError(self.kind + ' helper initialization rejected')
        commands = 'expression -l objc++ -- int gpu_bridge_stream(const char *, const char *, const char *); printf("GPU_PC=%p\\n", (void *)&gpu_bridge_stream); fflush(__stdoutp)\n'
        for index, path in enumerate((self.directory, control, response)):
            commands += f'expression -l objc++ -- char *strdup(const char *); printf("GPU_X{index}=%p\\n", strdup({json.dumps(str(path))})); fflush(__stdoutp)\n'
        self.send(commands)
        addresses = []
        for marker in (b'\nGPU_PC=', b'\nGPU_X0=', b'\nGPU_X1=', b'\nGPU_X2='):
            self.wait(marker)
            address = self.wait(b'\n').strip()
            if not re.fullmatch(r'0x[0-9a-fA-F]+', address):
                raise RuntimeError('Invalid helper stream address')
            addresses.append(address)
        commands = ''.join(f'register write x{index} {address}\n' for index, address in enumerate(addresses[1:]))
        commands += f'register write pc {addresses[0]}\nprocess detach\nquit\n'
        self.send(commands)
        self.wait(b'detached')
        self.process.wait(timeout=5)
        self.detached = True
        self.process.stdin.close()
        self.process.stdout.close()

    def send(self, commands):
        self.process.stdin.write(commands.encode())
        self.process.stdin.flush()

    def wait(self, marker):
        deadline = time.monotonic() + 30
        while marker not in self.buffer:
            if time.monotonic() > deadline:
                raise RuntimeError('Helper startup timed out: ' + self.buffer[-1500:].decode(errors='replace'))
            if select.select([self.process.stdout], [], [], 0.2)[0]:
                chunk = os.read(self.process.stdout.fileno(), 65536)
                if not chunk:
                    raise RuntimeError('Helper exited: ' + self.buffer[-1500:].decode(errors='replace'))
                self.buffer += chunk.replace(b'\r', b'')
                launched = re.search(rb'Process (\d+) launched:', self.buffer)
                if launched:
                    self.helper_pid = int(launched[1])
                if b'error: ' in self.buffer or b' error:' in self.buffer:
                    raise RuntimeError('Helper startup failed: ' + self.buffer[-1500:].decode(errors='replace'))
        result, self.buffer = self.buffer.split(marker, 1)
        return result.decode(errors='replace')

    def capture(self):
        os.write(self.control, b's')
        if not select.select([self.response], [], [], 5)[0]:
            raise RuntimeError(self.kind + ' capture timed out')
        result = os.read(self.response, 1)
        if result != b'0' and not (self.kind == 'shader' and result == b'2'):
            raise RuntimeError(self.kind + ' capture rejected')

    def close(self):
        try:
            if self.control is not None:
                os.write(self.control, b'q')
            if self.detached and self.helper_pid:
                for _ in range(20):
                    try:
                        os.kill(self.helper_pid, 0)
                    except ProcessLookupError:
                        break
                    time.sleep(0.05)
                else:
                    os.kill(self.helper_pid, signal.SIGTERM)
            elif self.process is not None:
                try:
                    self.process.communicate(b'process kill\nquit\n', timeout=5)
                except (subprocess.TimeoutExpired, BrokenPipeError):
                    os.killpg(self.process.pid, signal.SIGKILL)
                    self.process.wait()
        finally:
            for descriptor in (self.control, self.response):
                if descriptor is not None:
                    os.close(descriptor)
            self.control = self.response = None

    def __exit__(self, *_):
        self.close()

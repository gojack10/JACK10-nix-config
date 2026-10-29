"""Run without opening a microphone: uv run --no-project python scripts/test_record_mic.py"""
import os
from pathlib import Path
import signal
import select
import subprocess
import tempfile
import time
import unittest


FAKE_FFMPEG = r'''#!/bin/bash
printf '%s\n' "$*" >> "$CALLS"
case " $* " in
  *' -list_devices true '*)
    case "$CASE" in
      discovery-hang) exec sleep 60 ;;
      no-device) echo 'device enumeration failed verbatim' >&2; exit 1 ;;
    esac
    printf 'AVFoundation audio devices:\n[0] MacBook Pro Microphone\n[1] AirPods Microphone\n' >&2
    exit 1 ;;
esac
# Capture progress FD and final output path; never perform a mic preflight.
previous=''
for arg in "$@"; do
  if [ "$previous" = '-progress' ]; then fd="${arg#pipe:}"; fi
  previous="$arg"
  out="$arg"
done
case "$CASE" in
  hang) exec sleep 60 ;;
  header-only)
    printf 'header' > "$out"
    eval "printf 'total_size=6\nout_time_us=0\nprogress=continue\n' >&$fd"
    exec sleep 60 ;;
  fail) echo 'original FFmpeg error: cannot start input' >&2; exit 42 ;;
  early-exit) exit 0 ;;
  real-audio|real-q|real-signal)
    # Replace only the hardware input with a synthetic source. Keep all actual
    # encoder, muxer, flushing and progress options under test.
    args=()
    for arg in "$@"; do
      case "$arg" in
        avfoundation) arg=lavfi ;;
        :0) arg=anullsrc=r=48000:cl=mono ;;
      esac
      args+=("$arg")
    done
    last=$((${#args[@]} - 1))
    unset "args[$last]"
    if [ "$CASE" = real-audio ]; then
      exec "$REAL_FFMPEG" "${args[@]}" -t 0.4 "$out"
    fi
    exec "$REAL_FFMPEG" -re "${args[@]}" "$out" ;;
esac
printf 'saved audio' > "$out"
eval "printf 'total_size=11\nout_time_us=200000\nprogress=continue\n' >&$fd"
if [ "$CASE" = 'signal' ]; then
  trap 'exit 0' INT TERM
  while :; do sleep 0.1; done
fi
'''


class RecordingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='record-mic-tests-')
        cls.root = Path(cls.temp.name)
        cls.ffmpeg = cls.root / 'ffmpeg'
        cls.ffmpeg.write_text(FAKE_FFMPEG)
        cls.ffmpeg.chmod(0o755)
        logger = cls.root / 'log'
        logger.write_text('#!/bin/sh\nprintf "system audio error: mlock failed\\n"\nprintf "%s\\n" "$*" >> "$LOG_CALLS"\n')
        logger.chmod(0o755)
        cls.binary = cls.root / 'record-mic'
        subprocess.run([
            'clang', '-O2', '-Wall', '-Wextra', '-Werror',
            '-DSTARTUP_TIMEOUT_SECONDS=1',
            f'-DFFMPEG_PATH="{cls.ffmpeg}"', f'-DSYSTEM_LOG_PATH="{logger}"',
            str(Path(__file__).with_name('record-mic.c')), '-o', str(cls.binary),
        ], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def setUp(self):
        self.work = Path(tempfile.mkdtemp(dir=self.root))
        self.calls = self.work / 'calls'
        self.log_calls = self.work / 'log-calls'

    def start(self, case, *args):
        env = dict(os.environ, CASE=case, CALLS=str(self.calls), LOG_CALLS=str(self.log_calls))
        return subprocess.Popen([str(self.binary), '--dir', str(self.work), *args],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                stdin=subprocess.PIPE, text=True, env=env, start_new_session=True)

    def finish(self, proc):
        try:
            stdout, stderr = proc.communicate(timeout=6)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.communicate()
            self.fail('recorder did not terminate promptly')
        return proc.returncode, stdout, stderr

    def test_success_uses_one_capture_and_stdout_contains_only_path(self):
        code, stdout, stderr = self.finish(self.start('success'))
        self.assertEqual(code, 0, stderr)
        self.assertEqual(Path(stdout.strip()).read_text(), 'saved audio')
        self.assertIn('Recording mic', stderr)
        self.assertEqual(len(self.calls.read_text().splitlines()), 2)  # discovery + capture
        self.assertNotIn('-t 0.25', self.calls.read_text())
        self.assertFalse(self.log_calls.exists())

    def test_hung_start_fails_with_system_diagnostics_and_no_stdout(self):
        code, stdout, stderr = self.finish(self.start('hang'))
        self.assertNotEqual(code, 0)
        self.assertEqual(stdout, '')
        self.assertIn('STARTUP FAILED', stderr)
        self.assertIn('mlock failed', stderr)
        self.assertNotIn('Recording mic', stderr)
        self.assertIn('coreaudiod', self.log_calls.read_text())

    def test_header_alone_is_not_recording_and_partial_file_is_kept(self):
        code, stdout, stderr = self.finish(self.start('header-only'))
        self.assertNotEqual(code, 0)
        self.assertEqual(stdout, '')
        self.assertNotIn('Recording mic', stderr)
        self.assertEqual(next(self.work.glob('mic-*.opus')).read_text(), 'header')
        self.assertIn('keeping audio', stderr)

    def test_original_error_and_status_are_preserved(self):
        code, stdout, stderr = self.finish(self.start('fail'))
        self.assertEqual(code, 42)
        self.assertEqual(stdout, '')
        self.assertIn('original FFmpeg error: cannot start input', stderr)
        self.assertIn('mlock failed', stderr)

    def test_broken_downstream_pipe_stops_capture_and_keeps_audio(self):
        proc = self.start('signal')
        proc.stdout.close()
        proc.stdout = None
        code, _, stderr = self.finish(proc)
        self.assertNotEqual(code, 0)
        self.assertIn('cannot deliver audio path', stderr)
        self.assertEqual(next(self.work.glob('mic-*.opus')).read_text(), 'saved audio')

    def test_successful_exit_without_audio_is_failure(self):
        code, stdout, stderr = self.finish(self.start('early-exit'))
        self.assertNotEqual(code, 0)
        self.assertEqual(stdout, '')
        self.assertIn('recording did not start', stderr)

    def test_discovery_is_also_bounded_and_preserves_errors(self):
        for case in ('discovery-hang', 'no-device'):
            with self.subTest(case=case):
                code, stdout, stderr = self.finish(self.start(case))
                self.assertNotEqual(code, 0)
                self.assertEqual(stdout, '')
                self.assertIn('timed out' if case.endswith('hang') else 'device enumeration failed verbatim', stderr)

    def test_airpods_selection_is_preserved(self):
        code, stdout, stderr = self.finish(self.start('success', '--airpods'))
        self.assertEqual(code, 0, stderr)
        self.assertIn('-i :1', self.calls.read_text())
        self.assertTrue(Path(stdout.strip()).exists())

    def test_ctrl_c_keeps_audio_and_reaps_capture(self):
        proc = self.start('signal')
        # Poll the test fixture, not a production microphone or background job.
        deadline = time.monotonic() + 3
        while not list(self.work.glob('mic-*.opus')) and time.monotonic() < deadline:
            time.sleep(0.01)
        time.sleep(0.2)
        os.killpg(proc.pid, signal.SIGINT)
        code, stdout, stderr = self.finish(proc)
        self.assertEqual(code, 130, stderr)
        self.assertTrue(Path(stdout.strip()).exists())
        self.assertNotIn('mlock failed', stderr)

    @unittest.skipUnless(os.environ.get('REAL_FFMPEG'), 'set REAL_FFMPEG to test real FFmpeg interaction')
    def test_real_ffmpeg_q_and_ctrl_c_preserve_saved_audio(self):
        for case in ('real-q', 'real-signal'):
            with self.subTest(case=case):
                # Avoid timestamp collisions between the two recordings.
                self.work = Path(tempfile.mkdtemp(dir=self.root))
                proc = self.start(case)
                if not select.select([proc.stdout], [], [], 3)[0]:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.communicate()
                    self.fail('real FFmpeg never became ready')
                path = Path(proc.stdout.readline().strip())
                if case == 'real-q':
                    proc.stdin.write('q')
                    proc.stdin.flush()
                else:
                    os.killpg(proc.pid, signal.SIGINT)
                code, stdout, stderr = self.finish(proc)
                self.assertEqual(code, 0 if case == 'real-q' else 130, stderr)
                self.assertEqual(stdout, '')
                self.assertTrue(path.exists())
                subprocess.run([os.environ['REAL_FFMPEG'], '-v', 'error', '-i', str(path),
                                '-f', 'null', '-'], check=True, capture_output=True)
                self.assertNotIn('mlock failed', stderr)

    @unittest.skipUnless(os.environ.get('REAL_FFMPEG'), 'set REAL_FFMPEG to test the real encoder with synthetic silence')
    def test_real_ffmpeg_saved_silent_audio_is_success(self):
        code, stdout, stderr = self.finish(self.start('real-audio'))
        self.assertEqual(code, 0, stderr)
        audio = Path(stdout.strip())
        self.assertGreater(audio.stat().st_size, 137)
        decoded = subprocess.run([os.environ['REAL_FFMPEG'], '-v', 'error', '-i', str(audio),
                                  '-f', 's16le', '-'], capture_output=True, check=True)
        self.assertGreater(len(decoded.stdout), 0)
        self.assertEqual(set(decoded.stdout), {0})


if __name__ == '__main__':
    unittest.main()

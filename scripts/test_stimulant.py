#!/usr/bin/env python3

import argparse
import runpy
from subprocess import CompletedProcess
from unittest.mock import patch

stimulant = runpy.run_path("scripts/stimulant")

assert stimulant["positive_seconds"]("7200") == 7200
try:
    stimulant["positive_seconds"]("0")
except argparse.ArgumentTypeError:
    pass
else:
    raise AssertionError("zero seconds accepted")

with patch("subprocess.run", return_value=CompletedProcess([], 0, "SleepDisabled 1\n")):
    assert stimulant["enabled"]()

with patch("subprocess.run", return_value=CompletedProcess([], 0)) as run:
    stimulant["set_enabled"](True)
    assert run.call_args.args[0] == ["sudo", "/usr/bin/pmset", "-a", "disablesleep", "1"]

with patch("subprocess.run", return_value=CompletedProcess([], 0)) as run:
    stimulant["run_timer"](7200)
    command = run.call_args.args[0]
    assert command[:3] == ["sudo", "/bin/sh", "-c"]
    assert command[-1] == "7200"
    assert "trap cleanup EXIT HUP INT TERM" in command[3]

print("stimulant checks passed")

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
    stimulant["set_enabled"](False)
    assert [c.args[0] for c in run.call_args_list] == [
        ["sudo", "/usr/bin/pmset", "-a", "restoredefaults"],
        ["sudo", "/usr/bin/pmset", "-a", "disablesleep", "0"],
    ], "restore must return to Apple defaults and clear the lid override"

with patch("subprocess.run", return_value=CompletedProcess([], 0)) as run:
    stimulant["set_enabled"](True)
    assert run.call_args.args[0] == [
        "sudo", "/usr/bin/pmset", "-a",
        "disablesleep", "1", "displaysleep", "0", "sleep", "0", "disksleep", "0",
    ], "awake must cover lid, display, idle sleep and disk sleep"

# The timed mode escalates only pmset, never a root shell, and always restores.
with patch("subprocess.run", return_value=CompletedProcess([], 0)) as run, \
        patch("time.sleep") as sleep:
    stimulant["run_timer"](7200)
    assert sleep.call_args.args == (7200,)
    escalated = [c.args[0] for c in run.call_args_list]
    assert all(cmd[:2] == ["sudo", "/usr/bin/pmset"] for cmd in escalated), escalated
    assert escalated[0][2:4] == ["-a", "disablesleep"]
    assert ["-a", "restoredefaults"] in [cmd[2:] for cmd in escalated]

with patch("subprocess.run", return_value=CompletedProcess([], 0)) as run, \
        patch("time.sleep", side_effect=KeyboardInterrupt):
    stimulant["run_timer"](7200)
    assert ["-a", "restoredefaults"] in [c.args[0][2:] for c in run.call_args_list], \
        "Ctrl-C must still restore defaults"

print("stimulant: ok")

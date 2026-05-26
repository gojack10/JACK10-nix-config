use anyhow::{Context, Result};

use crate::config::{parse_duration, Config};
use crate::daemon::{is_daemon_running, send_command, spawn_daemon};
use crate::timer::{DaemonCommand, DaemonResponse};

/// Start a new deep work session
pub fn start(duration: Option<&str>, config: &Config) -> Result<()> {
    let duration_secs = match duration {
        Some(d) => parse_duration(d)?.as_secs(),
        None => config.default_duration()?.as_secs(),
    };

    // Ensure daemon is running
    if !is_daemon_running() {
        spawn_daemon().context("Failed to start daemon")?;
    }

    let response = send_command(DaemonCommand::Start { duration_secs })?;

    match response {
        DaemonResponse::Ok => {
            let mins = duration_secs / 60;
            println!("Started {}m deep work session", mins);
            Ok(())
        }
        DaemonResponse::AlreadyRunning => {
            println!("A session is already running. Use 'deepwork stop' to end it.");
            Ok(())
        }
        DaemonResponse::Error(e) => {
            anyhow::bail!("Failed to start session: {}", e)
        }
        _ => {
            anyhow::bail!("Unexpected response from daemon")
        }
    }
}

/// Start a session without printing (for raw mode contexts)
pub fn start_quiet(duration: Option<&str>, config: &Config) -> Result<()> {
    let duration_secs = match duration {
        Some(d) => parse_duration(d)?.as_secs(),
        None => config.default_duration()?.as_secs(),
    };

    if !is_daemon_running() {
        spawn_daemon().context("Failed to start daemon")?;
    }

    let response = send_command(DaemonCommand::Start { duration_secs })?;

    match response {
        DaemonResponse::Ok | DaemonResponse::AlreadyRunning => Ok(()),
        DaemonResponse::Error(e) => anyhow::bail!("Failed to start session: {}", e),
        _ => anyhow::bail!("Unexpected response from daemon"),
    }
}

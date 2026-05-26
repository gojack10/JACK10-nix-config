use anyhow::Result;

use crate::config::Config;
use crate::daemon::{is_daemon_running, send_command};
use crate::timer::{DaemonCommand, DaemonResponse, TimerState};

use super::start::start;

/// Stop the current session (counts as completed)
pub fn stop() -> Result<()> {
    if !is_daemon_running() {
        println!("No session running.");
        return Ok(());
    }

    let response = send_command(DaemonCommand::Stop)?;

    match response {
        DaemonResponse::Ok => {
            println!("Session completed!");
            Ok(())
        }
        DaemonResponse::NotRunning => {
            println!("No session running.");
            Ok(())
        }
        DaemonResponse::Error(e) => {
            anyhow::bail!("Failed to stop session: {}", e)
        }
        _ => {
            anyhow::bail!("Unexpected response from daemon")
        }
    }
}

/// Cancel the current session (doesn't count)
pub fn cancel() -> Result<()> {
    if !is_daemon_running() {
        println!("No session running.");
        return Ok(());
    }

    let response = send_command(DaemonCommand::Cancel)?;

    match response {
        DaemonResponse::Ok => {
            println!("Session cancelled.");
            Ok(())
        }
        DaemonResponse::NotRunning => {
            println!("No session running.");
            Ok(())
        }
        DaemonResponse::Error(e) => {
            anyhow::bail!("Failed to cancel session: {}", e)
        }
        _ => {
            anyhow::bail!("Unexpected response from daemon")
        }
    }
}

/// Toggle: if running/overtime → stop, if idle → start
pub fn toggle(duration: Option<&str>, config: &Config) -> Result<()> {
    // Check current state
    if is_daemon_running() {
        let response = send_command(DaemonCommand::GetStatus)?;
        if let DaemonResponse::State(state) = response {
            match state {
                TimerState::Running { .. } | TimerState::Overtime { .. } => {
                    // Session active → stop it
                    return stop();
                }
                TimerState::Idle { .. } | TimerState::Completed { .. } => {
                    // No active session → start new one
                    return start(duration, config);
                }
            }
        }
    }

    // Daemon not running → start new session
    start(duration, config)
}

/// Stop session without printing (for raw mode contexts)
pub fn stop_quiet() -> Result<()> {
    if !is_daemon_running() {
        return Ok(());
    }

    let response = send_command(DaemonCommand::Stop)?;

    match response {
        DaemonResponse::Ok | DaemonResponse::NotRunning => Ok(()),
        DaemonResponse::Error(e) => anyhow::bail!("Failed to stop session: {}", e),
        _ => anyhow::bail!("Unexpected response from daemon"),
    }
}

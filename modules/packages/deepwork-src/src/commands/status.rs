use anyhow::Result;
use crossterm::{
    cursor::{Hide, MoveTo, Show},
    event::{self, Event, KeyCode, KeyModifiers},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, Clear, ClearType},
};
use std::io::{self, IsTerminal, Write};
use std::time::Duration;

use crate::config::Config;
use crate::daemon::{is_daemon_running, send_command};
use crate::db::Database;
use crate::timer::{format_time, progress_bar, remaining_secs, DaemonCommand, DaemonResponse, TimerState};

use super::start::start_quiet;
use super::stop::stop_quiet;

/// RAII guard for terminal raw mode - ensures cleanup on drop
struct TerminalGuard;

impl TerminalGuard {
    fn new() -> Result<Self> {
        enable_raw_mode()?;
        execute!(io::stdout(), Clear(ClearType::All), MoveTo(0, 0), Hide)?;
        Ok(Self)
    }
}

impl Drop for TerminalGuard {
    fn drop(&mut self) {
        let _ = execute!(io::stdout(), Show);
        let _ = disable_raw_mode();
    }
}

/// Output current status (optionally in watch mode)
pub fn status(polybar: bool, watch: bool, config: &Config) -> Result<()> {
    if !watch {
        let state = get_current_state()?;
        let output = format_state(&state, config, polybar);
        println!("{}", output);
        return Ok(());
    }

    watch_status(config)
}

/// Get current timer state
fn get_current_state() -> Result<TimerState> {
    if !is_daemon_running() {
        // No daemon, return idle with count from database
        let db = Database::open()?;
        let today_count = db.today_count().unwrap_or(0);
        return Ok(TimerState::Idle { today_count });
    }

    let response = send_command(DaemonCommand::GetStatus)?;

    match response {
        DaemonResponse::State(state) => Ok(state),
        _ => {
            // Fallback to idle
            let db = Database::open()?;
            let today_count = db.today_count().unwrap_or(0);
            Ok(TimerState::Idle { today_count })
        }
    }
}

fn watch_status(config: &Config) -> Result<()> {
    let stdout_is_tty = io::stdout().is_terminal();
    let term = std::env::var("TERM").unwrap_or_default();

    if !stdout_is_tty || term.is_empty() || term == "dumb" {
        // Non-interactive fallback: just print once
        let state = get_current_state()?;
        let output = format_state(&state, config, false);
        println!("{}", output);
        return Ok(());
    }

    // Interactive watch mode with raw terminal
    let _guard = TerminalGuard::new()?;
    let mut confirm_quit = false;

    loop {
        // Move to top-left and overwrite in-place (no clear to avoid flashing)
        execute!(io::stdout(), MoveTo(0, 0))?;

        let state = get_current_state()?;
        let output = format_state(&state, config, false);

        // Build hint based on current state
        let hint = match &state {
            TimerState::Idle { .. } | TimerState::Completed { .. } => {
                "\x1b[2m[Ctrl+D: start 1h30m | Ctrl+C: quit]\x1b[0m"
            }
            TimerState::Running { .. } | TimerState::Overtime { .. } => {
                "\x1b[2m[Ctrl+D: stop | Ctrl+C: quit]\x1b[0m"
            }
        };

        // Clear to end of line after each line to handle varying content lengths
        let clear_eol = "\x1b[K";
        if confirm_quit {
            print!("{}{}\r\n{}\r\n{}{}\r\n{}\r\nQuit? (y/n){}", output, clear_eol, clear_eol, hint, clear_eol, clear_eol, clear_eol);
        } else {
            print!("{}{}\r\n{}\r\n{}{}", output, clear_eol, clear_eol, hint, clear_eol);
        }
        // Clear any remaining lines from previous state (e.g., after dismissing quit prompt)
        print!("\x1b[J");
        io::stdout().flush()?;

        // Poll for input (100ms timeout for responsive updates)
        if event::poll(Duration::from_millis(100))? {
            if let Event::Key(key) = event::read()? {
                if confirm_quit {
                    match key.code {
                        KeyCode::Char('y') | KeyCode::Char('Y') => {
                            break;
                        }
                        _ => {
                            confirm_quit = false;
                        }
                    }
                } else {
                    match (key.code, key.modifiers) {
                        (KeyCode::Char('c'), KeyModifiers::CONTROL) => {
                            confirm_quit = true;
                        }
                        (KeyCode::Char('d'), KeyModifiers::CONTROL) => {
                            handle_toggle(config)?;
                            // Brief delay for daemon to update state
                            std::thread::sleep(Duration::from_millis(50));
                        }
                        _ => {}
                    }
                }
            }
        }
    }

    Ok(())
}

/// Handle Ctrl+D toggle: start 1h30m if idle, stop if running
fn handle_toggle(config: &Config) -> Result<()> {
    let state = get_current_state()?;
    match state {
        TimerState::Idle { .. } | TimerState::Completed { .. } => {
            start_quiet(Some("1h30m"), config)?;
        }
        TimerState::Running { .. } | TimerState::Overtime { .. } => {
            stop_quiet()?;
        }
    }
    Ok(())
}

/// Format state for display
fn format_state(state: &TimerState, config: &Config, polybar: bool) -> String {
    let width = config.display.progress_width;

    match state {
        TimerState::Idle { today_count } => {
            let bar = "─".repeat(width);
            // No color override - uses module's format-foreground
            format!("{} {} Ready ({})", config.display.icon_idle, bar, today_count)
        }

        TimerState::Running {
            planned_duration_secs,
            elapsed_secs,
            today_count,
            ..
        } => {
            let remaining = remaining_secs(*planned_duration_secs, *elapsed_secs);
            let bar = progress_bar(*elapsed_secs, *planned_duration_secs, width);
            let time = format_time(remaining);
            // No color override - uses module's format-foreground
            format!("{} {} {} ({})", config.display.icon_running, bar, time, today_count)
        }

        TimerState::Completed { today_count, .. } => {
            if polybar {
                format!(
                    "%{{F#88cc88}}{} Done! ({})%{{F-}}",
                    config.display.icon_complete, today_count
                )
            } else {
                format!("{} Done! ({})", config.display.icon_complete, today_count)
            }
        }

        TimerState::Overtime {
            overtime_secs,
            today_count,
            ..
        } => {
            let time = format!("+{}", format_time(*overtime_secs));
            if polybar {
                format!(
                    "%{{F#ffcc00}}{} {} ({})%{{F-}}",
                    config.display.icon_overtime, time, today_count
                )
            } else {
                format!("{} {} ({})", config.display.icon_overtime, time, today_count)
            }
        }
    }
}

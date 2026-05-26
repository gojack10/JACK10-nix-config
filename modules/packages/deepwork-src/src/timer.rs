use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Timer state that can be serialized for IPC
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TimerState {
    Idle {
        today_count: i64,
    },
    Running {
        session_id: i64,
        started_at: DateTime<Utc>,
        planned_duration_secs: u64,
        elapsed_secs: u64,
        today_count: i64,
    },
    Completed {
        session_id: i64,
        today_count: i64,
        /// Timestamp when completion was registered (for 3s flash)
        completed_at: DateTime<Utc>,
    },
    Overtime {
        session_id: i64,
        started_at: DateTime<Utc>,
        planned_duration_secs: u64,
        elapsed_secs: u64,
        overtime_secs: u64,
        today_count: i64,
    },
}

impl TimerState {
    pub fn today_count(&self) -> i64 {
        match self {
            TimerState::Idle { today_count } => *today_count,
            TimerState::Running { today_count, .. } => *today_count,
            TimerState::Completed { today_count, .. } => *today_count,
            TimerState::Overtime { today_count, .. } => *today_count,
        }
    }
}

/// Commands that can be sent to the daemon via IPC
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum DaemonCommand {
    Start { duration_secs: u64 },
    Stop,
    Cancel,
    GetStatus,
    Shutdown,
    /// Reload today_count from database (used after sync)
    RefreshCount,
    /// Reopen database connection (used after sync replaces the file)
    ReloadDatabase,
}

/// Response from daemon
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum DaemonResponse {
    Ok,
    State(TimerState),
    Error(String),
    AlreadyRunning,
    NotRunning,
}

/// Format time as MM:SS or H:MM:SS
pub fn format_time(total_secs: u64) -> String {
    let hours = total_secs / 3600;
    let mins = (total_secs % 3600) / 60;
    let secs = total_secs % 60;

    if hours > 0 {
        format!("{}:{:02}:{:02}", hours, mins, secs)
    } else {
        format!("{:02}:{:02}", mins, secs)
    }
}

/// Format time for display (minutes and seconds only for short durations)
pub fn format_time_short(total_secs: u64) -> String {
    let mins = total_secs / 60;
    let secs = total_secs % 60;
    format!("{}:{:02}", mins, secs)
}

/// Calculate remaining time
pub fn remaining_secs(planned: u64, elapsed: u64) -> u64 {
    planned.saturating_sub(elapsed)
}

/// Generate progress bar string
pub fn progress_bar(elapsed: u64, planned: u64, width: usize) -> String {
    if planned == 0 {
        return "─".repeat(width);
    }

    let progress = (elapsed as f64 / planned as f64).min(1.0);
    let filled = (progress * width as f64).round() as usize;
    let empty = width - filled;

    format!("{}{}", "━".repeat(filled), "░".repeat(empty))
}

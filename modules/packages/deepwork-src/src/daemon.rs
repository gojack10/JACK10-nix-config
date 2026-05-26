use anyhow::{Context, Result};
use chrono::{Local, NaiveDate, Utc};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use std::{fs, thread};

use crate::config::{socket_path, Config};
use crate::db::Database;
use crate::notify::Notifier;
use crate::timer::{DaemonCommand, DaemonResponse, TimerState};

/// The daemon process that manages the timer
pub struct Daemon {
    config: Config,
    db: Database,
    notifier: Notifier,
    state: TimerState,
    session_id: Option<i64>,
    planned_duration_secs: u64,
    start_instant: Option<Instant>,
    overtime_nudge_sent: bool,
    /// Track the current date to detect day changes
    last_known_date: NaiveDate,
    /// Track last tick time to detect sleep/resume
    last_tick: Instant,
}

impl Daemon {
    pub fn new(config: Config, db: Database) -> Self {
        let today_count = db.today_count().unwrap_or(0);
        Self {
            config,
            db,
            notifier: Notifier::new(),
            state: TimerState::Idle { today_count },
            session_id: None,
            planned_duration_secs: 0,
            start_instant: None,
            overtime_nudge_sent: false,
            last_known_date: Local::now().date_naive(),
            last_tick: Instant::now(),
        }
    }

    /// Refresh the today_count from database if needed
    /// Returns true if the count was refreshed
    fn maybe_refresh_count(&mut self) -> bool {
        let now = Local::now();
        let today = now.date_naive();
        let time_since_last_tick = self.last_tick.elapsed();

        // Refresh if:
        // 1. Date changed (new day)
        // 2. Significant time jump detected (system resumed from sleep)
        let date_changed = today != self.last_known_date;
        let time_jump = time_since_last_tick > Duration::from_secs(60); // Normally ticks every 100ms

        if date_changed || time_jump {
            // Update tracking fields
            self.last_known_date = today;

            // Refresh count from database
            if let Ok(new_count) = self.db.today_count() {
                // Update the count in current state
                match &mut self.state {
                    TimerState::Idle { today_count } => *today_count = new_count,
                    TimerState::Running { today_count, .. } => *today_count = new_count,
                    TimerState::Completed { today_count, .. } => *today_count = new_count,
                    TimerState::Overtime { today_count, .. } => *today_count = new_count,
                }
                return true;
            }
        }

        false
    }

    /// Run the daemon, listening on Unix socket
    pub fn run(mut self) -> Result<()> {
        let socket_path = socket_path();

        // Remove stale socket if exists
        let _ = fs::remove_file(&socket_path);

        let listener = UnixListener::bind(&socket_path)
            .with_context(|| format!("Failed to bind to socket: {:?}", socket_path))?;

        // Set socket to non-blocking for periodic updates
        listener.set_nonblocking(true)?;

        let running = Arc::new(AtomicBool::new(true));
        let r = running.clone();

        // Handle SIGTERM/SIGINT
        ctrlc::set_handler(move || {
            r.store(false, Ordering::SeqCst);
        })
        .ok();

        eprintln!("Daemon started, listening on {:?}", socket_path);

        while running.load(Ordering::SeqCst) {
            // Accept connections (non-blocking)
            match listener.accept() {
                Ok((stream, _)) => {
                    if let Err(e) = self.handle_client(stream) {
                        eprintln!("Error handling client: {}", e);
                    }
                }
                Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    // No connection waiting, continue
                }
                Err(e) => {
                    eprintln!("Accept error: {}", e);
                }
            }

            // Update timer state
            self.tick();

            // Small sleep to avoid busy-waiting
            thread::sleep(Duration::from_millis(100));
        }

        // Cleanup
        let _ = fs::remove_file(&socket_path);
        eprintln!("Daemon stopped");
        Ok(())
    }

    /// Handle a client connection
    fn handle_client(&mut self, stream: UnixStream) -> Result<()> {
        stream.set_read_timeout(Some(Duration::from_secs(1)))?;
        stream.set_write_timeout(Some(Duration::from_secs(1)))?;

        let mut reader = BufReader::new(&stream);
        let mut line = String::new();

        if reader.read_line(&mut line)? == 0 {
            return Ok(());
        }

        let cmd: DaemonCommand = serde_json::from_str(&line)
            .with_context(|| format!("Invalid command: {}", line))?;

        let response = self.handle_command(cmd);

        let mut stream = stream;
        let response_json = serde_json::to_string(&response)?;
        writeln!(stream, "{}", response_json)?;
        stream.flush()?;

        Ok(())
    }

    /// Process a command and return response
    fn handle_command(&mut self, cmd: DaemonCommand) -> DaemonResponse {
        match cmd {
            DaemonCommand::Start { duration_secs } => self.cmd_start(duration_secs),
            DaemonCommand::Stop => self.cmd_stop(),
            DaemonCommand::Cancel => self.cmd_cancel(),
            DaemonCommand::GetStatus => DaemonResponse::State(self.state.clone()),
            DaemonCommand::Shutdown => {
                // Will be handled by the main loop
                std::process::exit(0);
            }
            DaemonCommand::RefreshCount => self.cmd_refresh_count(),
            DaemonCommand::ReloadDatabase => self.cmd_reload_database(),
        }
    }

    fn cmd_start(&mut self, duration_secs: u64) -> DaemonResponse {
        match &self.state {
            TimerState::Running { .. } | TimerState::Overtime { .. } => {
                DaemonResponse::AlreadyRunning
            }
            _ => {
                // Start new session in database
                match self.db.start_session(duration_secs as i64) {
                    Ok(id) => {
                        self.session_id = Some(id);
                        self.planned_duration_secs = duration_secs;
                        self.start_instant = Some(Instant::now());
                        self.overtime_nudge_sent = false;

                        let today_count = self.db.today_count().unwrap_or(0);
                        self.state = TimerState::Running {
                            session_id: id,
                            started_at: Utc::now(),
                            planned_duration_secs: duration_secs,
                            elapsed_secs: 0,
                            today_count,
                        };
                        DaemonResponse::Ok
                    }
                    Err(e) => DaemonResponse::Error(e.to_string()),
                }
            }
        }
    }

    fn cmd_stop(&mut self) -> DaemonResponse {
        // Minimum time (60 minutes) for a session to count as completed
        const MIN_VALID_SESSION_SECS: u64 = 60 * 60;

        match &self.state {
            TimerState::Running { session_id, .. } | TimerState::Overtime { session_id, .. } => {
                let elapsed = self.start_instant.map(|s| s.elapsed().as_secs()).unwrap_or(0);

                // If less than 60 minutes, cancel instead of complete
                if elapsed < MIN_VALID_SESSION_SECS {
                    if let Err(e) = self.db.cancel_session(*session_id) {
                        return DaemonResponse::Error(e.to_string());
                    }

                    let today_count = self.db.today_count().unwrap_or(0);
                    self.state = TimerState::Idle { today_count };
                    self.session_id = None;
                    self.start_instant = None;
                    return DaemonResponse::Ok;
                }

                // 60+ minutes: complete the session
                let overtime = elapsed.saturating_sub(self.planned_duration_secs);

                if let Err(e) = self.db.complete_session(*session_id, elapsed as i64, overtime as i64) {
                    return DaemonResponse::Error(e.to_string());
                }

                let today_count = self.db.today_count().unwrap_or(0);

                // Send completion notification
                if self.config.notifications.enabled && self.config.notifications.on_complete {
                    self.notifier.session_complete(today_count);
                }

                self.state = TimerState::Completed {
                    session_id: *session_id,
                    today_count,
                    completed_at: Utc::now(),
                };

                self.session_id = None;
                self.start_instant = None;
                DaemonResponse::Ok
            }
            _ => DaemonResponse::NotRunning,
        }
    }

    fn cmd_cancel(&mut self) -> DaemonResponse {
        match &self.state {
            TimerState::Running { session_id, .. } | TimerState::Overtime { session_id, .. } => {
                if let Err(e) = self.db.cancel_session(*session_id) {
                    return DaemonResponse::Error(e.to_string());
                }

                let today_count = self.db.today_count().unwrap_or(0);
                self.state = TimerState::Idle { today_count };
                self.session_id = None;
                self.start_instant = None;
                DaemonResponse::Ok
            }
            _ => DaemonResponse::NotRunning,
        }
    }

    fn cmd_refresh_count(&mut self) -> DaemonResponse {
        let today_count = self.db.today_count().unwrap_or(0);
        match &mut self.state {
            TimerState::Idle { today_count: tc } => *tc = today_count,
            TimerState::Running { today_count: tc, .. } => *tc = today_count,
            TimerState::Completed { today_count: tc, .. } => *tc = today_count,
            TimerState::Overtime { today_count: tc, .. } => *tc = today_count,
        }
        DaemonResponse::Ok
    }

    fn cmd_reload_database(&mut self) -> DaemonResponse {
        if let Err(e) = self.db.reopen() {
            return DaemonResponse::Error(format!("Failed to reload database: {}", e));
        }
        // Also refresh the count after reloading
        self.cmd_refresh_count()
    }

    /// Called periodically to update timer state
    fn tick(&mut self) {
        // Check if we need to refresh count (new day or system resume)
        self.maybe_refresh_count();

        // Update last tick time for sleep detection
        self.last_tick = Instant::now();

        let Some(start) = self.start_instant else {
            // Check if we should transition from Completed back to Idle
            if let TimerState::Completed { completed_at, .. } = &self.state {
                let elapsed = Utc::now().signed_duration_since(*completed_at);
                if elapsed.num_seconds() >= 3 {
                    let today_count = self.db.today_count().unwrap_or(0);
                    self.state = TimerState::Idle { today_count };
                }
            }
            return;
        };

        let elapsed_secs = start.elapsed().as_secs();
        let today_count = self.state.today_count();

        if elapsed_secs >= self.planned_duration_secs {
            // Timer completed or in overtime
            let overtime_secs = elapsed_secs - self.planned_duration_secs;

            // Check for overtime nudge
            if !self.overtime_nudge_sent
                && self.config.notifications.enabled
                && self.config.notifications.on_overtime_nudge
            {
                if let Ok(threshold) = self.config.overtime_nudge_threshold() {
                    if overtime_secs >= threshold.as_secs() {
                        let total_time = self.planned_duration_secs + overtime_secs;
                        self.notifier.overtime_nudge(total_time);
                        self.overtime_nudge_sent = true;
                    }
                }
            }

            // If just completed (within first tick after completion), auto-complete
            if overtime_secs == 0 {
                // Auto-complete when timer reaches zero
                if let Some(session_id) = self.session_id {
                    if let Err(e) = self.db.complete_session(
                        session_id,
                        elapsed_secs as i64,
                        0,
                    ) {
                        eprintln!("Failed to complete session: {}", e);
                    }

                    let today_count = self.db.today_count().unwrap_or(0);

                    if self.config.notifications.enabled && self.config.notifications.on_complete {
                        self.notifier.session_complete(today_count);
                    }

                    self.state = TimerState::Completed {
                        session_id,
                        today_count,
                        completed_at: Utc::now(),
                    };
                    self.session_id = None;
                    self.start_instant = None;
                    return;
                }
            }

            if let Some(session_id) = self.session_id {
                self.state = TimerState::Overtime {
                    session_id,
                    started_at: Utc::now() - chrono::Duration::seconds(elapsed_secs as i64),
                    planned_duration_secs: self.planned_duration_secs,
                    elapsed_secs,
                    overtime_secs,
                    today_count,
                };
            }
        } else if let Some(session_id) = self.session_id {
            self.state = TimerState::Running {
                session_id,
                started_at: Utc::now() - chrono::Duration::seconds(elapsed_secs as i64),
                planned_duration_secs: self.planned_duration_secs,
                elapsed_secs,
                today_count,
            };
        }
    }
}

/// Send a command to the daemon and get response
pub fn send_command(cmd: DaemonCommand) -> Result<DaemonResponse> {
    let socket_path = socket_path();

    let mut stream = UnixStream::connect(&socket_path)
        .with_context(|| "Daemon not running. Start a timer first.")?;

    stream.set_read_timeout(Some(Duration::from_secs(2)))?;
    stream.set_write_timeout(Some(Duration::from_secs(2)))?;

    let cmd_json = serde_json::to_string(&cmd)?;
    writeln!(stream, "{}", cmd_json)?;
    stream.flush()?;

    let mut reader = BufReader::new(&stream);
    let mut line = String::new();
    reader.read_line(&mut line)?;

    let response: DaemonResponse = serde_json::from_str(&line)?;
    Ok(response)
}

/// Check if daemon is running
pub fn is_daemon_running() -> bool {
    let socket_path = socket_path();
    UnixStream::connect(&socket_path).is_ok()
}

/// Start daemon in background
pub fn spawn_daemon() -> Result<()> {
    use std::process::Command;

    let exe = std::env::current_exe()?;

    Command::new(&exe)
        .arg("daemon")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn()
        .context("Failed to spawn daemon")?;

    // Wait a moment for daemon to start
    thread::sleep(Duration::from_millis(200));

    Ok(())
}

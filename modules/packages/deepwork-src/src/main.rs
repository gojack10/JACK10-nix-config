mod commands;
mod config;
mod daemon;
mod db;
mod notify;
mod timer;
mod tui;

use anyhow::Result;
use clap::{Parser, Subcommand};

use config::Config;
use daemon::Daemon;
use db::Database;
use commands::sync::SyncMode;

#[derive(Parser)]
#[command(name = "deepwork")]
#[command(version, about = "A focused deep work timer with polybar integration", long_about = None)]
#[command(after_help = r#"Examples:
  deepwork status
  deepwork status --watch
  deepwork status --polybar
  deepwork start 90m
  deepwork toggle 1h30m
  deepwork stats
  deepwork config

Watch mode controls:
  Ctrl+D    Toggle timer (start 1h30m / stop)
  Ctrl+C    Quit (with confirmation)

Sync (single-writer workflow):
  deepwork sync user@server            # auto pull/push based on what changed
  deepwork sync user@server --pull      # pull regardless of auto decision (use with --force on conflicts)
  deepwork sync user@server --push      # push regardless of auto decision (use with --force on conflicts)
  deepwork sync user@server -p 9999     # custom SSH port (ssh -p / scp -P)
"#)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    /// Start a new deep work session
    Start {
        /// Duration (e.g., "1h30m", "90m", "2h"). Defaults to config value.
        duration: Option<String>,
    },
    /// Stop the current session (<60min cancels, >=60min completes)
    Stop,
    /// Cancel the current session (doesn't count)
    Cancel,
    /// Toggle timer: start if idle, stop if running
    Toggle {
        /// Duration for new sessions (e.g., "1h30m", "90m", "2h")
        duration: Option<String>,
    },
    /// Show current timer status
    Status {
        /// Format output for polybar (with color codes)
        #[arg(long, conflicts_with = "watch")]
        polybar: bool,
        /// Interactive watch mode (Ctrl+D: toggle, Ctrl+C: quit)
        #[arg(long, conflicts_with = "polybar")]
        watch: bool,
    },
    /// Open the stats dashboard (TUI)
    Stats,
    /// Show config file location
    Config,
    /// Refresh daemon's cached count from database
    Refresh,
    /// Sync database with a remote machine over SSH (single-writer workflow)
    Sync {
        /// Remote SSH host (e.g. user@server)
        remote: String,
        /// SSH port (passed as `ssh -p` and `scp -P`)
        #[arg(short = 'p', long)]
        port: Option<u16>,
        /// Remote database path (default: ~/.local/share/deepwork/deepwork.db)
        #[arg(long)]
        remote_path: Option<String>,
        /// Force pull from remote even if both sides changed since last sync
        #[arg(long, conflicts_with = "push")]
        pull: bool,
        /// Force push local to remote even if both sides changed since last sync
        #[arg(long, conflicts_with = "pull")]
        push: bool,
        /// Required with --pull/--push to override conflict detection
        #[arg(long)]
        force: bool,
        /// Allow syncing while daemon is running (not recommended)
        #[arg(long)]
        allow_running: bool,
    },
    /// Run as daemon (internal use)
    #[command(hide = true)]
    Daemon,
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let config = Config::load()?;

    // Ensure directories exist
    Config::ensure_config_dir()?;
    config::data_dir()?;

    match cli.command {
        Some(Commands::Start { duration }) => {
            commands::start(duration.as_deref(), &config)?;
        }
        Some(Commands::Stop) => {
            commands::stop()?;
        }
        Some(Commands::Cancel) => {
            commands::cancel()?;
        }
        Some(Commands::Toggle { duration }) => {
            commands::toggle(duration.as_deref(), &config)?;
        }
        Some(Commands::Status { polybar, watch }) => {
            commands::status(polybar, watch, &config)?;
        }
        Some(Commands::Stats) => {
            tui::run(&config)?;
        }
        Some(Commands::Config) => {
            let path = Config::config_path()?;
            println!("Config file: {:?}", path);
            if !path.exists() {
                println!("(File does not exist yet - using defaults)");
            }
        }
        Some(Commands::Refresh) => {
            if !daemon::is_daemon_running() {
                anyhow::bail!("Daemon is not running");
            }
            daemon::send_command(timer::DaemonCommand::ReloadDatabase)?;
        }
        Some(Commands::Sync {
            remote,
            port,
            remote_path,
            pull,
            push,
            force,
            allow_running,
        }) => {
            let mode = if pull {
                SyncMode::Pull
            } else if push {
                SyncMode::Push
            } else {
                SyncMode::Auto
            };

            if force && mode == SyncMode::Auto {
                anyhow::bail!("Use --force with either --pull or --push");
            }

            commands::sync::sync(
                &remote,
                port,
                remote_path.as_deref(),
                mode,
                force,
                allow_running,
            )?;
        }
        Some(Commands::Daemon) => {
            let db = Database::open()?;
            let daemon = Daemon::new(config, db);
            daemon.run()?;
        }
        None => {
            // Default: show status
            commands::status(false, false, &config)?;
        }
    }

    Ok(())
}

use anyhow::{Context, Result};
use directories::ProjectDirs;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::time::Duration;

/// Parse duration strings like "1h30m", "90m", "2h"
pub fn parse_duration(s: &str) -> Result<Duration> {
    let s = s.trim().to_lowercase();
    let mut total_secs: u64 = 0;
    let mut current_num = String::new();

    for c in s.chars() {
        if c.is_ascii_digit() {
            current_num.push(c);
        } else {
            let num: u64 = current_num
                .parse()
                .with_context(|| format!("Invalid number in duration: {}", s))?;
            current_num.clear();

            match c {
                'h' => total_secs += num * 3600,
                'm' => total_secs += num * 60,
                's' => total_secs += num,
                _ => anyhow::bail!("Unknown duration unit '{}' in: {}", c, s),
            }
        }
    }

    // Handle bare numbers (assume minutes)
    if !current_num.is_empty() {
        let num: u64 = current_num.parse()?;
        total_secs += num * 60;
    }

    if total_secs == 0 {
        anyhow::bail!("Duration cannot be zero");
    }

    Ok(Duration::from_secs(total_secs))
}

/// Format duration as human-readable string
pub fn format_duration(d: Duration) -> String {
    let total_secs = d.as_secs();
    let hours = total_secs / 3600;
    let mins = (total_secs % 3600) / 60;

    if hours > 0 {
        format!("{}h{}m", hours, mins)
    } else {
        format!("{}m", mins)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimerConfig {
    #[serde(default = "default_duration")]
    pub default_duration: String,
    #[serde(default = "default_overtime_nudge")]
    pub overtime_nudge_after: String,
}

fn default_duration() -> String {
    "1h30m".to_string()
}

fn default_overtime_nudge() -> String {
    "1h".to_string()
}

impl Default for TimerConfig {
    fn default() -> Self {
        Self {
            default_duration: default_duration(),
            overtime_nudge_after: default_overtime_nudge(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DisplayConfig {
    #[serde(default = "default_progress_width")]
    pub progress_width: usize,
    #[serde(default = "default_icon_idle")]
    pub icon_idle: String,
    #[serde(default = "default_icon_running")]
    pub icon_running: String,
    #[serde(default = "default_icon_complete")]
    pub icon_complete: String,
    #[serde(default = "default_icon_overtime")]
    pub icon_overtime: String,
}

fn default_progress_width() -> usize {
    12
}
fn default_icon_idle() -> String {
    "󰔟".to_string()
}
fn default_icon_running() -> String {
    "󰔟".to_string()
}
fn default_icon_complete() -> String {
    "󰄬".to_string()
}
fn default_icon_overtime() -> String {
    "󰈸".to_string()
}

impl Default for DisplayConfig {
    fn default() -> Self {
        Self {
            progress_width: default_progress_width(),
            icon_idle: default_icon_idle(),
            icon_running: default_icon_running(),
            icon_complete: default_icon_complete(),
            icon_overtime: default_icon_overtime(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationConfig {
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default = "default_true")]
    pub on_complete: bool,
    #[serde(default = "default_true")]
    pub on_overtime_nudge: bool,
}

fn default_true() -> bool {
    true
}

impl Default for NotificationConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            on_complete: true,
            on_overtime_nudge: true,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Config {
    #[serde(default)]
    pub timer: TimerConfig,
    #[serde(default)]
    pub display: DisplayConfig,
    #[serde(default)]
    pub notifications: NotificationConfig,
}

impl Config {
    /// Load config from file, or return defaults if file doesn't exist
    pub fn load() -> Result<Self> {
        let path = Self::config_path()?;

        if path.exists() {
            let contents = fs::read_to_string(&path)
                .with_context(|| format!("Failed to read config from {:?}", path))?;
            let config: Config = toml::from_str(&contents)
                .with_context(|| format!("Failed to parse config from {:?}", path))?;
            Ok(config)
        } else {
            Ok(Config::default())
        }
    }

    /// Get the config file path
    pub fn config_path() -> Result<PathBuf> {
        let dirs = project_dirs()?;
        Ok(dirs.config_dir().join("config.toml"))
    }

    /// Get the default duration as Duration
    pub fn default_duration(&self) -> Result<Duration> {
        parse_duration(&self.timer.default_duration)
    }

    /// Get the overtime nudge threshold as Duration
    pub fn overtime_nudge_threshold(&self) -> Result<Duration> {
        parse_duration(&self.timer.overtime_nudge_after)
    }

    /// Ensure config directory exists and optionally create default config
    pub fn ensure_config_dir() -> Result<PathBuf> {
        let dirs = project_dirs()?;
        let config_dir = dirs.config_dir();
        fs::create_dir_all(config_dir)
            .with_context(|| format!("Failed to create config dir: {:?}", config_dir))?;
        Ok(config_dir.to_path_buf())
    }
}

/// Get project directories using XDG conventions
pub fn project_dirs() -> Result<ProjectDirs> {
    ProjectDirs::from("", "", "deepwork")
        .context("Failed to determine project directories")
}

/// Get the data directory path (~/.local/share/deepwork)
pub fn data_dir() -> Result<PathBuf> {
    let dirs = project_dirs()?;
    let data_dir = dirs.data_dir();
    fs::create_dir_all(data_dir)
        .with_context(|| format!("Failed to create data dir: {:?}", data_dir))?;
    Ok(data_dir.to_path_buf())
}

/// Get the runtime directory for socket ($XDG_RUNTIME_DIR or /tmp)
pub fn runtime_dir() -> PathBuf {
    std::env::var("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"))
}

/// Get the socket path
pub fn socket_path() -> PathBuf {
    runtime_dir().join("deepwork.sock")
}

/// Get the database path
pub fn db_path() -> Result<PathBuf> {
    Ok(data_dir()?.join("deepwork.db"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_duration() {
        assert_eq!(parse_duration("1h30m").unwrap(), Duration::from_secs(5400));
        assert_eq!(parse_duration("90m").unwrap(), Duration::from_secs(5400));
        assert_eq!(parse_duration("2h").unwrap(), Duration::from_secs(7200));
        assert_eq!(parse_duration("30").unwrap(), Duration::from_secs(1800));
        assert_eq!(parse_duration("1h").unwrap(), Duration::from_secs(3600));
    }

    #[test]
    fn test_format_duration() {
        assert_eq!(format_duration(Duration::from_secs(5400)), "1h30m");
        assert_eq!(format_duration(Duration::from_secs(1800)), "30m");
        assert_eq!(format_duration(Duration::from_secs(7200)), "2h0m");
    }
}

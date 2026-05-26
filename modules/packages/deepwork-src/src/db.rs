use anyhow::{Context, Result};
use chrono::{DateTime, Datelike, Local, NaiveDate, Utc};
use rusqlite::{params, Connection, OptionalExtension};
use std::path::Path;

use crate::config::db_path;

/// A deep work session record
#[derive(Debug, Clone)]
pub struct Session {
    pub id: i64,
    pub started_at: DateTime<Utc>,
    pub ended_at: Option<DateTime<Utc>>,
    pub planned_duration_secs: i64,
    pub actual_duration_secs: Option<i64>,
    pub completed: bool,
    pub overtime_secs: i64,
}

/// Daily stats for heatmap
#[derive(Debug, Clone)]
pub struct DailyStats {
    pub date: NaiveDate,
    pub sessions: i64,
    pub total_seconds: i64,
}

/// Aggregated stats for display
#[derive(Debug, Clone, Default)]
pub struct AggregatedStats {
    pub today_sessions: i64,
    pub today_seconds: i64,
    pub week_sessions: i64,
    pub week_seconds: i64,
    pub month_sessions: i64,
    pub month_seconds: i64,
    pub year_sessions: i64,
    pub year_seconds: i64,
    pub total_sessions: i64,
    pub total_seconds: i64,
    pub current_streak: i64,
    pub best_streak: i64,
}

pub struct Database {
    conn: Connection,
}

impl Database {
    /// Open or create the database
    pub fn open() -> Result<Self> {
        let path = db_path()?;
        Self::open_at(&path)
    }

    /// Open database at a specific path (useful for testing)
    pub fn open_at(path: &Path) -> Result<Self> {
        let conn = Connection::open(path)
            .with_context(|| format!("Failed to open database at {:?}", path))?;

        let db = Self { conn };
        db.migrate()?;
        Ok(db)
    }

    /// Reopen the database connection (used after sync replaces the file)
    pub fn reopen(&mut self) -> Result<()> {
        let path = db_path()?;
        self.conn = Connection::open(&path)
            .with_context(|| format!("Failed to reopen database at {:?}", path))?;
        self.migrate()?;
        Ok(())
    }

    /// Run database migrations
    fn migrate(&self) -> Result<()> {
        self.conn.execute_batch(
            "
            CREATE TABLE IF NOT EXISTS sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                started_at TEXT NOT NULL,
                ended_at TEXT,
                planned_duration_secs INTEGER NOT NULL,
                actual_duration_secs INTEGER,
                completed INTEGER NOT NULL DEFAULT 0,
                overtime_secs INTEGER DEFAULT 0
            );

            CREATE INDEX IF NOT EXISTS idx_sessions_started ON sessions(started_at);
            CREATE INDEX IF NOT EXISTS idx_sessions_completed ON sessions(completed);
            ",
        )?;
        Ok(())
    }

    /// Start a new session
    pub fn start_session(&self, planned_duration_secs: i64) -> Result<i64> {
        let now = Utc::now().to_rfc3339();
        self.conn.execute(
            "INSERT INTO sessions (started_at, planned_duration_secs, completed) VALUES (?1, ?2, 0)",
            params![now, planned_duration_secs],
        )?;
        Ok(self.conn.last_insert_rowid())
    }

    /// Complete a session (either normally or stopped early)
    pub fn complete_session(
        &self,
        session_id: i64,
        actual_duration_secs: i64,
        overtime_secs: i64,
    ) -> Result<()> {
        let now = Utc::now().to_rfc3339();
        self.conn.execute(
            "UPDATE sessions SET ended_at = ?1, actual_duration_secs = ?2, completed = 1, overtime_secs = ?3 WHERE id = ?4",
            params![now, actual_duration_secs, overtime_secs, session_id],
        )?;
        Ok(())
    }

    /// Cancel a session (doesn't count toward stats)
    pub fn cancel_session(&self, session_id: i64) -> Result<()> {
        self.conn.execute(
            "DELETE FROM sessions WHERE id = ?1 AND completed = 0",
            params![session_id],
        )?;
        Ok(())
    }

    /// Get the current in-progress session if any
    pub fn get_active_session(&self) -> Result<Option<Session>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, started_at, ended_at, planned_duration_secs, actual_duration_secs, completed, overtime_secs
             FROM sessions WHERE completed = 0 ORDER BY id DESC LIMIT 1"
        )?;

        let session = stmt
            .query_row([], |row| {
                Ok(Session {
                    id: row.get(0)?,
                    started_at: parse_datetime(row.get::<_, String>(1)?),
                    ended_at: row.get::<_, Option<String>>(2)?.map(parse_datetime),
                    planned_duration_secs: row.get(3)?,
                    actual_duration_secs: row.get(4)?,
                    completed: row.get(5)?,
                    overtime_secs: row.get(6)?,
                })
            })
            .optional()?;

        Ok(session)
    }

    /// Get count of completed sessions today
    pub fn today_count(&self) -> Result<i64> {
        let today = Local::now().format("%Y-%m-%d").to_string();
        let mut stmt = self.conn.prepare(
            "SELECT COUNT(*) FROM sessions WHERE completed = 1 AND date(started_at, 'localtime') = ?1"
        )?;
        let count: i64 = stmt.query_row([today], |row| row.get(0))?;
        Ok(count)
    }

    /// Get aggregated stats for all time periods
    pub fn get_stats(&self) -> Result<AggregatedStats> {
        let now = Local::now();
        let today = now.format("%Y-%m-%d").to_string();
        let week_start = (now - chrono::Duration::days(now.weekday().num_days_from_monday() as i64))
            .format("%Y-%m-%d")
            .to_string();
        let month_start = now.format("%Y-%m-01").to_string();
        let year_start = now.format("%Y-01-01").to_string();

        let mut stats = AggregatedStats::default();

        // Today
        let mut stmt = self.conn.prepare(
            "SELECT COUNT(*), COALESCE(SUM(actual_duration_secs), 0) FROM sessions
             WHERE completed = 1 AND date(started_at, 'localtime') = ?1"
        )?;
        let (sessions, seconds): (i64, i64) = stmt.query_row([&today], |row| {
            Ok((row.get(0)?, row.get(1)?))
        })?;
        stats.today_sessions = sessions;
        stats.today_seconds = seconds;

        // This week
        let mut stmt = self.conn.prepare(
            "SELECT COUNT(*), COALESCE(SUM(actual_duration_secs), 0) FROM sessions
             WHERE completed = 1 AND date(started_at, 'localtime') >= ?1"
        )?;
        let (sessions, seconds): (i64, i64) = stmt.query_row([&week_start], |row| {
            Ok((row.get(0)?, row.get(1)?))
        })?;
        stats.week_sessions = sessions;
        stats.week_seconds = seconds;

        // This month
        let mut stmt = self.conn.prepare(
            "SELECT COUNT(*), COALESCE(SUM(actual_duration_secs), 0) FROM sessions
             WHERE completed = 1 AND date(started_at, 'localtime') >= ?1"
        )?;
        let (sessions, seconds): (i64, i64) = stmt.query_row([&month_start], |row| {
            Ok((row.get(0)?, row.get(1)?))
        })?;
        stats.month_sessions = sessions;
        stats.month_seconds = seconds;

        // This year
        let mut stmt = self.conn.prepare(
            "SELECT COUNT(*), COALESCE(SUM(actual_duration_secs), 0) FROM sessions
             WHERE completed = 1 AND date(started_at, 'localtime') >= ?1"
        )?;
        let (sessions, seconds): (i64, i64) = stmt.query_row([&year_start], |row| {
            Ok((row.get(0)?, row.get(1)?))
        })?;
        stats.year_sessions = sessions;
        stats.year_seconds = seconds;

        // Total
        let mut stmt = self.conn.prepare(
            "SELECT COUNT(*), COALESCE(SUM(actual_duration_secs), 0) FROM sessions WHERE completed = 1"
        )?;
        let (sessions, seconds): (i64, i64) = stmt.query_row([], |row| {
            Ok((row.get(0)?, row.get(1)?))
        })?;
        stats.total_sessions = sessions;
        stats.total_seconds = seconds;

        // Streaks
        let (current, best) = self.calculate_streaks()?;
        stats.current_streak = current;
        stats.best_streak = best;

        Ok(stats)
    }

    /// Get daily stats for heatmap (last N days or specific month/year)
    pub fn get_daily_stats(&self, year: i32, month: u32) -> Result<Vec<DailyStats>> {
        let start = format!("{:04}-{:02}-01", year, month);
        let end = if month == 12 {
            format!("{:04}-01-01", year + 1)
        } else {
            format!("{:04}-{:02}-01", year, month + 1)
        };

        let mut stmt = self.conn.prepare(
            "SELECT date(started_at, 'localtime') as day, COUNT(*), COALESCE(SUM(actual_duration_secs), 0)
             FROM sessions
             WHERE completed = 1 AND date(started_at, 'localtime') >= ?1 AND date(started_at, 'localtime') < ?2
             GROUP BY day ORDER BY day"
        )?;

        let stats = stmt
            .query_map([&start, &end], |row| {
                let date_str: String = row.get(0)?;
                let date = NaiveDate::parse_from_str(&date_str, "%Y-%m-%d")
                    .unwrap_or_else(|_| NaiveDate::from_ymd_opt(2000, 1, 1).unwrap());
                Ok(DailyStats {
                    date,
                    sessions: row.get(1)?,
                    total_seconds: row.get(2)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;

        Ok(stats)
    }

    /// Get all daily stats for a year (for year view)
    pub fn get_year_stats(&self, year: i32) -> Result<Vec<DailyStats>> {
        let start = format!("{:04}-01-01", year);
        let end = format!("{:04}-01-01", year + 1);

        let mut stmt = self.conn.prepare(
            "SELECT date(started_at, 'localtime') as day, COUNT(*), COALESCE(SUM(actual_duration_secs), 0)
             FROM sessions
             WHERE completed = 1 AND date(started_at, 'localtime') >= ?1 AND date(started_at, 'localtime') < ?2
             GROUP BY day ORDER BY day"
        )?;

        let stats = stmt
            .query_map([&start, &end], |row| {
                let date_str: String = row.get(0)?;
                let date = NaiveDate::parse_from_str(&date_str, "%Y-%m-%d")
                    .unwrap_or_else(|_| NaiveDate::from_ymd_opt(2000, 1, 1).unwrap());
                Ok(DailyStats {
                    date,
                    sessions: row.get(1)?,
                    total_seconds: row.get(2)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;

        Ok(stats)
    }

    /// Calculate current and best streaks
    fn calculate_streaks(&self) -> Result<(i64, i64)> {
        // Get all distinct days with completed sessions, ordered descending
        let mut stmt = self.conn.prepare(
            "SELECT DISTINCT date(started_at, 'localtime') as day FROM sessions
             WHERE completed = 1 ORDER BY day DESC"
        )?;

        let dates: Vec<NaiveDate> = stmt
            .query_map([], |row| {
                let date_str: String = row.get(0)?;
                Ok(NaiveDate::parse_from_str(&date_str, "%Y-%m-%d")
                    .unwrap_or_else(|_| NaiveDate::from_ymd_opt(2000, 1, 1).unwrap()))
            })?
            .collect::<Result<Vec<_>, _>>()?;

        if dates.is_empty() {
            return Ok((0, 0));
        }

        let today = Local::now().date_naive();
        let yesterday = today - chrono::Duration::days(1);

        // Current streak (must include today or yesterday)
        let mut current_streak = 0i64;
        if !dates.is_empty() {
            let most_recent = dates[0];
            if most_recent == today || most_recent == yesterday {
                current_streak = 1;
                for i in 1..dates.len() {
                    let expected = dates[i - 1] - chrono::Duration::days(1);
                    if dates[i] == expected {
                        current_streak += 1;
                    } else {
                        break;
                    }
                }
            }
        }

        // Best streak (find longest consecutive run)
        let mut best_streak = 0i64;
        let mut streak = 1i64;
        for i in 1..dates.len() {
            let expected = dates[i - 1] - chrono::Duration::days(1);
            if dates[i] == expected {
                streak += 1;
            } else {
                best_streak = best_streak.max(streak);
                streak = 1;
            }
        }
        best_streak = best_streak.max(streak);
        best_streak = best_streak.max(current_streak);

        Ok((current_streak, best_streak))
    }
}

/// Parse RFC3339 datetime string to DateTime<Utc>
fn parse_datetime(s: String) -> DateTime<Utc> {
    DateTime::parse_from_rfc3339(&s)
        .map(|dt| dt.with_timezone(&Utc))
        .unwrap_or_else(|_| Utc::now())
}

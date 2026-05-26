use anyhow::Result;
use chrono::{Datelike, Local};
use crossterm::{
    event::{self, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::io;
use std::time::Duration;

use crate::config::Config;
use crate::db::{AggregatedStats, Database, DailyStats};

use super::ui;

pub struct App {
    pub config: Config,
    pub db: Database,
    pub stats: AggregatedStats,
    pub daily_stats: Vec<DailyStats>,
    pub current_year: i32,
    pub current_month: u32,
    pub year_view: bool,
    pub should_quit: bool,
}

impl App {
    pub fn new(config: &Config) -> Result<Self> {
        let db = Database::open()?;
        let stats = db.get_stats()?;
        let now = Local::now();
        let current_year = now.year();
        let current_month = now.month();
        let daily_stats = db.get_daily_stats(current_year, current_month)?;

        Ok(Self {
            config: config.clone(),
            db,
            stats,
            daily_stats,
            current_year,
            current_month,
            year_view: false,
            should_quit: false,
        })
    }

    pub fn run(&mut self) -> Result<()> {
        // Setup terminal
        enable_raw_mode()?;
        let mut stdout = io::stdout();
        execute!(stdout, EnterAlternateScreen)?;
        let backend = CrosstermBackend::new(stdout);
        let mut terminal = Terminal::new(backend)?;

        // Main loop
        while !self.should_quit {
            terminal.draw(|f| ui::render(f, self))?;

            // Poll for events with timeout for auto-refresh
            if event::poll(Duration::from_secs(1))? {
                if let Event::Key(key) = event::read()? {
                    if key.kind == KeyEventKind::Press {
                        self.handle_key(key.code)?;
                    }
                }
            } else {
                // Refresh stats periodically
                self.refresh_stats()?;
            }
        }

        // Restore terminal
        disable_raw_mode()?;
        execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
        Ok(())
    }

    fn handle_key(&mut self, key: KeyCode) -> Result<()> {
        match key {
            KeyCode::Char('q') | KeyCode::Esc => {
                self.should_quit = true;
            }
            KeyCode::Char('y') => {
                self.year_view = !self.year_view;
                if self.year_view {
                    self.daily_stats = self.db.get_year_stats(self.current_year)?;
                } else {
                    self.daily_stats = self.db.get_daily_stats(self.current_year, self.current_month)?;
                }
            }
            KeyCode::Char('h') | KeyCode::Left => {
                if !self.year_view {
                    // Previous month
                    if self.current_month == 1 {
                        self.current_month = 12;
                        self.current_year -= 1;
                    } else {
                        self.current_month -= 1;
                    }
                    self.daily_stats = self.db.get_daily_stats(self.current_year, self.current_month)?;
                } else {
                    // Previous year
                    self.current_year -= 1;
                    self.daily_stats = self.db.get_year_stats(self.current_year)?;
                }
            }
            KeyCode::Char('l') | KeyCode::Right => {
                if !self.year_view {
                    // Next month
                    if self.current_month == 12 {
                        self.current_month = 1;
                        self.current_year += 1;
                    } else {
                        self.current_month += 1;
                    }
                    self.daily_stats = self.db.get_daily_stats(self.current_year, self.current_month)?;
                } else {
                    // Next year
                    self.current_year += 1;
                    self.daily_stats = self.db.get_year_stats(self.current_year)?;
                }
            }
            _ => {}
        }
        Ok(())
    }

    fn refresh_stats(&mut self) -> Result<()> {
        self.stats = self.db.get_stats()?;
        Ok(())
    }
}

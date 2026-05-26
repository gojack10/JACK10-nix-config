mod app;
mod heatmap;
mod ui;

use anyhow::Result;

use crate::config::Config;

pub use app::App;

/// Run the TUI stats dashboard
pub fn run(config: &Config) -> Result<()> {
    let mut app = App::new(config)?;
    app.run()
}

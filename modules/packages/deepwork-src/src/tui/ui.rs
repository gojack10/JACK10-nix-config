use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    widgets::{Block, Borders, Paragraph, Row, Table},
    Frame,
};

use super::app::App;
use super::heatmap;

fn centered_rect(max_width: u16, area: Rect) -> Rect {
    if area.width <= max_width {
        return area;
    }
    let padding = (area.width - max_width) / 2;
    Rect {
        x: area.x + padding,
        y: area.y,
        width: max_width,
        height: area.height,
    }
}

pub fn render(f: &mut Frame, app: &App) {
    let centered = centered_rect(80, f.area());
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),  // Header
            Constraint::Length(5),  // Stats summary
            Constraint::Min(10),    // Heatmap
            Constraint::Length(3),  // Footer
        ])
        .split(centered);

    render_header(f, chunks[0]);
    render_stats_summary(f, chunks[1], app);

    if app.year_view {
        render_year_view(f, chunks[2], app);
    } else {
        render_calendar(f, chunks[2], app);
    }

    render_footer(f, chunks[3], app);
}

fn render_header(f: &mut Frame, area: Rect) {
    let header = Paragraph::new("󰔟  DEEP WORK")
        .style(Style::default().fg(Color::Rgb(208, 208, 208)).add_modifier(Modifier::BOLD))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::ALL).border_style(Style::default().fg(Color::Rgb(111, 111, 111))));
    f.render_widget(header, area);
}

fn render_stats_summary(f: &mut Frame, area: Rect, app: &App) {
    let stats = &app.stats;

    // Format time helpers
    let fmt_time = |secs: i64| {
        let hours = secs / 3600;
        let mins = (secs % 3600) / 60;
        if hours > 0 {
            format!("{}h {:02}m", hours, mins)
        } else {
            format!("{}m", mins)
        }
    };

    let header = Row::new(vec!["TODAY", "WEEK", "MONTH", "YEAR", "TOTAL"])
        .style(Style::default().fg(Color::Rgb(138, 138, 138)));

    let sessions = Row::new(vec![
        stats.today_sessions.to_string(),
        stats.week_sessions.to_string(),
        stats.month_sessions.to_string(),
        stats.year_sessions.to_string(),
        stats.total_sessions.to_string(),
    ])
    .style(Style::default().fg(Color::Rgb(208, 208, 208)).add_modifier(Modifier::BOLD));

    let times = Row::new(vec![
        fmt_time(stats.today_seconds),
        fmt_time(stats.week_seconds),
        fmt_time(stats.month_seconds),
        fmt_time(stats.year_seconds),
        String::new(),
    ])
    .style(Style::default().fg(Color::Rgb(138, 138, 138)));

    let widths = [
        Constraint::Percentage(20),
        Constraint::Percentage(20),
        Constraint::Percentage(20),
        Constraint::Percentage(20),
        Constraint::Percentage(20),
    ];

    let table = Table::new(vec![header, sessions, times], widths)
        .block(Block::default().borders(Borders::ALL).border_style(Style::default().fg(Color::Rgb(111, 111, 111))));

    f.render_widget(table, area);
}

fn render_calendar(f: &mut Frame, area: Rect, app: &App) {
    let month_name = match app.current_month {
        1 => "JANUARY",
        2 => "FEBRUARY",
        3 => "MARCH",
        4 => "APRIL",
        5 => "MAY",
        6 => "JUNE",
        7 => "JULY",
        8 => "AUGUST",
        9 => "SEPTEMBER",
        10 => "OCTOBER",
        11 => "NOVEMBER",
        12 => "DECEMBER",
        _ => "UNKNOWN",
    };

    let title = format!("{} {}", month_name, app.current_year);

    let inner = Block::default()
        .title(title)
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Rgb(111, 111, 111)));

    let inner_area = inner.inner(area);
    f.render_widget(inner, area);

    // Render the calendar grid
    let calendar_text = heatmap::render_month_calendar(
        app.current_year,
        app.current_month,
        &app.daily_stats,
    );

    let calendar = Paragraph::new(calendar_text)
        .style(Style::default().fg(Color::Rgb(208, 208, 208)));

    f.render_widget(calendar, inner_area);
}

fn render_year_view(f: &mut Frame, area: Rect, app: &App) {
    let title = format!("{} OVERVIEW", app.current_year);

    let inner = Block::default()
        .title(title)
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Rgb(111, 111, 111)));

    let inner_area = inner.inner(area);
    f.render_widget(inner, area);

    let year_text = heatmap::render_year_linear(app.current_year, &app.daily_stats);

    let year_view = Paragraph::new(year_text)
        .style(Style::default().fg(Color::Rgb(208, 208, 208)));

    f.render_widget(year_view, inner_area);
}

fn render_footer(f: &mut Frame, area: Rect, app: &App) {
    let streak_info = format!(
        "Streak: {} days (best: {})  │  ",
        app.stats.current_streak, app.stats.best_streak
    );

    let view_mode = if app.year_view { "month" } else { "year" };

    let footer_text = format!(
        "{}[q] quit  [h/l] prev/next  [y] {} view",
        streak_info, view_mode
    );

    let footer = Paragraph::new(footer_text)
        .style(Style::default().fg(Color::Rgb(138, 138, 138)))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::ALL).border_style(Style::default().fg(Color::Rgb(111, 111, 111))));

    f.render_widget(footer, area);
}

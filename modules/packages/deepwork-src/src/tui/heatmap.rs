use chrono::{Datelike, NaiveDate, Weekday};
use ratatui::{
    style::{Color, Style},
    text::{Line, Span},
};
use std::collections::HashMap;

use crate::db::DailyStats;

/// Get heatmap color based on hours worked
fn get_heatmap_color(hours: f64) -> Color {
    if hours == 0.0 {
        Color::Rgb(48, 54, 61)    // Visible gray - no work
    } else if hours < 2.0 {
        Color::Rgb(14, 68, 41)    // Light green
    } else if hours < 4.0 {
        Color::Rgb(0, 109, 50)    // Medium green
    } else {
        Color::Rgb(38, 166, 65)   // Bright green
    }
}

/// Render a month calendar with heatmap colors
pub fn render_month_calendar(year: i32, month: u32, daily_stats: &[DailyStats]) -> Vec<Line<'static>> {
    // Build a map of date -> hours
    let stats_map: HashMap<NaiveDate, f64> = daily_stats
        .iter()
        .map(|s| (s.date, s.total_seconds as f64 / 3600.0))
        .collect();

    let mut lines = Vec::new();

    // Header row
    lines.push(Line::from(vec![
        Span::styled("  M   T   W   T   F   S   S", Style::default().fg(Color::Rgb(138, 138, 138))),
    ]));

    // Get first day of month
    let first_day = NaiveDate::from_ymd_opt(year, month, 1).unwrap();
    let days_in_month = if month == 12 {
        NaiveDate::from_ymd_opt(year + 1, 1, 1)
    } else {
        NaiveDate::from_ymd_opt(year, month + 1, 1)
    }
    .unwrap()
    .signed_duration_since(first_day)
    .num_days() as u32;

    // Calculate starting position (0 = Monday, 6 = Sunday)
    let start_weekday = first_day.weekday().num_days_from_monday() as usize;

    let mut current_day = 1u32;
    let mut week_spans: Vec<Span> = Vec::new();

    // Add empty cells for days before the 1st
    for _ in 0..start_weekday {
        week_spans.push(Span::raw("    "));
    }

    while current_day <= days_in_month {
        let date = NaiveDate::from_ymd_opt(year, month, current_day).unwrap();
        let hours = stats_map.get(&date).copied().unwrap_or(0.0);

        // Background colors with contrasting text
        let (bg_color, fg_color) = if hours == 0.0 {
            (Color::Rgb(33, 38, 45), Color::Rgb(139, 148, 158))  // subtle gray bg, readable text
        } else if hours < 2.0 {
            (Color::Rgb(14, 68, 41), Color::Rgb(208, 208, 208))  // green bg, light text
        } else if hours < 4.0 {
            (Color::Rgb(0, 109, 50), Color::Rgb(255, 255, 255))  // medium green, white text
        } else {
            (Color::Rgb(38, 166, 65), Color::Rgb(255, 255, 255)) // bright green, white text
        };

        let cell = format!(" {:2} ", current_day);

        week_spans.push(Span::styled(cell, Style::default().fg(fg_color).bg(bg_color)));

        // Check if end of week (Sunday)
        let weekday = date.weekday();
        if weekday == Weekday::Sun || current_day == days_in_month {
            // Pad remaining days if last week
            if weekday != Weekday::Sun {
                let remaining = 6 - weekday.num_days_from_monday() as usize;
                for _ in 0..remaining {
                    week_spans.push(Span::raw("    "));
                }
            }
            lines.push(Line::from(week_spans.clone()));
            week_spans.clear();
        }

        current_day += 1;
    }

    // Legend
    lines.push(Line::from(""));
    lines.push(Line::from(vec![
        Span::styled("  ", Style::default()),
        Span::styled("  ", Style::default().bg(Color::Rgb(33, 38, 45))),
        Span::styled(" 0h  ", Style::default().fg(Color::Rgb(138, 138, 138))),
        Span::styled("  ", Style::default().bg(Color::Rgb(14, 68, 41))),
        Span::styled(" 0-2h  ", Style::default().fg(Color::Rgb(138, 138, 138))),
        Span::styled("  ", Style::default().bg(Color::Rgb(0, 109, 50))),
        Span::styled(" 2-4h  ", Style::default().fg(Color::Rgb(138, 138, 138))),
        Span::styled("  ", Style::default().bg(Color::Rgb(38, 166, 65))),
        Span::styled(" 4h+", Style::default().fg(Color::Rgb(138, 138, 138))),
    ]));

    lines
}

/// Render year view with linear month rows
pub fn render_year_linear(year: i32, daily_stats: &[DailyStats]) -> Vec<Line<'static>> {
    let stats_map: HashMap<NaiveDate, f64> = daily_stats
        .iter()
        .map(|s| (s.date, s.total_seconds as f64 / 3600.0))
        .collect();

    let months = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ];

    let mut lines = Vec::new();

    for (month_idx, month_name) in months.iter().enumerate() {
        let month = (month_idx + 1) as u32;

        let first_day = NaiveDate::from_ymd_opt(year, month, 1).unwrap();
        let days_in_month = if month == 12 {
            NaiveDate::from_ymd_opt(year + 1, 1, 1)
        } else {
            NaiveDate::from_ymd_opt(year, month + 1, 1)
        }
        .unwrap()
        .signed_duration_since(first_day)
        .num_days() as u32;

        let mut spans = vec![
            Span::styled(format!("{} ", month_name), Style::default().fg(Color::Rgb(138, 138, 138))),
        ];

        for day in 1..=days_in_month {
            let date = NaiveDate::from_ymd_opt(year, month, day).unwrap();
            let hours = stats_map.get(&date).copied().unwrap_or(0.0);
            let color = get_heatmap_color(hours);

            let char = if hours == 0.0 {
                "░"
            } else if hours < 2.0 {
                "▒"
            } else if hours < 4.0 {
                "▓"
            } else {
                "█"
            };

            spans.push(Span::styled(char, Style::default().fg(color)));
        }

        lines.push(Line::from(spans));
    }

    lines
}

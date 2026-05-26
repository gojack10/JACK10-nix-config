use notify_rust::Notification;

pub struct Notifier;

impl Notifier {
    pub fn new() -> Self {
        Self
    }

    /// Send notification when session completes
    pub fn session_complete(&self, today_count: i64) {
        let _ = Notification::new()
            .summary("󰄬 Deep work complete!")
            .body(&format!("Session #{} today", today_count))
            .icon("dialog-information")
            .timeout(5000)
            .show();
    }

    /// Send notification for overtime nudge
    pub fn overtime_nudge(&self, total_secs: u64) {
        let hours = total_secs / 3600;
        let mins = (total_secs % 3600) / 60;

        let time_str = if hours > 0 {
            format!("{}h {}m", hours, mins)
        } else {
            format!("{}m", mins)
        };

        let _ = Notification::new()
            .summary("󰔟 Time for a break?")
            .body(&format!("{} deep work - consider taking a break", time_str))
            .icon("dialog-information")
            .timeout(10000)
            .show();
    }
}

impl Default for Notifier {
    fn default() -> Self {
        Self::new()
    }
}

#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

mod codex;

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::Duration;

use chrono::{DateTime, Local};
use slint::{ComponentHandle, Timer, TimerMode};

use crate::codex::{CodexSnapshot, UsageWindow};

slint::include_modules!();

const REFRESH_INTERVAL: Duration = Duration::from_secs(5 * 60);
const DASHBOARD_URL: &str = "https://chatgpt.com/codex/settings/usage";

fn main() -> Result<(), slint::PlatformError> {
    let window = MainWindow::new()?;
    let tray = AppTray::new()?;
    let about = AboutWindow::new()?;

    tray.set_icon_level(0);
    tray.set_tray_title("Codex".into());
    tray.set_tray_tooltip("CodexBar is loading usage…".into());
    tray.set_provider_line("Codex · loading…".into());
    tray.set_status_line("Fetching usage".into());
    window.set_status_text("Fetching current Codex usage…".into());
    window.set_loading(true);

    let refreshing = Arc::new(AtomicBool::new(false));

    {
        let window_weak = window.as_weak();
        tray.on_toggle_window(move || {
            let Some(window) = window_weak.upgrade() else {
                return;
            };
            if window.window().is_visible() {
                let _ = window.hide();
            } else {
                let _ = window.show();
            }
        });
    }

    {
        let window_weak = window.as_weak();
        window.on_hide_window(move || {
            if let Some(window) = window_weak.upgrade() {
                let _ = window.hide();
            }
        });
    }

    {
        let window_weak = window.as_weak();
        let tray_weak = tray.as_weak();
        let refreshing = refreshing.clone();
        window.on_refresh(move || {
            refresh(window_weak.clone(), tray_weak.clone(), refreshing.clone());
        });
    }

    {
        let window_weak = window.as_weak();
        let tray_weak = tray.as_weak();
        let refreshing = refreshing.clone();
        tray.on_refresh(move || {
            refresh(window_weak.clone(), tray_weak.clone(), refreshing.clone());
        });
    }

    window.on_open_dashboard(open_dashboard);
    tray.on_open_dashboard(open_dashboard);

    {
        let about_weak = about.as_weak();
        window.on_show_about(move || {
            if let Some(about) = about_weak.upgrade() {
                let _ = about.show();
            }
        });
    }

    {
        let about_weak = about.as_weak();
        tray.on_show_about(move || {
            if let Some(about) = about_weak.upgrade() {
                let _ = about.show();
            }
        });
    }

    {
        let about_weak = about.as_weak();
        about.on_close_about(move || {
            if let Some(about) = about_weak.upgrade() {
                let _ = about.hide();
            }
        });
    }

    window.on_quit(quit);
    tray.on_quit(quit);
    about.on_quit(quit);

    let refresh_timer = Timer::default();
    {
        let window_weak = window.as_weak();
        let tray_weak = tray.as_weak();
        let refreshing = refreshing.clone();
        refresh_timer.start(TimerMode::Repeated, REFRESH_INTERVAL, move || {
            refresh(window_weak.clone(), tray_weak.clone(), refreshing.clone());
        });
    }

    refresh(window.as_weak(), tray.as_weak(), refreshing);

    let show_on_start = std::env::args().any(|argument| argument == "--show")
        || std::env::var_os("CODEXBAR_SHOW_ON_START").is_some_and(|value| value == "1");
    if show_on_start {
        window.show()?;
    }

    slint::run_event_loop()
}

fn refresh(
    window: slint::Weak<MainWindow>,
    tray: slint::Weak<AppTray>,
    refreshing: Arc<AtomicBool>,
) {
    if refreshing.swap(true, Ordering::AcqRel) {
        return;
    }

    let _ = window.clone().upgrade_in_event_loop(|window| {
        window.set_loading(true);
        window.set_status_text("Refreshing…".into());
    });
    let _ = tray.clone().upgrade_in_event_loop(|tray| {
        tray.set_refreshing(true);
        tray.set_status_line("Refreshing…".into());
    });

    let worker_window = window.clone();
    let worker_tray = tray.clone();
    let worker_refreshing = refreshing.clone();
    let thread_result = thread::Builder::new()
        .name("codexbar-refresh".into())
        .spawn(move || {
            let result = codex::fetch_snapshot();
            worker_refreshing.store(false, Ordering::Release);

            match result {
                Ok(snapshot) => {
                    let window_snapshot = snapshot.clone();
                    let _ = worker_window.upgrade_in_event_loop(move |window| {
                        apply_window_snapshot(&window, &window_snapshot);
                    });
                    let _ = worker_tray.upgrade_in_event_loop(move |tray| {
                        apply_tray_snapshot(&tray, &snapshot);
                    });
                }
                Err(error) => {
                    let message = error.to_string();
                    let window_message = message.clone();
                    let _ = worker_window.upgrade_in_event_loop(move |window| {
                        window.set_loading(false);
                        window
                            .set_status_text(format!("Could not refresh: {window_message}").into());
                    });
                    let _ = worker_tray.upgrade_in_event_loop(move |tray| {
                        tray.set_refreshing(false);
                        tray.set_status_line(format!("Error: {message}").into());
                        tray.set_tray_tooltip(format!("CodexBar: {message}").into());
                        tray.set_icon_level(4);
                    });
                }
            }
        });

    if thread_result.is_err() {
        refreshing.store(false, Ordering::Release);
        // A thread creation failure is exceptional, but leave the app usable.
        // The next timer tick or manual refresh can retry.
        let _ = window.upgrade_in_event_loop(|window| {
            window.set_loading(false);
            window.set_status_text("Could not start the refresh worker.".into());
        });
        let _ = tray.upgrade_in_event_loop(|tray| {
            tray.set_refreshing(false);
            tray.set_status_line("Refresh worker unavailable".into());
        });
    }
}

fn apply_window_snapshot(window: &MainWindow, snapshot: &CodexSnapshot) {
    window.set_loading(false);
    window.set_account_text(
        snapshot
            .account_email
            .as_deref()
            .unwrap_or("Signed in")
            .into(),
    );
    window.set_plan_text(
        snapshot
            .plan
            .as_deref()
            .map(format_plan)
            .unwrap_or_else(|| "Codex".into())
            .into(),
    );
    window
        .set_status_text(format!("Updated {} · OAuth", snapshot.fetched_at.format("%H:%M")).into());
    apply_window(window, snapshot.session.as_ref(), true);
    apply_window(window, snapshot.weekly.as_ref(), false);

    let credits = snapshot
        .credits
        .map(|value| format!("{value:.2} credits remaining"))
        .unwrap_or_default();
    window.set_credits_visible(snapshot.credits.is_some());
    window.set_credits_text(credits.into());
}

fn apply_window(window: &MainWindow, usage: Option<&UsageWindow>, session: bool) {
    let visible = usage.is_some();
    let (used, remaining, reset) = usage.map_or((0.0, String::new(), String::new()), |usage| {
        (
            usage.used_percent as f32,
            format!("{:.0}% left", usage.remaining_percent()),
            format!("Resets {}", format_reset(usage.reset_at)),
        )
    });

    if session {
        window.set_session_visible(visible);
        window.set_session_used(used);
        window.set_session_remaining(remaining.into());
        window.set_session_reset(reset.into());
    } else {
        window.set_weekly_visible(visible);
        window.set_weekly_used(used);
        window.set_weekly_remaining(remaining.into());
        window.set_weekly_reset(reset.into());
    }
}

fn apply_tray_snapshot(tray: &AppTray, snapshot: &CodexSnapshot) {
    let constrained = snapshot.most_constrained_window();
    let remaining = constrained.map_or(100.0, UsageWindow::remaining_percent);
    let plan = snapshot
        .plan
        .as_deref()
        .map(format_plan)
        .unwrap_or_else(|| "Codex".into());

    tray.set_refreshing(false);
    tray.set_provider_line(format!("Codex · {plan}").into());
    tray.set_session_visible(snapshot.session.is_some());
    tray.set_weekly_visible(snapshot.weekly.is_some());
    tray.set_session_line(menu_window_line("Session", snapshot.session.as_ref()).into());
    tray.set_weekly_line(menu_window_line("Weekly", snapshot.weekly.as_ref()).into());
    tray.set_status_line(format!("Updated {}", snapshot.fetched_at.format("%H:%M")).into());
    tray.set_tray_title(format!("{remaining:.0}%").into());

    let tooltip = constrained.map_or_else(
        || "CodexBar: usage unavailable".into(),
        |window| {
            format!(
                "Codex: {:.0}% left · resets {}",
                window.remaining_percent(),
                format_reset(window.reset_at)
            )
        },
    );
    tray.set_tray_tooltip(tooltip.into());
    tray.set_icon_level(if remaining <= 20.0 {
        3
    } else if remaining <= 50.0 {
        2
    } else {
        1
    });
}

fn menu_window_line(label: &str, usage: Option<&UsageWindow>) -> String {
    usage.map_or_else(
        || format!("{label}: unavailable"),
        |usage| {
            format!(
                "{label}: {:.0}% left · {}",
                usage.remaining_percent(),
                format_reset(usage.reset_at)
            )
        },
    )
}

fn format_reset(reset_at: DateTime<Local>) -> String {
    let today = Local::now().date_naive();
    let reset_date = reset_at.date_naive();
    if reset_date == today {
        format!("today at {}", reset_at.format("%H:%M"))
    } else if reset_date == today.succ_opt().unwrap_or(today) {
        format!("tomorrow at {}", reset_at.format("%H:%M"))
    } else {
        reset_at.format("%a %d %b at %H:%M").to_string()
    }
}

fn format_plan(value: &str) -> String {
    value
        .split(['_', '-'])
        .filter(|part| !part.is_empty())
        .map(|part| {
            let mut characters = part.chars();
            match characters.next() {
                Some(first) => first.to_uppercase().collect::<String>() + characters.as_str(),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn open_dashboard() {
    let _ = webbrowser::open(DASHBOARD_URL);
}

fn quit() {
    let _ = slint::quit_event_loop();
}

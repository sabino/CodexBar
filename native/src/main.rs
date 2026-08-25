#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

mod codex;
mod engine;
mod icons;

use std::collections::{BTreeMap, HashMap, HashSet};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use chrono::{DateTime, Local, NaiveDate};
use slint::{CloseRequestResponse, Color, ComponentHandle, ModelRc, Timer, TimerMode, VecModel};

use crate::codex::{CodexSnapshot, UsageWindow as CodexUsageWindow};
use crate::engine::{
    DashboardProvider, DashboardWindow, Engine, NativeSnapshot, PaceLane, ProviderCatalogEntry,
};

slint::include_modules!();

const REFRESH_INTERVAL: Duration = Duration::from_secs(5 * 60);

#[derive(Clone)]
enum SnapshotData {
    Engine(NativeSnapshot),
    DirectCodex(CodexSnapshot),
}

#[derive(Clone)]
struct AppState {
    snapshot: Option<SnapshotData>,
    selected_provider_id: String,
    history_days: u32,
    message: String,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            snapshot: None,
            selected_provider_id: "codex".to_owned(),
            history_days: 30,
            message: String::new(),
        }
    }
}

fn main() -> Result<(), slint::PlatformError> {
    let window = MainWindow::new()?;
    let settings = SettingsWindow::new()?;
    let tray = AppTray::new()?;
    let about = AboutWindow::new()?;

    window.set_loading(true);
    window.set_updated_text("Loading provider usage…".into());
    settings.set_loading(true);
    tray.set_icon_level(0);
    tray.set_tray_title("…".into());
    tray.set_tray_tooltip("CodexBar is loading provider usage…".into());
    tray.set_provider_line("CodexBar · loading…".into());
    tray.set_status_line("Fetching enabled providers".into());

    let state = Arc::new(Mutex::new(AppState::default()));
    let refreshing = Arc::new(AtomicBool::new(false));

    wire_visibility(&window, &settings, &tray, &about);
    wire_selection(&window, &settings, &tray, state.clone());
    wire_history(&window, &settings, &tray, state.clone());
    wire_provider_toggle(&window, &settings, &tray, state.clone(), refreshing.clone());
    wire_refresh(&window, &settings, &tray, state.clone(), refreshing.clone());
    wire_links(&window, &settings, &tray, state.clone());

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
        let settings_weak = settings.as_weak();
        let tray_weak = tray.as_weak();
        let state = state.clone();
        let refreshing = refreshing.clone();
        refresh_timer.start(TimerMode::Repeated, REFRESH_INTERVAL, move || {
            refresh(
                window_weak.clone(),
                settings_weak.clone(),
                tray_weak.clone(),
                state.clone(),
                refreshing.clone(),
            );
        });
    }

    refresh(
        window.as_weak(),
        settings.as_weak(),
        tray.as_weak(),
        state,
        refreshing,
    );

    let show_on_start = std::env::args().any(|argument| argument == "--show")
        || std::env::var_os("CODEXBAR_SHOW_ON_START").is_some_and(|value| value == "1");
    if show_on_start {
        window.show()?;
    }

    slint::run_event_loop()
}

fn wire_visibility(
    window: &MainWindow,
    settings: &SettingsWindow,
    tray: &AppTray,
    about: &AboutWindow,
) {
    {
        let window_weak = window.as_weak();
        window.window().on_close_requested(move || {
            if let Some(window) = window_weak.upgrade() {
                let _ = window.hide();
            }
            CloseRequestResponse::KeepWindowShown
        });
    }
    {
        let settings_weak = settings.as_weak();
        settings.window().on_close_requested(move || {
            if let Some(settings) = settings_weak.upgrade() {
                let _ = settings.hide();
            }
            CloseRequestResponse::KeepWindowShown
        });
    }
    {
        let about_weak = about.as_weak();
        about.window().on_close_requested(move || {
            if let Some(about) = about_weak.upgrade() {
                let _ = about.hide();
            }
            CloseRequestResponse::KeepWindowShown
        });
    }
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
        let settings_weak = settings.as_weak();
        window.on_show_settings(move || {
            if let Some(settings) = settings_weak.upgrade() {
                let _ = settings.show();
            }
        });
    }
    {
        let settings_weak = settings.as_weak();
        tray.on_show_settings(move || {
            if let Some(settings) = settings_weak.upgrade() {
                let _ = settings.show();
            }
        });
    }
    {
        let settings_weak = settings.as_weak();
        settings.on_close_settings(move || {
            if let Some(settings) = settings_weak.upgrade() {
                let _ = settings.hide();
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
}

fn wire_selection(
    window: &MainWindow,
    settings: &SettingsWindow,
    tray: &AppTray,
    state: Arc<Mutex<AppState>>,
) {
    {
        let window_weak = window.as_weak();
        let settings_weak = settings.as_weak();
        let tray_weak = tray.as_weak();
        let state = state.clone();
        window.on_select_provider(move |index| {
            let ids = enabled_provider_ids(&state_snapshot(&state));
            let Some(provider_id) = ids.get(index.max(0) as usize) else {
                return;
            };
            update_selected_provider(&state, provider_id);
            apply_if_available(&window_weak, &settings_weak, &tray_weak, &state);
        });
    }
    {
        let window_weak = window.as_weak();
        let settings_weak = settings.as_weak();
        let tray_weak = tray.as_weak();
        let state = state.clone();
        settings.on_select_provider(move |index| {
            let ids = all_provider_ids(&state_snapshot(&state));
            let Some(provider_id) = ids.get(index.max(0) as usize) else {
                return;
            };
            update_selected_provider(&state, provider_id);
            if let Some(settings) = settings_weak.upgrade() {
                settings.set_navigation_index(7);
            }
            apply_if_available(&window_weak, &settings_weak, &tray_weak, &state);
        });
    }
    {
        let settings_weak = settings.as_weak();
        settings.on_navigate(move |index| {
            if let Some(settings) = settings_weak.upgrade() {
                settings.set_navigation_index(index.clamp(0, 7));
            }
        });
    }
}

fn wire_history(
    window: &MainWindow,
    settings: &SettingsWindow,
    tray: &AppTray,
    state: Arc<Mutex<AppState>>,
) {
    {
        let settings_weak = settings.as_weak();
        window.on_show_history(move || {
            if let Some(settings) = settings_weak.upgrade() {
                settings.set_navigation_index(1);
                let _ = settings.show();
            }
        });
    }
    {
        let window_weak = window.as_weak();
        let settings_weak = settings.as_weak();
        let tray_weak = tray.as_weak();
        settings.on_set_history_days(move |days| {
            let days = if days == 7 { 7 } else { 30 };
            {
                let mut state = lock_state(&state);
                state.history_days = days;
            }
            apply_if_available(&window_weak, &settings_weak, &tray_weak, &state);
        });
    }
}

fn wire_provider_toggle(
    window: &MainWindow,
    settings: &SettingsWindow,
    tray: &AppTray,
    state: Arc<Mutex<AppState>>,
    refreshing: Arc<AtomicBool>,
) {
    let window_weak = window.as_weak();
    let settings_weak = settings.as_weak();
    let tray_weak = tray.as_weak();
    settings.on_toggle_provider(move |index, enabled| {
        if refreshing.swap(true, Ordering::AcqRel) {
            return;
        }
        let ids = all_provider_ids(&state_snapshot(&state));
        let Some(provider_id) = ids.get(index.max(0) as usize).cloned() else {
            refreshing.store(false, Ordering::Release);
            return;
        };

        if let Some(settings) = settings_weak.upgrade() {
            settings.set_loading(true);
        }
        let worker_window = window_weak.clone();
        let worker_settings = settings_weak.clone();
        let worker_tray = tray_weak.clone();
        let worker_state = state.clone();
        let worker_refreshing = refreshing.clone();
        let _ = thread::Builder::new()
            .name("codexbar-provider-toggle".into())
            .spawn(move || {
                let result = Engine::discover()
                    .and_then(|engine| engine.set_provider_enabled(&provider_id, enabled))
                    .and_then(|_| Engine::discover()?.collect());
                {
                    let mut state = lock_state(&worker_state);
                    match result {
                        Ok(mut snapshot) => {
                            if let Some(SnapshotData::Engine(previous)) = state.snapshot.as_ref() {
                                snapshot.costs = previous.costs.clone();
                            }
                            state.snapshot = Some(SnapshotData::Engine(snapshot));
                            state.message.clear();
                            if !enabled && state.selected_provider_id == provider_id {
                                state.selected_provider_id.clear();
                            }
                        }
                        Err(error) => {
                            state.message = error.to_string();
                        }
                    }
                }
                worker_refreshing.store(false, Ordering::Release);
                let _ = worker_window.upgrade_in_event_loop(move |window| {
                    if let (Some(settings), Some(tray)) =
                        (worker_settings.upgrade(), worker_tray.upgrade())
                    {
                        apply_state(&window, &settings, &tray, &worker_state);
                    }
                });
            });
    });
}

fn wire_refresh(
    window: &MainWindow,
    settings: &SettingsWindow,
    tray: &AppTray,
    state: Arc<Mutex<AppState>>,
    refreshing: Arc<AtomicBool>,
) {
    {
        let window_weak = window.as_weak();
        let settings_weak = settings.as_weak();
        let tray_weak = tray.as_weak();
        let state = state.clone();
        let refreshing = refreshing.clone();
        window.on_refresh(move || {
            refresh(
                window_weak.clone(),
                settings_weak.clone(),
                tray_weak.clone(),
                state.clone(),
                refreshing.clone(),
            );
        });
    }
    {
        let window_weak = window.as_weak();
        let settings_weak = settings.as_weak();
        let tray_weak = tray.as_weak();
        let state = state.clone();
        let refreshing = refreshing.clone();
        tray.on_refresh(move || {
            refresh(
                window_weak.clone(),
                settings_weak.clone(),
                tray_weak.clone(),
                state.clone(),
                refreshing.clone(),
            );
        });
    }
    {
        let window_weak = window.as_weak();
        let settings_weak = settings.as_weak();
        let tray_weak = tray.as_weak();
        settings.on_refresh(move || {
            refresh(
                window_weak.clone(),
                settings_weak.clone(),
                tray_weak.clone(),
                state.clone(),
                refreshing.clone(),
            );
        });
    }
}

fn wire_links(
    window: &MainWindow,
    settings: &SettingsWindow,
    tray: &AppTray,
    state: Arc<Mutex<AppState>>,
) {
    {
        let state = state.clone();
        window.on_open_dashboard(move || open_selected_dashboard(&state));
    }
    {
        let state = state.clone();
        settings.on_open_provider_dashboard(move || open_selected_dashboard(&state));
    }
    tray.on_open_dashboard(move || open_selected_dashboard(&state));
}

fn refresh(
    window: slint::Weak<MainWindow>,
    settings: slint::Weak<SettingsWindow>,
    tray: slint::Weak<AppTray>,
    state: Arc<Mutex<AppState>>,
    refreshing: Arc<AtomicBool>,
) {
    if refreshing.swap(true, Ordering::AcqRel) {
        return;
    }

    let _ = window
        .clone()
        .upgrade_in_event_loop(|window| window.set_loading(true));
    let _ = settings
        .clone()
        .upgrade_in_event_loop(|settings| settings.set_loading(true));
    let _ = tray.clone().upgrade_in_event_loop(|tray| {
        tray.set_refreshing(true);
        tray.set_status_line("Refreshing enabled providers…".into());
        tray.set_icon_level(0);
    });

    let worker_window = window.clone();
    let worker_settings = settings.clone();
    let worker_tray = tray.clone();
    let worker_state = state.clone();
    let worker_refreshing = refreshing.clone();
    let thread_result = thread::Builder::new()
        .name("codexbar-refresh".into())
        .spawn(move || {
            let engine_result = Engine::discover();
            let engine_error = match engine_result {
                Ok(engine) => match engine.collect() {
                    Ok(mut snapshot) => {
                        {
                            let mut state = lock_state(&worker_state);
                            if let Some(SnapshotData::Engine(previous)) = state.snapshot.as_ref() {
                                snapshot.costs = previous.costs.clone();
                            }
                            state.snapshot = Some(SnapshotData::Engine(snapshot));
                            state.message.clear();
                        }
                        schedule_apply(
                            worker_window.clone(),
                            worker_settings.clone(),
                            worker_tray.clone(),
                            worker_state.clone(),
                        );

                        let costs = engine.collect_costs();
                        if !costs.is_empty() {
                            let mut state = lock_state(&worker_state);
                            if let Some(SnapshotData::Engine(snapshot)) = state.snapshot.as_mut() {
                                snapshot.costs = costs;
                            }
                        }
                        worker_refreshing.store(false, Ordering::Release);
                        schedule_apply(worker_window, worker_settings, worker_tray, worker_state);
                        return;
                    }
                    Err(error) => error,
                },
                Err(error) => error,
            };

            let (snapshot, message) = match codex::fetch_snapshot() {
                Ok(snapshot) => (
                    Some(SnapshotData::DirectCodex(snapshot)),
                    format!("{engine_error}; showing direct Codex usage only"),
                ),
                Err(codex_error) => (
                    None,
                    format!("{engine_error}; direct Codex fallback failed: {codex_error}"),
                ),
            };

            {
                let mut state = lock_state(&worker_state);
                if let Some(snapshot) = snapshot {
                    state.snapshot = Some(snapshot);
                }
                state.message = message;
            }
            worker_refreshing.store(false, Ordering::Release);

            schedule_apply(worker_window, worker_settings, worker_tray, worker_state);
        });

    if thread_result.is_err() {
        refreshing.store(false, Ordering::Release);
        let mut state = lock_state(&state);
        state.message = "Could not start the provider refresh worker.".to_owned();
    }
}

fn schedule_apply(
    window: slint::Weak<MainWindow>,
    settings: slint::Weak<SettingsWindow>,
    tray: slint::Weak<AppTray>,
    state: Arc<Mutex<AppState>>,
) {
    let _ = window.upgrade_in_event_loop(move |window| {
        if let (Some(settings), Some(tray)) = (settings.upgrade(), tray.upgrade()) {
            apply_state(&window, &settings, &tray, &state);
        }
    });
}

fn apply_if_available(
    window: &slint::Weak<MainWindow>,
    settings: &slint::Weak<SettingsWindow>,
    tray: &slint::Weak<AppTray>,
    state: &Arc<Mutex<AppState>>,
) {
    if let (Some(window), Some(settings), Some(tray)) =
        (window.upgrade(), settings.upgrade(), tray.upgrade())
    {
        apply_state(&window, &settings, &tray, state);
    }
}

fn apply_state(
    window: &MainWindow,
    settings: &SettingsWindow,
    tray: &AppTray,
    state: &Arc<Mutex<AppState>>,
) {
    window.set_loading(false);
    settings.set_loading(false);
    tray.set_refreshing(false);

    let snapshot = state_snapshot(state);
    match snapshot.snapshot.as_ref() {
        Some(SnapshotData::Engine(engine_snapshot)) => {
            apply_engine_state(window, settings, tray, state, &snapshot, engine_snapshot);
        }
        Some(SnapshotData::DirectCodex(codex_snapshot)) => {
            apply_direct_codex_state(window, settings, tray, &snapshot, codex_snapshot);
        }
        None => {
            window.set_selected_error(snapshot.message.clone().into());
            window.set_updated_text("No provider data is available.".into());
            window.set_engine_text(snapshot.message.clone().into());
            settings.set_engine_path(snapshot.message.clone().into());
            tray.set_status_line("Provider refresh failed".into());
            tray.set_tray_tooltip(snapshot.message.into());
            tray.set_icon_level(4);
        }
    }
}

fn apply_engine_state(
    window: &MainWindow,
    settings: &SettingsWindow,
    tray: &AppTray,
    state: &Arc<Mutex<AppState>>,
    app_state: &AppState,
    snapshot: &NativeSnapshot,
) {
    let enabled_ids = engine_enabled_provider_ids(snapshot);
    let all_ids = snapshot.ordered_provider_ids();
    let selected_id = resolve_selected_provider(
        state,
        &app_state.selected_provider_id,
        &enabled_ids,
        &all_ids,
    );
    let selected = snapshot.dashboard_by_provider(&selected_id);
    let catalog = catalog_entry(snapshot, &selected_id);
    let accent = provider_accent(snapshot, &selected_id);

    let main_items = enabled_ids
        .iter()
        .map(|id| provider_item(snapshot, id, id == &selected_id))
        .collect::<Vec<_>>();
    window.set_providers(ModelRc::new(VecModel::from(main_items)));

    let settings_items = all_ids
        .iter()
        .map(|id| provider_item(snapshot, id, id == &selected_id))
        .collect::<Vec<_>>();
    settings.set_providers(ModelRc::new(VecModel::from(settings_items)));
    settings.set_provider_index(
        all_ids
            .iter()
            .position(|id| id == &selected_id)
            .unwrap_or(0) as i32,
    );
    settings.set_history_days(app_state.history_days as i32);
    settings.set_accent(accent);

    let provider_name = selected
        .map(|provider| provider.name.as_str())
        .or_else(|| catalog.map(|provider| provider.display_name.as_str()))
        .unwrap_or(&selected_id);
    let identity = selected.and_then(|provider| provider.identity.as_ref());
    let account = identity
        .and_then(|identity| identity.account_email.as_deref())
        .unwrap_or_default();
    let plan = identity
        .and_then(|identity| identity.plan.as_deref())
        .unwrap_or_default();
    let source = selected
        .map(|provider| provider.source.as_str())
        .unwrap_or_default();
    let status = selected
        .and_then(|provider| provider.status.as_ref())
        .map(|status| status.label.as_str())
        .unwrap_or_default();
    let provider_error = selected
        .and_then(primary_provider_error)
        .map(|error| error.message.as_str())
        .unwrap_or_default();
    let dashboard_url = provider_dashboard_url(snapshot, &selected_id).unwrap_or_default();
    let icon_resource = catalog.and_then(|provider| provider.icon_resource_name.as_deref());

    window.set_selected_icon(icons::provider_icon(&selected_id, icon_resource));
    window.set_selected_accent(accent);
    window.set_selected_name(provider_name.into());
    window.set_selected_account(account.into());
    window.set_selected_plan(plan.into());
    window.set_selected_source(source.into());
    window.set_selected_status(status.into());
    window.set_selected_error(provider_error.into());
    window.set_dashboard_available(!dashboard_url.is_empty());

    let lanes = selected
        .map(|provider| usage_lanes(provider, accent))
        .unwrap_or_default();
    window.set_usage_lanes(ModelRc::new(VecModel::from(lanes.clone())));
    window.set_details(ModelRc::new(VecModel::from(detail_rows(selected))));

    let credits_text = selected
        .and_then(|provider| provider.credits.as_ref())
        .map(|credits| format_number(credits.remaining, &credits.unit))
        .unwrap_or_default();
    let cost = selected.and_then(|provider| provider.cost.as_ref());
    let full_cost = snapshot.cost_by_provider(&selected_id);
    let today_cost = cost
        .and_then(|cost| cost.today_usd)
        .or_else(|| full_cost.and_then(|cost| cost.session_cost_usd));
    let month_cost = cost
        .and_then(|cost| cost.last30_days_usd)
        .or_else(|| full_cost.and_then(|cost| cost.last30_days_cost_usd));
    window.set_credits_text(credits_text.into());
    window.set_today_cost_text(today_cost.map(format_usd).unwrap_or_default().into());
    window.set_month_cost_text(month_cost.map(format_usd).unwrap_or_default().into());

    let version = snapshot
        .dashboard
        .host
        .codex_bar_version
        .as_deref()
        .unwrap_or("engine");
    let engine_label = format!(
        "CodexBarCore {version} · {}",
        snapshot.engine_path.display()
    );
    window.set_engine_text(engine_label.clone().into());
    window.set_updated_text(
        format!(
            "Updated {} · {}{}",
            format_iso_time(&snapshot.dashboard.generated_at),
            if source.is_empty() {
                "automatic"
            } else {
                source
            },
            if app_state.message.is_empty() {
                String::new()
            } else {
                format!(" · {}", app_state.message)
            }
        )
        .into(),
    );

    settings.set_engine_path(snapshot.engine_path.display().to_string().into());
    settings.set_selected_provider_name(provider_name.into());
    settings.set_selected_provider_summary(provider_summary(snapshot, &selected_id).into());
    settings.set_selected_provider_source(source.into());
    settings.set_selected_provider_status(status.into());
    settings.set_selected_provider_account(account.into());
    settings.set_selected_provider_dashboard(dashboard_url.clone().into());
    settings.set_selected_provider_enabled(
        catalog
            .map(|provider| provider.enabled)
            .unwrap_or_else(|| selected.map(|provider| provider.enabled).unwrap_or(false)),
    );

    let spend = spend_projection(snapshot, app_state.history_days, accent);
    settings.set_history_points(ModelRc::new(VecModel::from(spend.points)));
    settings.set_provider_spend(ModelRc::new(VecModel::from(spend.providers)));
    settings.set_model_spend(ModelRc::new(VecModel::from(spend.models)));
    settings.set_total_spend(format_usd(spend.total).into());
    settings.set_spend_subtitle(
        format!(
            "Local estimated cost history across supported providers · {} days.",
            app_state.history_days
        )
        .into(),
    );

    apply_engine_tray(
        tray,
        provider_name,
        plan,
        status,
        &lanes,
        dashboard_url,
        selected,
    );
}

fn apply_direct_codex_state(
    window: &MainWindow,
    settings: &SettingsWindow,
    tray: &AppTray,
    app_state: &AppState,
    snapshot: &CodexSnapshot,
) {
    let accent = Color::from_rgb_u8(0x49, 0xA3, 0xB0);
    let item = ProviderItem {
        id: "codex".into(),
        name: "Codex".into(),
        short_name: "Codex".into(),
        icon: icons::provider_icon("codex", None),
        accent,
        enabled: true,
        selected: true,
        has_data: snapshot.session.is_some() || snapshot.weekly.is_some(),
        has_error: false,
        status_color: Color::from_rgb_u8(0x5E, 0xD1, 0x8F),
        status_text: "Fallback".into(),
        summary: snapshot
            .most_constrained_window()
            .map(|window| format!("{:.0}% left", window.remaining_percent()))
            .unwrap_or_else(|| "Direct OAuth".to_owned())
            .into(),
    };
    window.set_providers(ModelRc::new(VecModel::from(vec![item.clone()])));
    settings.set_providers(ModelRc::new(VecModel::from(vec![item])));
    window.set_selected_icon(icons::provider_icon("codex", None));
    window.set_selected_accent(accent);
    window.set_selected_name("Codex".into());
    window.set_selected_account(snapshot.account_email.clone().unwrap_or_default().into());
    window.set_selected_plan(
        snapshot
            .plan
            .as_deref()
            .map(format_plan)
            .unwrap_or_else(|| "Codex".to_owned())
            .into(),
    );
    window.set_selected_source("oauth fallback".into());
    window.set_selected_status("Direct".into());
    window.set_selected_error("".into());
    window.set_dashboard_available(true);
    let lanes = direct_codex_lanes(snapshot, accent);
    window.set_usage_lanes(ModelRc::new(VecModel::from(lanes.clone())));
    window.set_details(ModelRc::new(VecModel::from(Vec::<DetailRow>::new())));
    window.set_credits_text(
        snapshot
            .credits
            .map(|value| format!("{value:.2} credits"))
            .unwrap_or_default()
            .into(),
    );
    window.set_today_cost_text("".into());
    window.set_month_cost_text("".into());
    window.set_updated_text(
        format!(
            "Updated {} · direct OAuth fallback",
            snapshot.fetched_at.format("%H:%M")
        )
        .into(),
    );
    window.set_engine_text(app_state.message.clone().into());

    settings.set_provider_index(0);
    settings.set_history_days(app_state.history_days as i32);
    settings.set_accent(accent);
    settings.set_engine_path(app_state.message.clone().into());
    settings.set_selected_provider_name("Codex".into());
    settings.set_selected_provider_summary("Direct OAuth fallback".into());
    settings.set_selected_provider_source("oauth".into());
    settings.set_selected_provider_status("Provider engine unavailable".into());
    settings
        .set_selected_provider_account(snapshot.account_email.clone().unwrap_or_default().into());
    settings.set_selected_provider_dashboard(
        fallback_dashboard_url("codex").unwrap_or_default().into(),
    );
    settings.set_selected_provider_enabled(true);
    settings.set_history_points(ModelRc::new(VecModel::from(Vec::<HistoryPoint>::new())));
    settings.set_provider_spend(ModelRc::new(VecModel::from(Vec::<SpendRow>::new())));
    settings.set_model_spend(ModelRc::new(VecModel::from(Vec::<SpendRow>::new())));
    settings.set_total_spend("$0.00".into());

    let plan = snapshot
        .plan
        .as_deref()
        .map(format_plan)
        .unwrap_or_else(|| "Codex".to_owned());
    tray.set_provider_line(format!("Codex · {plan}").into());
    apply_tray_lanes(tray, &lanes);
    tray.set_status_line("Direct OAuth fallback".into());
    tray.set_dashboard_available(true);
    set_tray_remaining(
        tray,
        snapshot
            .most_constrained_window()
            .map(CodexUsageWindow::remaining_percent),
        "Codex",
    );
}

fn provider_item(snapshot: &NativeSnapshot, provider_id: &str, selected: bool) -> ProviderItem {
    let catalog = catalog_entry(snapshot, provider_id);
    let dashboard = snapshot.dashboard_by_provider(provider_id);
    let name = dashboard
        .map(|provider| provider.name.as_str())
        .or_else(|| catalog.map(|provider| provider.display_name.as_str()))
        .unwrap_or(provider_id);
    let short_name = catalog
        .and_then(|provider| provider.short_display_name.as_deref())
        .unwrap_or(name);
    let enabled = catalog
        .map(|provider| provider.enabled)
        .or_else(|| dashboard.map(|provider| provider.enabled))
        .unwrap_or(false);
    let error = dashboard.and_then(primary_provider_error);
    let status = dashboard.and_then(|provider| provider.status.as_ref());
    ProviderItem {
        id: provider_id.into(),
        name: name.into(),
        short_name: short_name.into(),
        icon: icons::provider_icon(
            provider_id,
            catalog.and_then(|provider| provider.icon_resource_name.as_deref()),
        ),
        accent: provider_accent(snapshot, provider_id),
        enabled,
        selected,
        has_data: dashboard.is_some_and(|provider| {
            !provider.windows.is_empty() || provider.credits.is_some() || provider.cost.is_some()
        }),
        has_error: error.is_some(),
        status_color: status_color(status.map(|status| status.level.as_str())),
        status_text: status
            .map(|status| status.label.as_str())
            .unwrap_or_default()
            .into(),
        summary: provider_summary(snapshot, provider_id).into(),
    }
}

fn provider_summary(snapshot: &NativeSnapshot, provider_id: &str) -> String {
    let Some(provider) = snapshot.dashboard_by_provider(provider_id) else {
        return if catalog_entry(snapshot, provider_id).is_some_and(|provider| provider.enabled) {
            "Waiting for usage".to_owned()
        } else {
            "Disabled".to_owned()
        };
    };
    if let Some(error) = primary_provider_error(provider) {
        return error.message.clone();
    }
    if let Some(window) = provider
        .windows
        .iter()
        .min_by(|left, right| left.remaining_percent.total_cmp(&right.remaining_percent))
    {
        return format!("{:.0}% left · {}", window.remaining_percent, window.label);
    }
    if let Some(credits) = provider.credits.as_ref() {
        return format_number(credits.remaining, &credits.unit);
    }
    "No usage returned".to_owned()
}

fn primary_provider_error(provider: &DashboardProvider) -> Option<&crate::engine::ProviderError> {
    let has_usable_usage = !provider.windows.is_empty()
        || provider.credits.is_some()
        || provider.cost.is_some()
        || !provider.details.is_empty();
    (!has_usable_usage)
        .then_some(provider.error.as_ref())
        .flatten()
}

fn usage_lanes(provider: &DashboardProvider, accent: Color) -> Vec<UsageLane> {
    provider
        .windows
        .iter()
        .enumerate()
        .map(|(index, window)| {
            let pace = pace_for_index(provider, index);
            UsageLane {
                kind: window.kind.clone().into(),
                label: window.label.clone().into(),
                used_percent: window.used_percent.clamp(0.0, 100.0) as f32,
                value_text: format!("{:.0}% left", window.remaining_percent).into(),
                reset_text: format_reset(window).into(),
                pace_text: pace
                    .map(|pace| pace.summary.as_str())
                    .unwrap_or_default()
                    .into(),
                pace_deficit: pace.is_some_and(|pace| pace.delta_percent > 0.0),
                accent,
            }
        })
        .collect()
}

fn pace_for_index(provider: &DashboardProvider, index: usize) -> Option<&PaceLane> {
    let pace = provider.pace.as_ref()?;
    match index {
        0 => pace.primary.as_ref(),
        1 => pace.secondary.as_ref(),
        2 => pace.tertiary.as_ref(),
        _ => None,
    }
}

fn detail_rows(provider: Option<&DashboardProvider>) -> Vec<DetailRow> {
    provider
        .into_iter()
        .flat_map(|provider| provider.details.iter())
        .flat_map(|section| {
            section.rows.iter().map(|row| DetailRow {
                section: section.title.clone().unwrap_or_default().into(),
                label: row.label.clone().into(),
                value: row.value.clone().into(),
                secondary: row.secondary_value.clone().unwrap_or_default().into(),
            })
        })
        .take(10)
        .collect()
}

fn direct_codex_lanes(snapshot: &CodexSnapshot, accent: Color) -> Vec<UsageLane> {
    let mut lanes = Vec::new();
    if let Some(session) = snapshot.session.as_ref() {
        lanes.push(direct_codex_lane("session", "Session", session, accent));
    }
    if let Some(weekly) = snapshot.weekly.as_ref() {
        lanes.push(direct_codex_lane("weekly", "Weekly", weekly, accent));
    }
    lanes
}

fn direct_codex_lane(
    kind: &str,
    label: &str,
    window: &CodexUsageWindow,
    accent: Color,
) -> UsageLane {
    UsageLane {
        kind: kind.into(),
        label: label.into(),
        used_percent: window.used_percent.clamp(0.0, 100.0) as f32,
        value_text: format!("{:.0}% left", window.remaining_percent()).into(),
        reset_text: format!("Resets {}", format_reset_date(window.reset_at)).into(),
        pace_text: "".into(),
        pace_deficit: false,
        accent,
    }
}

struct SpendProjection {
    points: Vec<HistoryPoint>,
    providers: Vec<SpendRow>,
    models: Vec<SpendRow>,
    total: f64,
}

fn spend_projection(snapshot: &NativeSnapshot, days: u32, accent: Color) -> SpendProjection {
    let mut daily = BTreeMap::<String, f64>::new();
    for cost in &snapshot.costs {
        for entry in &cost.daily {
            if let Some(value) = entry.total_cost {
                *daily.entry(entry.date.clone()).or_default() += value;
            }
        }
    }

    let selected_dates = daily
        .keys()
        .rev()
        .take(days as usize)
        .cloned()
        .collect::<HashSet<_>>();
    let maximum = selected_dates
        .iter()
        .filter_map(|date| daily.get(date))
        .copied()
        .fold(0.0_f64, f64::max);
    let points = daily
        .iter()
        .filter(|(date, _)| selected_dates.contains(*date))
        .map(|(date, value)| HistoryPoint {
            label: compact_day(date).into(),
            value_text: format_usd(*value).into(),
            normalized: if maximum > 0.0 {
                (*value / maximum).clamp(0.0, 1.0) as f32
            } else {
                0.0
            },
            accent,
        })
        .collect::<Vec<_>>();
    let total = selected_dates
        .iter()
        .filter_map(|date| daily.get(date))
        .sum();

    let mut provider_totals = Vec::<(String, f64, i64)>::new();
    let mut model_totals = HashMap::<String, (f64, i64)>::new();
    for cost in &snapshot.costs {
        let mut provider_cost = 0.0;
        let mut provider_tokens = 0_i64;
        for entry in &cost.daily {
            if !selected_dates.contains(&entry.date) {
                continue;
            }
            provider_cost += entry.total_cost.unwrap_or(0.0);
            provider_tokens += entry.total_tokens.unwrap_or(0);
            for model in entry.model_breakdowns.as_deref().unwrap_or_default() {
                let totals = model_totals.entry(model.model_name.clone()).or_default();
                totals.0 += model.cost.unwrap_or(0.0);
                totals.1 += model.total_tokens.unwrap_or(0);
            }
        }
        if provider_cost > 0.0 || provider_tokens > 0 {
            provider_totals.push((cost.provider.clone(), provider_cost, provider_tokens));
        }
    }
    provider_totals.sort_by(|left, right| right.1.total_cmp(&left.1));
    let providers = provider_totals
        .into_iter()
        .take(7)
        .enumerate()
        .map(|(index, (provider_id, value, tokens))| SpendRow {
            rank: format!("#{}", index + 1).into(),
            label: provider_display_name(snapshot, &provider_id).into(),
            value: format_usd(value).into(),
            detail: format_tokens(tokens).into(),
            accent: provider_accent(snapshot, &provider_id),
        })
        .collect();

    let mut models = model_totals.into_iter().collect::<Vec<_>>();
    models.sort_by(|left, right| right.1.0.total_cmp(&left.1.0));
    let models = models
        .into_iter()
        .take(7)
        .enumerate()
        .map(|(index, (name, (value, tokens)))| SpendRow {
            rank: format!("#{}", index + 1).into(),
            label: name.into(),
            value: format_usd(value).into(),
            detail: format_tokens(tokens).into(),
            accent,
        })
        .collect();

    SpendProjection {
        points,
        providers,
        models,
        total,
    }
}

fn apply_engine_tray(
    tray: &AppTray,
    provider_name: &str,
    plan: &str,
    status: &str,
    lanes: &[UsageLane],
    dashboard_url: String,
    provider: Option<&DashboardProvider>,
) {
    tray.set_provider_line(
        if plan.is_empty() {
            provider_name.to_owned()
        } else {
            format!("{provider_name} · {plan}")
        }
        .into(),
    );
    apply_tray_lanes(tray, lanes);
    tray.set_status_line(if status.is_empty() {
        "Updated from CodexBarCore".into()
    } else {
        status.into()
    });
    tray.set_dashboard_available(!dashboard_url.is_empty());
    let remaining = provider.and_then(|provider| {
        provider
            .windows
            .iter()
            .map(|window| window.remaining_percent)
            .min_by(f64::total_cmp)
    });
    set_tray_remaining(tray, remaining, provider_name);
}

fn apply_tray_lanes(tray: &AppTray, lanes: &[UsageLane]) {
    tray.set_lane_one_visible(!lanes.is_empty());
    tray.set_lane_two_visible(lanes.len() > 1);
    tray.set_lane_one_line(
        lanes
            .first()
            .map(|lane| format!("{}: {}", lane.label, lane.value_text))
            .unwrap_or_default()
            .into(),
    );
    tray.set_lane_two_line(
        lanes
            .get(1)
            .map(|lane| format!("{}: {}", lane.label, lane.value_text))
            .unwrap_or_default()
            .into(),
    );
}

fn set_tray_remaining(tray: &AppTray, remaining: Option<f64>, provider_name: &str) {
    let remaining = remaining.map(|value| value.clamp(0.0, 100.0));
    tray.set_tray_title(
        remaining
            .map(|value| format!("{value:.0}%"))
            .unwrap_or_else(|| "—".to_owned())
            .into(),
    );
    tray.set_tray_tooltip(
        remaining
            .map(|value| format!("{provider_name}: {value:.0}% left"))
            .unwrap_or_else(|| format!("{provider_name}: usage unavailable"))
            .into(),
    );
    tray.set_icon_level(match remaining {
        Some(value) if value <= 20.0 => 3,
        Some(value) if value <= 50.0 => 2,
        Some(_) => 1,
        None => 4,
    });
}

fn resolve_selected_provider(
    state: &Arc<Mutex<AppState>>,
    current: &str,
    enabled_ids: &[String],
    all_ids: &[String],
) -> String {
    let selected = if enabled_ids.iter().any(|id| id == current) {
        current.to_owned()
    } else if let Some(codex) = enabled_ids.iter().find(|id| id.as_str() == "codex") {
        codex.clone()
    } else if let Some(first) = enabled_ids.first() {
        first.clone()
    } else if all_ids.iter().any(|id| id == current) {
        current.to_owned()
    } else {
        all_ids
            .first()
            .cloned()
            .unwrap_or_else(|| "codex".to_owned())
    };
    update_selected_provider(state, &selected);
    selected
}

fn update_selected_provider(state: &Arc<Mutex<AppState>>, provider_id: &str) {
    lock_state(state).selected_provider_id = provider_id.to_owned();
}

fn state_snapshot(state: &Arc<Mutex<AppState>>) -> AppState {
    lock_state(state).clone()
}

fn lock_state(state: &Arc<Mutex<AppState>>) -> std::sync::MutexGuard<'_, AppState> {
    state
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn enabled_provider_ids(state: &AppState) -> Vec<String> {
    match state.snapshot.as_ref() {
        Some(SnapshotData::Engine(snapshot)) => engine_enabled_provider_ids(snapshot),
        Some(SnapshotData::DirectCodex(_)) => vec!["codex".to_owned()],
        None => Vec::new(),
    }
}

fn all_provider_ids(state: &AppState) -> Vec<String> {
    match state.snapshot.as_ref() {
        Some(SnapshotData::Engine(snapshot)) => snapshot.ordered_provider_ids(),
        Some(SnapshotData::DirectCodex(_)) => vec!["codex".to_owned()],
        None => Vec::new(),
    }
}

fn engine_enabled_provider_ids(snapshot: &NativeSnapshot) -> Vec<String> {
    let mut ids = snapshot
        .catalog
        .iter()
        .filter(|provider| provider.enabled)
        .map(|provider| provider.id.clone())
        .collect::<Vec<_>>();
    for provider in &snapshot.dashboard.providers {
        if provider.enabled && !ids.contains(&provider.id) {
            ids.push(provider.id.clone());
        }
    }
    if ids.is_empty() {
        ids.extend(
            snapshot
                .dashboard
                .providers
                .iter()
                .map(|provider| provider.id.clone()),
        );
    }
    ids
}

fn catalog_entry<'a>(
    snapshot: &'a NativeSnapshot,
    provider_id: &str,
) -> Option<&'a ProviderCatalogEntry> {
    snapshot
        .catalog
        .iter()
        .find(|provider| provider.id == provider_id)
}

fn provider_display_name(snapshot: &NativeSnapshot, provider_id: &str) -> String {
    snapshot
        .dashboard_by_provider(provider_id)
        .map(|provider| provider.name.clone())
        .or_else(|| {
            catalog_entry(snapshot, provider_id).map(|provider| provider.display_name.clone())
        })
        .unwrap_or_else(|| provider_id.to_owned())
}

fn provider_accent(snapshot: &NativeSnapshot, provider_id: &str) -> Color {
    let value = snapshot
        .dashboard_by_provider(provider_id)
        .map(|provider| provider.display.accent_color.as_str())
        .filter(|value| !value.is_empty() && *value != "#6E6E6E")
        .or_else(|| {
            catalog_entry(snapshot, provider_id).map(|provider| provider.accent_color.as_str())
        });
    value
        .and_then(parse_hex_color)
        .unwrap_or_else(|| deterministic_accent(provider_id))
}

fn status_color(level: Option<&str>) -> Color {
    match level {
        Some("ok") => Color::from_rgb_u8(0x5E, 0xD1, 0x8F),
        Some("warning") => Color::from_rgb_u8(0xF0, 0xB5, 0x59),
        Some("critical") => Color::from_rgb_u8(0xFF, 0x66, 0x6A),
        Some(_) => Color::from_rgb_u8(0x8E, 0x8E, 0x93),
        None => Color::from_argb_u8(0, 0, 0, 0),
    }
}

fn parse_hex_color(value: &str) -> Option<Color> {
    let value = value.strip_prefix('#').unwrap_or(value);
    if value.len() != 6 {
        return None;
    }
    let red = u8::from_str_radix(&value[0..2], 16).ok()?;
    let green = u8::from_str_radix(&value[2..4], 16).ok()?;
    let blue = u8::from_str_radix(&value[4..6], 16).ok()?;
    Some(Color::from_rgb_u8(red, green, blue))
}

fn deterministic_accent(provider_id: &str) -> Color {
    const PALETTE: &[(u8, u8, u8)] = &[
        (0x49, 0xA3, 0xB0),
        (0xA5, 0x7A, 0xE8),
        (0xE0, 0x8B, 0x58),
        (0x4F, 0xB8, 0x7D),
        (0xD0, 0x69, 0x89),
        (0x6E, 0x8F, 0xD5),
    ];
    let index = provider_id.bytes().fold(0_usize, |hash, byte| {
        hash.wrapping_mul(31).wrapping_add(byte as usize)
    }) % PALETTE.len();
    let (red, green, blue) = PALETTE[index];
    Color::from_rgb_u8(red, green, blue)
}

fn format_reset(window: &DashboardWindow) -> String {
    window
        .reset_at
        .as_deref()
        .and_then(parse_iso_date)
        .map(|date| format!("Resets {}", format_reset_date(date)))
        .unwrap_or_default()
}

fn parse_iso_date(value: &str) -> Option<DateTime<Local>> {
    DateTime::parse_from_rfc3339(value)
        .ok()
        .map(|date| date.with_timezone(&Local))
}

fn format_iso_time(value: &str) -> String {
    parse_iso_date(value)
        .map(|date| date.format("%H:%M").to_string())
        .unwrap_or_else(|| value.to_owned())
}

fn format_reset_date(reset_at: DateTime<Local>) -> String {
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

fn compact_day(value: &str) -> String {
    NaiveDate::parse_from_str(&value[..value.len().min(10)], "%Y-%m-%d")
        .map(|date| date.format("%d").to_string())
        .unwrap_or_else(|_| {
            value
                .chars()
                .rev()
                .take(2)
                .collect::<String>()
                .chars()
                .rev()
                .collect()
        })
}

fn format_usd(value: f64) -> String {
    format!("${value:.2}")
}

fn format_number(value: f64, unit: &str) -> String {
    if unit.is_empty() {
        format!("{value:.2}")
    } else {
        format!("{value:.2} {unit}")
    }
}

fn format_tokens(value: i64) -> String {
    let value = value.max(0) as f64;
    if value >= 1_000_000.0 {
        format!("{:.1}M tokens", value / 1_000_000.0)
    } else if value >= 1_000.0 {
        format!("{:.1}K tokens", value / 1_000.0)
    } else {
        format!("{value:.0} tokens")
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

fn provider_dashboard_url(snapshot: &NativeSnapshot, provider_id: &str) -> Option<String> {
    catalog_entry(snapshot, provider_id)
        .and_then(|provider| provider.dashboard_url.clone())
        .filter(|value| !value.trim().is_empty())
        .or_else(|| fallback_dashboard_url(provider_id).map(str::to_owned))
}

fn fallback_dashboard_url(provider_id: &str) -> Option<&'static str> {
    match provider_id {
        "codex" => Some("https://chatgpt.com/codex/settings/usage"),
        "openai" => Some("https://platform.openai.com/usage"),
        "azureopenai" => Some("https://ai.azure.com"),
        "claude" => Some("https://console.anthropic.com/settings/billing"),
        "cursor" => Some("https://cursor.com/dashboard?tab=usage"),
        "gemini" => Some("https://gemini.google.com"),
        "copilot" => Some("https://github.com/settings/copilot"),
        "openrouter" => Some("https://openrouter.ai/settings/credits"),
        "deepseek" => Some("https://platform.deepseek.com/usage"),
        "mistral" => Some("https://admin.mistral.ai/organization/usage"),
        "amp" => Some("https://ampcode.com/settings/usage"),
        "kilo" => Some("https://app.kilo.ai/usage"),
        "kimi" => Some("https://www.kimi.com/code/console"),
        "moonshot" => Some("https://platform.moonshot.ai/console/account"),
        "augment" => Some("https://app.augmentcode.com/account/subscription"),
        "windsurf" => Some("https://windsurf.com/subscription/usage"),
        "perplexity" => Some("https://www.perplexity.ai/account/usage"),
        "elevenlabs" => Some("https://elevenlabs.io/app/developers/usage"),
        "groq" => Some("https://console.groq.com/dashboard/usage"),
        "grok" => Some("https://grok.com/?_s=usage"),
        "ollama" => Some("https://ollama.com/settings"),
        "fireworks" => Some("https://app.fireworks.ai"),
        "bedrock" => Some("https://console.aws.amazon.com/bedrock"),
        "vertexai" => Some("https://console.cloud.google.com/vertex-ai"),
        "xai" => Some("https://console.x.ai"),
        "poe" => Some("https://poe.com/api/keys"),
        "venice" => Some("https://venice.ai/settings/api"),
        "codebuff" => Some("https://www.codebuff.com/usage"),
        "devin" => Some("https://app.devin.ai"),
        "kiro" => Some("https://app.kiro.dev/account/usage"),
        "notion" => Some("https://app.notion.com/"),
        "warp" => Some("https://docs.warp.dev/reference/cli/api-keys"),
        _ => None,
    }
}

fn open_selected_dashboard(state: &Arc<Mutex<AppState>>) {
    let snapshot = state_snapshot(state);
    let url = match snapshot.snapshot.as_ref() {
        Some(SnapshotData::Engine(engine_snapshot)) => {
            provider_dashboard_url(engine_snapshot, &snapshot.selected_provider_id)
        }
        Some(SnapshotData::DirectCodex(_)) => fallback_dashboard_url("codex").map(str::to_owned),
        None => None,
    };
    if let Some(url) = url {
        let _ = open_url_detached(&url);
    }
}

fn open_url_detached(url: &str) -> std::io::Result<()> {
    #[cfg(target_os = "linux")]
    {
        let unit = format!("codexbar-open-{}", std::process::id());
        let status = Command::new("systemd-run")
            .args([
                "--user",
                "--quiet",
                "--collect",
                "--unit",
                &unit,
                "xdg-open",
                url,
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
        if status.is_ok_and(|status| status.success()) {
            return Ok(());
        }
        Command::new("xdg-open")
            .arg(url)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map(|_| ())
    }

    #[cfg(target_os = "macos")]
    {
        Command::new("open")
            .arg(url)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map(|_| ())
    }

    #[cfg(windows)]
    {
        Command::new("rundll32")
            .args(["url.dll,FileProtocolHandler", url])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map(|_| ())
    }

    #[cfg(not(any(target_os = "linux", target_os = "macos", windows)))]
    {
        let _ = url;
        Err(std::io::Error::new(
            std::io::ErrorKind::Unsupported,
            "opening URLs is unsupported on this platform",
        ))
    }
}

fn quit() {
    let _ = slint::quit_event_loop();
}

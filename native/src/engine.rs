#![allow(dead_code)]

use std::collections::HashMap;
use std::env;
use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use serde::Deserialize;
use serde::de::DeserializeOwned;
use thiserror::Error;

#[derive(Debug, Clone)]
pub struct NativeSnapshot {
    pub dashboard: DashboardSnapshot,
    pub catalog: Vec<ProviderCatalogEntry>,
    pub costs: Vec<CostPayload>,
    pub engine_path: PathBuf,
}

impl NativeSnapshot {
    pub fn cost_by_provider(&self, provider_id: &str) -> Option<&CostPayload> {
        self.costs.iter().find(|cost| cost.provider == provider_id)
    }

    pub fn dashboard_by_provider(&self, provider_id: &str) -> Option<&DashboardProvider> {
        self.dashboard
            .providers
            .iter()
            .find(|provider| provider.id == provider_id)
    }

    pub fn ordered_provider_ids(&self) -> Vec<String> {
        let mut ids = Vec::with_capacity(self.catalog.len().max(self.dashboard.providers.len()));
        for provider in &self.catalog {
            if !ids.contains(&provider.id) {
                ids.push(provider.id.clone());
            }
        }
        for provider in &self.dashboard.providers {
            if !ids.contains(&provider.id) {
                ids.push(provider.id.clone());
            }
        }
        ids
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DashboardSnapshot {
    pub schema_version: u32,
    pub generated_at: String,
    #[serde(default)]
    pub stale_after_seconds: u64,
    #[serde(default)]
    pub host: DashboardHost,
    #[serde(default)]
    pub providers: Vec<DashboardProvider>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DashboardHost {
    pub codex_bar_version: Option<String>,
    #[serde(default)]
    pub refresh_interval_seconds: u64,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DashboardProvider {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub source: String,
    pub status: Option<DashboardStatus>,
    pub identity: Option<DashboardIdentity>,
    #[serde(default)]
    pub windows: Vec<DashboardWindow>,
    pub credits: Option<DashboardCredits>,
    pub cost: Option<DashboardCost>,
    #[serde(default)]
    pub display: DashboardDisplay,
    pub error: Option<ProviderError>,
    pub updated_at: Option<String>,
    #[serde(default)]
    pub accounts: Vec<DashboardAccount>,
    pub accounts_error: Option<String>,
    pub pace: Option<ProviderPace>,
    #[serde(default)]
    pub details: Vec<ProviderDetailSection>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DashboardStatus {
    pub level: String,
    pub label: String,
    pub updated_at: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DashboardIdentity {
    pub account_email: Option<String>,
    pub plan: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DashboardWindow {
    pub kind: String,
    pub label: String,
    pub used_percent: f64,
    pub remaining_percent: f64,
    pub reset_at: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DashboardCredits {
    pub remaining: f64,
    pub unit: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DashboardCost {
    #[serde(rename = "todayUSD")]
    pub today_usd: Option<f64>,
    #[serde(rename = "last30DaysUSD")]
    pub last30_days_usd: Option<f64>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DashboardDisplay {
    #[serde(default = "default_accent")]
    pub accent_color: String,
    #[serde(default)]
    pub sort_key: i32,
    #[serde(default)]
    pub priority: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DashboardAccount {
    pub id: String,
    pub label: String,
    #[serde(default)]
    pub active: bool,
    pub identity: Option<DashboardIdentity>,
    #[serde(default)]
    pub windows: Vec<DashboardWindow>,
    pub pace: Option<ProviderPace>,
    pub error: Option<String>,
    pub updated_at: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ProviderPace {
    pub primary: Option<PaceLane>,
    pub secondary: Option<PaceLane>,
    pub tertiary: Option<PaceLane>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PaceLane {
    pub stage: String,
    pub delta_percent: f64,
    pub expected_used_percent: f64,
    pub will_last_to_reset: bool,
    pub eta_seconds: Option<f64>,
    pub summary: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderDetailSection {
    pub title: Option<String>,
    #[serde(default)]
    pub rows: Vec<ProviderDetailRow>,
    pub chart: Option<ProviderDetailChart>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderDetailRow {
    pub label: String,
    pub value: String,
    pub secondary_value: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderDetailChart {
    pub kind: String,
    pub title: Option<String>,
    pub unit: Option<String>,
    #[serde(default)]
    pub points: Vec<ProviderDetailPoint>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ProviderDetailPoint {
    pub label: String,
    pub value: f64,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderCatalogEntry {
    #[serde(rename = "provider")]
    pub id: String,
    pub display_name: String,
    #[serde(default)]
    pub short_display_name: Option<String>,
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub default_enabled: bool,
    #[serde(default = "default_accent")]
    pub accent_color: String,
    #[serde(default)]
    pub icon_resource_name: Option<String>,
    #[serde(default)]
    pub session_label: Option<String>,
    #[serde(default)]
    pub weekly_label: Option<String>,
    #[serde(default)]
    #[serde(rename = "dashboardURL")]
    pub dashboard_url: Option<String>,
    #[serde(default)]
    #[serde(rename = "statusURL")]
    pub status_url: Option<String>,
    #[serde(default)]
    pub supports_credits: bool,
    #[serde(default)]
    pub supports_cost: bool,
    #[serde(default)]
    pub supports_history: bool,
    #[serde(default)]
    pub balance_only: bool,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ProviderError {
    #[serde(default)]
    pub code: i32,
    pub message: String,
    pub kind: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CostPayload {
    pub provider: String,
    #[serde(default)]
    pub source: String,
    pub updated_at: Option<String>,
    pub currency_code: Option<String>,
    pub session_tokens: Option<i64>,
    #[serde(rename = "sessionCostUSD")]
    pub session_cost_usd: Option<f64>,
    pub history_days: Option<u32>,
    pub history_coverage_is_established: Option<bool>,
    pub last30_days_tokens: Option<i64>,
    #[serde(rename = "last30DaysCostUSD")]
    pub last30_days_cost_usd: Option<f64>,
    #[serde(rename = "meteredCostUSD")]
    pub metered_cost_usd: Option<f64>,
    #[serde(default)]
    pub daily: Vec<CostDailyEntry>,
    #[serde(default)]
    pub projects: Vec<CostProject>,
    pub totals: Option<CostTotals>,
    pub error: Option<ProviderError>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CostDailyEntry {
    pub date: String,
    pub input_tokens: Option<i64>,
    pub output_tokens: Option<i64>,
    pub cache_read_tokens: Option<i64>,
    pub cache_creation_tokens: Option<i64>,
    pub total_tokens: Option<i64>,
    #[serde(rename = "totalCost")]
    pub total_cost: Option<f64>,
    #[serde(default)]
    pub models_used: Option<Vec<String>>,
    #[serde(default)]
    pub model_breakdowns: Option<Vec<CostModelBreakdown>>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CostModelBreakdown {
    pub model_name: String,
    #[serde(rename = "cost")]
    pub cost: Option<f64>,
    pub total_tokens: Option<i64>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CostProject {
    pub name: String,
    pub path: Option<String>,
    pub total_tokens: Option<i64>,
    #[serde(rename = "totalCostUSD")]
    pub total_cost_usd: Option<f64>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CostTotals {
    #[serde(flatten)]
    pub values: HashMap<String, serde_json::Value>,
}

fn default_accent() -> String {
    "#6E6E6E".to_owned()
}

#[derive(Debug, Error)]
pub enum EngineError {
    #[error("CodexBar provider engine was not found")]
    NotFound,
    #[error("could not launch the CodexBar provider engine")]
    Launch,
    #[error("CodexBar provider engine command failed: {0}")]
    CommandFailed(String),
    #[error("CodexBar provider engine returned invalid {0} JSON")]
    InvalidJson(String),
}

#[derive(Debug, Clone)]
pub struct Engine {
    path: PathBuf,
}

impl Engine {
    pub fn discover() -> Result<Self, EngineError> {
        discover_engine_path()
            .map(|path| Self { path })
            .ok_or(EngineError::NotFound)
    }

    pub fn collect(&self) -> Result<NativeSnapshot, EngineError> {
        // The standalone Swift engine is intentionally short-lived. Run one
        // projection at a time so refreshes do not multiply its peak memory.
        let dashboard = self.run_json::<DashboardSnapshot>(
            "dashboard",
            &["dashboard", "--identity", "full", "--timeout", "60"],
        )?;
        let mut catalog = self.run_json::<Vec<ProviderCatalogEntry>>(
            "provider catalog",
            &["config", "providers", "--json"],
        )?;
        if catalog.is_empty() {
            catalog = dashboard
                .providers
                .iter()
                .map(|provider| ProviderCatalogEntry {
                    id: provider.id.clone(),
                    display_name: provider.name.clone(),
                    short_display_name: None,
                    enabled: provider.enabled,
                    default_enabled: provider.enabled,
                    accent_color: provider.display.accent_color.clone(),
                    icon_resource_name: None,
                    session_label: None,
                    weekly_label: None,
                    dashboard_url: None,
                    status_url: None,
                    supports_credits: provider.credits.is_some(),
                    supports_cost: provider.cost.is_some(),
                    supports_history: false,
                    balance_only: provider.windows.is_empty() && provider.credits.is_some(),
                })
                .collect();
        }

        let accents: HashMap<&str, &str> = dashboard
            .providers
            .iter()
            .map(|provider| (provider.id.as_str(), provider.display.accent_color.as_str()))
            .collect();
        for provider in &mut catalog {
            if provider.accent_color == default_accent()
                && let Some(accent) = accents.get(provider.id.as_str())
            {
                provider.accent_color = (*accent).to_owned();
            }
        }

        Ok(NativeSnapshot {
            dashboard,
            catalog,
            costs: Vec::new(),
            engine_path: self.path.clone(),
        })
    }

    pub fn collect_costs(&self) -> Vec<CostPayload> {
        self.run_json_allow_failure::<Vec<CostPayload>>(
            "cost history",
            &["cost", "--provider", "all", "--json", "--days", "30"],
        )
        .unwrap_or_default()
    }

    pub fn set_provider_enabled(
        &self,
        provider_id: &str,
        enabled: bool,
    ) -> Result<(), EngineError> {
        let operation = if enabled { "enable" } else { "disable" };
        let output = self.output(&["config", operation, "--provider", provider_id, "--json"])?;
        if output.status.success() {
            Ok(())
        } else {
            Err(EngineError::CommandFailed(format!("config {operation}")))
        }
    }

    fn run_json<T: DeserializeOwned>(
        &self,
        label: &str,
        arguments: &[&str],
    ) -> Result<T, EngineError> {
        let output = self.output(arguments)?;
        if !output.status.success() {
            return Err(EngineError::CommandFailed(label.to_owned()));
        }
        decode_json(label, &output)
    }

    fn run_json_allow_failure<T: DeserializeOwned>(
        &self,
        label: &str,
        arguments: &[&str],
    ) -> Result<T, EngineError> {
        let output = self.output(arguments)?;
        if output.stdout.is_empty() {
            return Err(EngineError::CommandFailed(label.to_owned()));
        }
        decode_json(label, &output)
    }

    fn output(&self, arguments: &[&str]) -> Result<Output, EngineError> {
        let mut command = Command::new(&self.path);
        command.args(arguments);
        command.env("NO_COLOR", "1");
        command.env("CODEXBAR_NATIVE_CLIENT", env!("CARGO_PKG_VERSION"));

        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            command.creation_flags(0x0800_0000);
        }

        command.output().map_err(|_| EngineError::Launch)
    }
}

fn decode_json<T: DeserializeOwned>(label: &str, output: &Output) -> Result<T, EngineError> {
    serde_json::from_slice(&output.stdout).map_err(|_| EngineError::InvalidJson(label.to_owned()))
}

fn discover_engine_path() -> Option<PathBuf> {
    if let Some(explicit) = env::var_os("CODEXBAR_ENGINE") {
        let path = PathBuf::from(explicit);
        if is_engine_file(&path) {
            return Some(path);
        }
    }

    if let Ok(executable) = env::current_exe()
        && let Some(directory) = executable.parent()
    {
        for relative in engine_relative_candidates() {
            let candidate = directory.join(relative);
            if is_engine_file(&candidate) {
                return Some(candidate);
            }
        }
    }

    if let Some(home) = env::var_os("HOME").or_else(|| env::var_os("USERPROFILE")) {
        let candidate = PathBuf::from(home)
            .join(".local")
            .join("lib")
            .join("codexbar-native")
            .join(engine_filename("CodexBarCLI"));
        if is_engine_file(&candidate) {
            return Some(candidate);
        }
    }

    let path = env::var_os("PATH")?;
    for directory in env::split_paths(&path) {
        for name in ["CodexBarCLI", "codexbar"] {
            let candidate = directory.join(engine_filename(name));
            if is_engine_file(&candidate) {
                return Some(candidate);
            }
        }
    }
    None
}

fn engine_relative_candidates() -> Vec<PathBuf> {
    vec![
        PathBuf::from(engine_filename("CodexBarCLI")),
        PathBuf::from("libexec").join(engine_filename("CodexBarCLI")),
        PathBuf::from("..")
            .join("libexec")
            .join(engine_filename("CodexBarCLI")),
        PathBuf::from("..")
            .join("lib")
            .join("codexbar-native")
            .join(engine_filename("CodexBarCLI")),
    ]
}

fn engine_filename(name: &str) -> OsString {
    #[cfg(windows)]
    {
        OsString::from(format!("{name}.exe"))
    }
    #[cfg(not(windows))]
    {
        OsString::from(name)
    }
}

fn is_engine_file(path: &Path) -> bool {
    path.is_file()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_dashboard_v1_and_additive_native_fields() {
        let dashboard: DashboardSnapshot = serde_json::from_str(
            r##"{
              "schemaVersion": 1,
              "generatedAt": "2026-08-14T12:00:00Z",
              "staleAfterSeconds": 900,
              "host": {"codexBarVersion":"0.49.6","refreshIntervalSeconds":300},
              "providers": [{
                "id":"codex","name":"Codex","enabled":true,"source":"oauth",
                "identity":{"accountEmail":"person@example.com","plan":"Pro"},
                "windows":[{"kind":"weekly","label":"Weekly","usedPercent":31,
                  "remainingPercent":69,"resetAt":"2026-08-20T12:00:00Z"}],
                "display":{"accentColor":"#49A3B0","sortKey":0,"priority":"normal"},
                "pace":{"primary":null,"secondary":{"stage":"reserve","deltaPercent":-5,
                  "expectedUsedPercent":36,"willLastToReset":true,"etaSeconds":null,
                  "summary":"5% reserve"},"tertiary":null},
                "details":[{"title":"Usage","rows":[{"label":"Requests","value":"12"}],"chart":null}]
              }]
            }"##,
        )
        .expect("dashboard should decode");

        assert_eq!(dashboard.providers.len(), 1);
        assert_eq!(dashboard.providers[0].windows[0].remaining_percent, 69.0);
        assert_eq!(dashboard.providers[0].details[0].rows[0].value, "12");
    }

    #[test]
    fn decodes_legacy_provider_catalog_without_native_metadata() {
        let catalog: Vec<ProviderCatalogEntry> = serde_json::from_str(
            r##"[{"provider":"codex","displayName":"Codex","enabled":true,"defaultEnabled":true}]"##,
        )
        .expect("catalog should decode");

        assert_eq!(catalog[0].accent_color, "#6E6E6E");
        assert!(catalog[0].dashboard_url.is_none());
    }
}

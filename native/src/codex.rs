use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::time::Duration;

use chrono::{DateTime, Local, TimeZone, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use thiserror::Error;
use ureq::Agent;

const DEFAULT_BASE_URL: &str = "https://chatgpt.com/backend-api";
const REFRESH_URL: &str = "https://auth.openai.com/oauth/token";
const OAUTH_CLIENT_ID: &str = "app_EMoamEEZ73f0CkXaXp7hrann";

#[derive(Debug, Clone)]
pub struct UsageWindow {
    pub used_percent: f64,
    pub window_seconds: u64,
    pub reset_at: DateTime<Local>,
}

impl UsageWindow {
    pub fn remaining_percent(&self) -> f64 {
        (100.0 - self.used_percent).clamp(0.0, 100.0)
    }
}

#[derive(Debug, Clone)]
pub struct CodexSnapshot {
    pub account_email: Option<String>,
    pub plan: Option<String>,
    pub session: Option<UsageWindow>,
    pub weekly: Option<UsageWindow>,
    pub credits: Option<f64>,
    pub fetched_at: DateTime<Local>,
}

impl CodexSnapshot {
    pub fn most_constrained_window(&self) -> Option<&UsageWindow> {
        [self.session.as_ref(), self.weekly.as_ref()]
            .into_iter()
            .flatten()
            .min_by(|left, right| {
                left.remaining_percent()
                    .total_cmp(&right.remaining_percent())
            })
    }
}

#[derive(Debug, Error)]
pub enum CodexError {
    #[error("Codex login was not found; run `codex` once to sign in")]
    LoginNotFound,
    #[error("Codex credentials are incomplete; run `codex login`")]
    InvalidCredentials,
    #[error("Codex login expired; run `codex login` again")]
    LoginExpired,
    #[error("Codex returned an invalid usage response")]
    InvalidResponse,
    #[error("Codex API returned HTTP {0}")]
    HttpStatus(u16),
    #[error("network error while contacting Codex")]
    Network,
    #[error("could not safely update Codex credentials")]
    CredentialWrite,
}

#[derive(Debug)]
struct AuthDocument {
    path: PathBuf,
    value: Value,
    credentials: Credentials,
}

#[derive(Debug, Clone)]
struct Credentials {
    access_token: String,
    refresh_token: Option<String>,
    account_id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct UsageResponse {
    email: Option<String>,
    plan_type: Option<String>,
    rate_limit: Option<RateLimit>,
    credits: Option<Credits>,
}

#[derive(Debug, Deserialize)]
struct RateLimit {
    primary_window: Option<ApiWindow>,
    secondary_window: Option<ApiWindow>,
}

#[derive(Debug, Deserialize)]
struct ApiWindow {
    used_percent: f64,
    limit_window_seconds: u64,
    reset_at: i64,
}

#[derive(Debug, Deserialize)]
struct Credits {
    #[serde(default)]
    has_credits: bool,
    #[serde(default)]
    unlimited: bool,
    balance: Option<FlexibleNumber>,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum FlexibleNumber {
    Number(f64),
    String(String),
}

impl FlexibleNumber {
    fn value(&self) -> Option<f64> {
        match self {
            Self::Number(value) => Some(*value),
            Self::String(value) => value.trim().parse().ok(),
        }
    }
}

#[derive(Debug, Deserialize)]
struct RefreshResponse {
    access_token: String,
    refresh_token: Option<String>,
    id_token: Option<String>,
}

#[derive(Debug, Serialize)]
struct RefreshRequest<'a> {
    client_id: &'a str,
    grant_type: &'a str,
    refresh_token: &'a str,
    scope: &'a str,
}

pub fn fetch_snapshot() -> Result<CodexSnapshot, CodexError> {
    let agent = http_agent();
    let mut auth = load_auth_document()?;

    match fetch_usage(&agent, &auth.credentials) {
        Ok(response) => Ok(make_snapshot(response)),
        Err(CodexError::LoginExpired) => {
            let refresh_token = auth
                .credentials
                .refresh_token
                .as_deref()
                .filter(|token| !token.trim().is_empty())
                .ok_or(CodexError::LoginExpired)?;
            let refreshed = refresh_credentials(&agent, refresh_token)?;
            apply_refreshed_credentials(&mut auth, refreshed)?;
            let response = fetch_usage(&agent, &auth.credentials)?;
            Ok(make_snapshot(response))
        }
        Err(error) => Err(error),
    }
}

fn http_agent() -> Agent {
    Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(30)))
        .http_status_as_error(false)
        .build()
        .into()
}

fn fetch_usage(agent: &Agent, credentials: &Credentials) -> Result<UsageResponse, CodexError> {
    let base_url = configured_base_url();
    let url = if base_url.contains("/backend-api") {
        format!("{}/wham/usage", base_url.trim_end_matches('/'))
    } else {
        format!("{}/api/codex/usage", base_url.trim_end_matches('/'))
    };

    let authorization = format!("Bearer {}", credentials.access_token);
    let mut request = agent
        .get(&url)
        .header("Authorization", &authorization)
        .header("Accept", "application/json")
        .header(
            "User-Agent",
            concat!("CodexBarNative/", env!("CARGO_PKG_VERSION")),
        );
    if let Some(account_id) = credentials.account_id.as_deref() {
        request = request.header("ChatGPT-Account-Id", account_id);
    }

    let mut response = request.call().map_err(|_| CodexError::Network)?;
    match response.status().as_u16() {
        200..=299 => response
            .body_mut()
            .read_json::<UsageResponse>()
            .map_err(|_| CodexError::InvalidResponse),
        401 | 403 => Err(CodexError::LoginExpired),
        status => Err(CodexError::HttpStatus(status)),
    }
}

fn refresh_credentials(agent: &Agent, refresh_token: &str) -> Result<RefreshResponse, CodexError> {
    let body = RefreshRequest {
        client_id: OAUTH_CLIENT_ID,
        grant_type: "refresh_token",
        refresh_token,
        scope: "openid profile email",
    };
    let mut response = agent
        .post(REFRESH_URL)
        .header("Content-Type", "application/json")
        .header("Accept", "application/json")
        .header(
            "User-Agent",
            concat!("CodexBarNative/", env!("CARGO_PKG_VERSION")),
        )
        .send_json(&body)
        .map_err(|_| CodexError::Network)?;

    match response.status().as_u16() {
        200..=299 => response
            .body_mut()
            .read_json::<RefreshResponse>()
            .map_err(|_| CodexError::InvalidResponse),
        400 | 401 | 403 => Err(CodexError::LoginExpired),
        status => Err(CodexError::HttpStatus(status)),
    }
}

fn make_snapshot(response: UsageResponse) -> CodexSnapshot {
    let (primary, secondary) = response
        .rate_limit
        .map(|limits| {
            (
                limits.primary_window.and_then(make_window),
                limits.secondary_window.and_then(make_window),
            )
        })
        .unwrap_or((None, None));
    let (session, weekly) = normalize_windows(primary, secondary);
    let credits = response.credits.and_then(|credits| {
        if credits.has_credits || credits.unlimited {
            credits.balance.as_ref().and_then(FlexibleNumber::value)
        } else {
            None
        }
    });

    CodexSnapshot {
        account_email: response.email.filter(|value| !value.trim().is_empty()),
        plan: response.plan_type.filter(|value| !value.trim().is_empty()),
        session,
        weekly,
        credits,
        fetched_at: Local::now(),
    }
}

fn make_window(window: ApiWindow) -> Option<UsageWindow> {
    let reset_at = Utc
        .timestamp_opt(window.reset_at, 0)
        .single()?
        .with_timezone(&Local);
    Some(UsageWindow {
        used_percent: window.used_percent.clamp(0.0, 100.0),
        window_seconds: window.limit_window_seconds,
        reset_at,
    })
}

fn normalize_windows(
    primary: Option<UsageWindow>,
    secondary: Option<UsageWindow>,
) -> (Option<UsageWindow>, Option<UsageWindow>) {
    match (primary, secondary) {
        (Some(primary), Some(secondary)) => match (role(&primary), role(&secondary)) {
            (WindowRole::Weekly, WindowRole::Session | WindowRole::Unknown) => {
                (Some(secondary), Some(primary))
            }
            _ => (Some(primary), Some(secondary)),
        },
        (Some(primary), None) => match role(&primary) {
            WindowRole::Weekly => (None, Some(primary)),
            WindowRole::Session | WindowRole::Unknown => (Some(primary), None),
        },
        (None, Some(secondary)) => match role(&secondary) {
            WindowRole::Weekly => (None, Some(secondary)),
            WindowRole::Session | WindowRole::Unknown => (Some(secondary), None),
        },
        (None, None) => (None, None),
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum WindowRole {
    Session,
    Weekly,
    Unknown,
}

fn role(window: &UsageWindow) -> WindowRole {
    match window.window_seconds {
        18_000 => WindowRole::Session,
        604_800 => WindowRole::Weekly,
        _ => WindowRole::Unknown,
    }
}

fn load_auth_document() -> Result<AuthDocument, CodexError> {
    let path = codex_home().join("auth.json");
    let data = fs::read(&path).map_err(|error| {
        if error.kind() == io::ErrorKind::NotFound {
            CodexError::LoginNotFound
        } else {
            CodexError::InvalidCredentials
        }
    })?;
    let value: Value = serde_json::from_slice(&data).map_err(|_| CodexError::InvalidCredentials)?;
    let credentials = credentials_from_value(&value)?;
    Ok(AuthDocument {
        path,
        value,
        credentials,
    })
}

fn credentials_from_value(value: &Value) -> Result<Credentials, CodexError> {
    let tokens = value
        .get("tokens")
        .and_then(Value::as_object)
        .ok_or(CodexError::InvalidCredentials)?;
    let access_token = string_field(tokens, "access_token", "accessToken")
        .ok_or(CodexError::InvalidCredentials)?;
    let refresh_token = string_field(tokens, "refresh_token", "refreshToken");
    let account_id = string_field(tokens, "account_id", "accountId");
    Ok(Credentials {
        access_token,
        refresh_token,
        account_id,
    })
}

fn string_field(
    values: &serde_json::Map<String, Value>,
    snake_case: &str,
    camel_case: &str,
) -> Option<String> {
    values
        .get(snake_case)
        .or_else(|| values.get(camel_case))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
}

fn apply_refreshed_credentials(
    auth: &mut AuthDocument,
    refreshed: RefreshResponse,
) -> Result<(), CodexError> {
    let tokens = auth
        .value
        .get_mut("tokens")
        .and_then(Value::as_object_mut)
        .ok_or(CodexError::InvalidCredentials)?;

    tokens.insert("access_token".into(), json!(refreshed.access_token));
    if let Some(refresh_token) = refreshed.refresh_token {
        tokens.insert("refresh_token".into(), json!(refresh_token));
    }
    if let Some(id_token) = refreshed.id_token {
        tokens.insert("id_token".into(), json!(id_token));
    }
    auth.value
        .as_object_mut()
        .ok_or(CodexError::InvalidCredentials)?
        .insert(
            "last_refresh".into(),
            json!(Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true)),
        );

    write_private_json(&auth.path, &auth.value)?;
    auth.credentials = credentials_from_value(&auth.value)?;
    Ok(())
}

fn write_private_json(path: &Path, value: &Value) -> Result<(), CodexError> {
    let parent = path.parent().ok_or(CodexError::CredentialWrite)?;
    fs::create_dir_all(parent).map_err(|_| CodexError::CredentialWrite)?;
    let temporary = parent.join(format!(
        ".{}.codexbar-{}.tmp",
        path.file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("auth.json"),
        std::process::id()
    ));

    let result = (|| -> Result<(), CodexError> {
        let mut file = private_file(&temporary)?;
        serde_json::to_writer_pretty(&mut file, value).map_err(|_| CodexError::CredentialWrite)?;
        file.write_all(b"\n")
            .map_err(|_| CodexError::CredentialWrite)?;
        file.sync_all().map_err(|_| CodexError::CredentialWrite)?;
        replace_file(&temporary, path)?;
        sync_directory(parent);
        Ok(())
    })();

    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

fn private_file(path: &Path) -> Result<File, CodexError> {
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    options.open(path).map_err(|_| CodexError::CredentialWrite)
}

#[cfg(unix)]
fn replace_file(source: &Path, destination: &Path) -> Result<(), CodexError> {
    fs::rename(source, destination).map_err(|_| CodexError::CredentialWrite)
}

#[cfg(windows)]
fn replace_file(source: &Path, destination: &Path) -> Result<(), CodexError> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Storage::FileSystem::{
        MOVEFILE_REPLACE_EXISTING, MOVEFILE_WRITE_THROUGH, MoveFileExW,
    };

    let source: Vec<u16> = source.as_os_str().encode_wide().chain(Some(0)).collect();
    let destination: Vec<u16> = destination
        .as_os_str()
        .encode_wide()
        .chain(Some(0))
        .collect();
    let flags = MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH;
    let succeeded = unsafe { MoveFileExW(source.as_ptr(), destination.as_ptr(), flags) };
    if succeeded == 0 {
        Err(CodexError::CredentialWrite)
    } else {
        Ok(())
    }
}

#[cfg(unix)]
fn sync_directory(path: &Path) {
    if let Ok(directory) = File::open(path) {
        let _ = directory.sync_all();
    }
}

#[cfg(not(unix))]
fn sync_directory(_path: &Path) {}

fn codex_home() -> PathBuf {
    if let Some(path) = env::var_os("CODEX_HOME").filter(|value| !value.is_empty()) {
        return PathBuf::from(path);
    }
    home_directory().join(".codex")
}

fn home_directory() -> PathBuf {
    env::var_os("HOME")
        .or_else(|| env::var_os("USERPROFILE"))
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."))
}

fn configured_base_url() -> String {
    let config_path = codex_home().join("config.toml");
    let configured = fs::read_to_string(config_path)
        .ok()
        .and_then(|contents| parse_base_url(&contents));
    normalize_base_url(configured.as_deref().unwrap_or(DEFAULT_BASE_URL))
}

fn parse_base_url(contents: &str) -> Option<String> {
    contents.lines().find_map(|raw_line| {
        let line = raw_line.split('#').next()?.trim();
        let (key, value) = line.split_once('=')?;
        if key.trim() != "chatgpt_base_url" {
            return None;
        }
        let value = value.trim().trim_matches(['\'', '"']).trim();
        (!value.is_empty()).then(|| value.to_owned())
    })
}

fn normalize_base_url(value: &str) -> String {
    let mut value = value.trim().trim_end_matches('/').to_owned();
    if value.is_empty() {
        value = DEFAULT_BASE_URL.into();
    }
    if (value.starts_with("https://chatgpt.com") || value.starts_with("https://chat.openai.com"))
        && !value.contains("/backend-api")
    {
        value.push_str("/backend-api");
    }
    value
}

#[cfg(test)]
mod tests {
    use super::*;

    fn window(seconds: u64, used: f64) -> UsageWindow {
        UsageWindow {
            used_percent: used,
            window_seconds: seconds,
            reset_at: Local.timestamp_opt(1_800_000_000, 0).single().unwrap(),
        }
    }

    #[test]
    fn weekly_primary_is_promoted_to_weekly_slot() {
        let (session, weekly) = normalize_windows(Some(window(604_800, 30.0)), None);
        assert!(session.is_none());
        assert_eq!(weekly.unwrap().remaining_percent(), 70.0);
    }

    #[test]
    fn reversed_session_and_weekly_windows_are_normalized() {
        let (session, weekly) =
            normalize_windows(Some(window(604_800, 40.0)), Some(window(18_000, 10.0)));
        assert_eq!(session.unwrap().window_seconds, 18_000);
        assert_eq!(weekly.unwrap().window_seconds, 604_800);
    }

    #[test]
    fn credentials_accept_camel_case_tokens() {
        let value = json!({
            "tokens": {
                "accessToken": "access",
                "refreshToken": "refresh",
                "accountId": "account"
            }
        });
        let credentials = credentials_from_value(&value).unwrap();
        assert_eq!(credentials.access_token, "access");
        assert_eq!(credentials.refresh_token.as_deref(), Some("refresh"));
        assert_eq!(credentials.account_id.as_deref(), Some("account"));
    }

    #[test]
    fn usage_response_accepts_string_credit_balance() {
        let response: UsageResponse = serde_json::from_value(json!({
            "email": "user@example.com",
            "plan_type": "plus",
            "rate_limit": {
                "primary_window": {
                    "used_percent": 29,
                    "limit_window_seconds": 604800,
                    "reset_at": 1800000000
                },
                "secondary_window": null
            },
            "credits": {
                "has_credits": true,
                "unlimited": false,
                "balance": "12.5"
            }
        }))
        .unwrap();
        let snapshot = make_snapshot(response);
        assert!(snapshot.session.is_none());
        assert_eq!(snapshot.weekly.unwrap().used_percent, 29.0);
        assert_eq!(snapshot.credits, Some(12.5));
    }

    #[test]
    fn chatgpt_origin_is_normalized_to_backend_api() {
        assert_eq!(
            normalize_base_url("https://chatgpt.com/"),
            "https://chatgpt.com/backend-api"
        );
    }
}

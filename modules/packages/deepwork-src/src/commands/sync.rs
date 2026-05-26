use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::config::{db_path, project_dirs};
use crate::daemon::{is_daemon_running, send_command};
use crate::timer::DaemonCommand;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SyncMode {
    Auto,
    Pull,
    Push,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct SyncState {
    remotes: HashMap<String, RemoteSyncState>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RemoteSyncState {
    last_local_hash: Option<String>,
    last_remote_hash: Option<String>,
}

fn sync_state_path() -> Result<PathBuf> {
    let dirs = project_dirs()?;
    Ok(dirs.config_dir().join("sync_state.json"))
}

fn load_state() -> Result<SyncState> {
    let path = sync_state_path()?;
    if !path.exists() {
        return Ok(SyncState::default());
    }
    let contents = fs::read_to_string(&path)
        .with_context(|| format!("Failed to read sync state from {:?}", path))?;
    let state: SyncState = serde_json::from_str(&contents)
        .with_context(|| format!("Failed to parse sync state from {:?}", path))?;
    Ok(state)
}

fn save_state(state: &SyncState) -> Result<()> {
    let path = sync_state_path()?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("Failed to create sync state dir: {:?}", parent))?;
    }

    let tmp = path.with_extension("json.tmp");
    fs::write(&tmp, serde_json::to_string_pretty(state)?)
        .with_context(|| format!("Failed to write sync state to {:?}", tmp))?;
    fs::rename(&tmp, &path).with_context(|| format!("Failed to move {:?} to {:?}", tmp, path))?;
    Ok(())
}

fn file_sha256(path: &Path) -> Result<Option<String>> {
    if !path.exists() {
        return Ok(None);
    }
    let bytes = fs::read(path).with_context(|| format!("Failed to read {:?}", path))?;
    let mut hasher = Sha256::new();
    hasher.update(&bytes);
    let digest = hasher.finalize();
    Ok(Some(hex::encode(digest)))
}

fn ssh(remote: &str, port: Option<u16>, remote_cmd: &str) -> Result<String> {
    let mut cmd = Command::new("ssh");
    if let Some(port) = port {
        cmd.arg("-p").arg(port.to_string());
    }

    // Important: `ssh host arg1 arg2 ...` is executed by the remote user's shell and does not
    // preserve argv boundaries; wrap the script as a single, safely-quoted `sh -c` string so
    // whitespace/newlines survive intact.
    let wrapped = format!("sh -c {}", sh_single_quote(remote_cmd));
    let output = cmd
        .arg(remote)
        .arg(wrapped)
        .output()
        .with_context(|| "Failed to run ssh (is it installed and configured?)")?;

    if !output.status.success() {
        anyhow::bail!(
            "ssh failed (exit {}): {}",
            output.status,
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

fn remote_home_dir(remote: &str, port: Option<u16>) -> Result<String> {
    let out = ssh(remote, port, r#"printf %s "$HOME""#).context("Failed to read remote $HOME")?;
    let home = out.trim().to_string();
    if home.is_empty() {
        anyhow::bail!("Remote $HOME is empty");
    }
    Ok(home)
}

fn expand_remote_path(remote_path: &str, remote_home: &str) -> Result<String> {
    if remote_path == "~" {
        return Ok(remote_home.to_string());
    }
    if let Some(suffix) = remote_path.strip_prefix("~/") {
        return Ok(format!("{}/{}", remote_home.trim_end_matches('/'), suffix));
    }
    if remote_path.starts_with('/') {
        return Ok(remote_path.to_string());
    }
    if remote_path.starts_with('~') {
        anyhow::bail!(
            "Unsupported remote path {remote_path:?}; use an absolute path or `~/...`"
        );
    }
    Ok(format!(
        "{}/{}",
        remote_home.trim_end_matches('/'),
        remote_path
    ))
}

fn sh_single_quote(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 2);
    out.push('\'');
    for ch in value.chars() {
        if ch == '\'' {
            out.push_str("'\"'\"'");
        } else {
            out.push(ch);
        }
    }
    out.push('\'');
    out
}

fn remote_path_prelude(remote_path: &str) -> String {
    let remote_path_q = sh_single_quote(remote_path);
    format!(
        r#"set -e
remote_path={remote_path_q}
case "$remote_path" in
  "~/"*) remote_path="$HOME/${{remote_path#~/}}" ;;
  "~") remote_path="$HOME" ;;
esac
"#
    )
}

fn remote_finalize_cmd(remote_path: &str) -> String {
    let prelude = remote_path_prelude(remote_path);
    format!(
        r#"{prelude}
remote_tmp="$remote_path.tmp"
mkdir -p "$(dirname "$remote_path")"
if [ -f "$remote_path" ]; then cp "$remote_path" "$remote_path.bak"; fi
mv "$remote_tmp" "$remote_path"
"#
    )
}

fn remote_sha256_cmd(remote_path: &str) -> String {
    let prelude = remote_path_prelude(remote_path);
    format!(
        r#"{prelude}
if [ ! -f "$remote_path" ]; then
  exit 0
fi
(sha256sum "$remote_path" 2>/dev/null || shasum -a 256 "$remote_path" 2>/dev/null) | awk '{{print $1}}'
"#
    )
}

fn scp_from(remote: &str, port: Option<u16>, remote_path: &str, local_path: &Path) -> Result<()> {
    let tmp = local_path.with_extension("db.tmp");
    let remote_spec = format!("{}:{}", remote, remote_path);
    let mut cmd = Command::new("scp");
    if let Some(port) = port {
        cmd.arg("-P").arg(port.to_string());
    }
    let status = cmd.arg(&remote_spec)
        .arg(&tmp)
        .status()
        .with_context(|| "Failed to run scp (is it installed and configured?)")?;
    if !status.success() {
        anyhow::bail!("scp pull failed (exit {})", status);
    }

    if local_path.exists() {
        let backup = local_path.with_extension("db.bak");
        fs::copy(local_path, &backup)
            .with_context(|| format!("Failed to create backup at {:?}", backup))?;
    }

    fs::rename(&tmp, local_path).with_context(|| format!("Failed to move {:?} to {:?}", tmp, local_path))?;
    Ok(())
}

fn scp_to(local_path: &Path, remote: &str, port: Option<u16>, remote_path: &str) -> Result<()> {
    let remote_tmp = format!("{}.tmp", remote_path);
    let remote_spec_tmp = format!("{}:{}", remote, remote_tmp);

    let mut cmd = Command::new("scp");
    if let Some(port) = port {
        cmd.arg("-P").arg(port.to_string());
    }
    let status = cmd.arg(local_path)
        .arg(&remote_spec_tmp)
        .status()
        .with_context(|| "Failed to run scp (is it installed and configured?)")?;
    if !status.success() {
        anyhow::bail!("scp push failed (exit {})", status);
    }

    // Best-effort remote backup, then atomic-ish replace.
    let remote_cmd = remote_finalize_cmd(remote_path);
    ssh(remote, port, &remote_cmd).context("Failed to finalize file on remote")?;
    Ok(())
}

fn remote_sha256(remote: &str, port: Option<u16>, remote_path: &str) -> Result<Option<String>> {
    // Output: hash or empty.
    let cmd = remote_sha256_cmd(remote_path);
    let out = ssh(remote, port, &cmd).context("Failed to compute remote hash")?;
    let hash = out.trim().to_string();
    if hash.is_empty() {
        Ok(None)
    } else {
        Ok(Some(hash))
    }
}

pub fn sync(
    remote: &str,
    port: Option<u16>,
    remote_path: Option<&str>,
    mode: SyncMode,
    force: bool,
    allow_running: bool,
) -> Result<()> {
    if is_daemon_running() && !allow_running {
        anyhow::bail!(
            "Refusing to sync while daemon is running (stop the timer first or pass --allow-running)"
        );
    }

    let local_db = db_path()?;
    let remote_path = remote_path.unwrap_or("~/.local/share/deepwork/deepwork.db");
    let remote_home = remote_home_dir(remote, port)?;
    let remote_path_abs = expand_remote_path(remote_path, &remote_home)?;

    let mut state = load_state()?;
    let remote_key = format!("{}:{}", remote, remote_path);
    let entry = state.remotes.get(&remote_key).cloned().unwrap_or(RemoteSyncState {
        last_local_hash: None,
        last_remote_hash: None,
    });

    let local_hash = file_sha256(&local_db)?;
    let remote_hash = remote_sha256(remote, port, &remote_path_abs)?;

    let local_changed = local_hash != entry.last_local_hash;
    let remote_changed = remote_hash != entry.last_remote_hash;

    let decide_action = || -> Result<SyncMode> {
        if mode != SyncMode::Auto {
            return Ok(mode);
        }
        match (local_changed, remote_changed) {
            (false, false) => Ok(SyncMode::Auto),
            (true, false) => Ok(SyncMode::Push),
            (false, true) => Ok(SyncMode::Pull),
            (true, true) => {
                if local_hash == remote_hash {
                    Ok(SyncMode::Auto)
                } else {
                    anyhow::bail!(
                        "Both local and remote changed since last sync (conflict). Re-run with --pull or --push plus --force to pick a side."
                    )
                }
            }
        }
    };

    let action = match decide_action() {
        Ok(a) => a,
        Err(e) if force && mode != SyncMode::Auto => mode,
        Err(e) => return Err(e),
    };

    match action {
        SyncMode::Auto => {
            println!("Already in sync.");
        }
        SyncMode::Pull => {
            scp_from(remote, port, &remote_path_abs, &local_db)
                .with_context(|| format!("Failed to pull {} to {:?}", remote_key, local_db))?;
            println!("Pulled database from {}.", remote_key);
            // Tell local daemon to reload its database connection
            if is_daemon_running() {
                let _ = send_command(DaemonCommand::ReloadDatabase);
            }
        }
        SyncMode::Push => {
            if !local_db.exists() {
                anyhow::bail!("Local database does not exist at {:?}", local_db);
            }
            scp_to(&local_db, remote, port, &remote_path_abs)
                .with_context(|| format!("Failed to push {:?} to {}", local_db, remote_key))?;
            println!("Pushed database to {}.", remote_key);
            // Tell the remote daemon to reload its database connection
            match ssh(remote, port, "deepwork refresh 2>/dev/null") {
                Ok(_) => println!("Remote daemon reloaded."),
                Err(_) => {} // Daemon not running on remote, that's fine
            }
        }
    }

    // Refresh hashes and persist state.
    let new_local_hash = file_sha256(&local_db)?;
    let new_remote_hash = remote_sha256(remote, port, &remote_path_abs)?;
    state.remotes.insert(
        remote_key,
        RemoteSyncState {
            last_local_hash: new_local_hash,
            last_remote_hash: new_remote_hash,
        },
    );
    save_state(&state)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn expand_remote_path_expands_tilde_with_remote_home() {
        assert_eq!(
            expand_remote_path("~/.local/share/deepwork/deepwork.db", "/home/jack").unwrap(),
            "/home/jack/.local/share/deepwork/deepwork.db"
        );
        assert_eq!(expand_remote_path("~", "/home/jack").unwrap(), "/home/jack");
    }

    #[test]
    fn remote_finalize_expands_tilde_safely() {
        let cmd = remote_finalize_cmd("~/.local/share/deepwork/deepwork.db");
        assert!(cmd.contains("remote_path='~/.local/share/deepwork/deepwork.db'"));
        assert!(cmd.contains("case \"$remote_path\" in"));
        assert!(cmd.contains("remote_tmp=\"$remote_path.tmp\""));
        assert!(!cmd.contains("~/.local/share/deepwork/deepwork.db.tmp"));
    }

    #[test]
    fn remote_sha256_uses_expanded_remote_path_var() {
        let cmd = remote_sha256_cmd("~/.local/share/deepwork/deepwork.db");
        assert!(cmd.contains("if [ ! -f \"$remote_path\" ]; then"));
        assert!(cmd.contains("sha256sum \"$remote_path\""));
        assert!(!cmd.contains("sha256sum \"~/.local/share"));
    }

    #[test]
    fn sh_single_quote_escapes_single_quotes() {
        assert_eq!(sh_single_quote("a'b"), "'a'\"'\"'b'");
    }
}

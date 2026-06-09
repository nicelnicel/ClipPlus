use anyhow::{bail, Result};
use clipplus_diagnostics::status::RuntimeStatus;
use serde_json::json;

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let Some(command) = args.next() else {
        bail!("用法: clipplus-cli status | diagnose");
    };

    match command.as_str() {
        "status" => {
            let status = RuntimeStatus::new_for_test();
            println!("{}", serde_json::to_string_pretty(&status)?);
        }
        "diagnose" => {
            let diagnostics = json!({
                "network": "not_started",
                "clipboard": "not_started",
                "file_transfer": "not_started",
            });
            println!("{}", serde_json::to_string_pretty(&diagnostics)?);
        }
        command => bail!("未知命令: {command}"),
    }

    Ok(())
}

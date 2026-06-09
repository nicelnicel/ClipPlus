use crate::config::SyncSettings;
use crate::sync::{LoopGuard, SyncPolicy};

#[derive(Debug, Clone)]
pub struct CoreService {
    settings: SyncSettings,
    loop_guard: LoopGuard,
}

impl CoreService {
    pub fn new(settings: SyncSettings) -> Self {
        Self {
            settings,
            loop_guard: LoopGuard::default(),
        }
    }

    pub fn policy(&self) -> SyncPolicy {
        SyncPolicy::new(self.settings.clone())
    }

    pub fn loop_guard(&self) -> &LoopGuard {
        &self.loop_guard
    }
}

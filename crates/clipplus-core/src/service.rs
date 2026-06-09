use std::sync::{Arc, Mutex, MutexGuard};

use crate::config::SyncSettings;
use crate::event::ClipboardEvent;
use crate::sync::{LoopGuard, SyncPolicy};
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct CoreService {
    state: Arc<Mutex<CoreServiceState>>,
}

#[derive(Debug)]
struct CoreServiceState {
    settings: SyncSettings,
    loop_guard: LoopGuard,
}

impl CoreService {
    pub fn new(settings: SyncSettings) -> Self {
        Self {
            state: Arc::new(Mutex::new(CoreServiceState {
                settings,
                loop_guard: LoopGuard::default(),
            })),
        }
    }

    pub fn policy(&self) -> SyncPolicy {
        SyncPolicy::new(self.lock_state().settings.clone())
    }

    pub fn loop_guard(&self) -> LoopGuard {
        self.lock_state().loop_guard.clone()
    }

    pub fn mark_remote_write(&self, event: &ClipboardEvent) {
        self.lock_state().loop_guard.mark_remote_write(event);
    }

    pub fn should_ignore_local_change(&self, event: &ClipboardEvent) -> bool {
        self.lock_state()
            .loop_guard
            .should_ignore_local_change(event)
    }

    pub fn mark_processed(&self, event_id: Uuid) {
        self.lock_state().loop_guard.mark_processed(event_id);
    }

    pub fn has_processed(&self, event_id: Uuid) -> bool {
        self.lock_state().loop_guard.has_processed(event_id)
    }

    pub fn update_settings(&self, settings: SyncSettings) {
        self.lock_state().settings = settings;
    }

    fn lock_state(&self) -> MutexGuard<'_, CoreServiceState> {
        self.state
            .lock()
            .expect("core service state mutex poisoned")
    }
}

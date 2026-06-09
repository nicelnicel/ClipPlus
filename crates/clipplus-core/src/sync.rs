use std::collections::VecDeque;

use uuid::Uuid;

use crate::config::SyncSettings;
use crate::event::ClipboardEvent;

const DEFAULT_LOOP_GUARD_CAPACITY: usize = 128;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SyncDecision {
    Allowed,
    Blocked(&'static str),
}

#[derive(Debug, Clone)]
pub struct SyncPolicy {
    settings: SyncSettings,
}

impl SyncPolicy {
    pub fn new(settings: SyncSettings) -> Self {
        Self { settings }
    }

    pub fn can_publish(&self, event: &ClipboardEvent) -> SyncDecision {
        if !self.settings.sharing_enabled {
            return SyncDecision::Blocked("sharing_disabled");
        }

        if !self.settings.content.allows(event) {
            return SyncDecision::Blocked("content_type_disabled_or_too_large");
        }

        SyncDecision::Allowed
    }
}

#[derive(Debug, Clone)]
pub struct LoopGuard {
    recent_remote_writes: VecDeque<Uuid>,
    recent_processed: VecDeque<Uuid>,
    capacity: usize,
}

impl Default for LoopGuard {
    fn default() -> Self {
        Self {
            recent_remote_writes: VecDeque::new(),
            recent_processed: VecDeque::new(),
            capacity: DEFAULT_LOOP_GUARD_CAPACITY,
        }
    }
}

impl LoopGuard {
    pub fn mark_remote_write(&mut self, event_id: Uuid) {
        Self::push_lru(&mut self.recent_remote_writes, self.capacity, event_id);
    }

    pub fn should_ignore_local_change(&self, event_id: Uuid) -> bool {
        self.recent_remote_writes.contains(&event_id)
    }

    pub fn mark_processed(&mut self, event_id: Uuid) {
        Self::push_lru(&mut self.recent_processed, self.capacity, event_id);
    }

    pub fn has_processed(&self, event_id: Uuid) -> bool {
        self.recent_processed.contains(&event_id)
    }

    fn push_lru(queue: &mut VecDeque<Uuid>, capacity: usize, event_id: Uuid) {
        if queue.contains(&event_id) {
            return;
        }

        queue.push_back(event_id);

        while queue.len() > capacity {
            queue.pop_front();
        }
    }
}

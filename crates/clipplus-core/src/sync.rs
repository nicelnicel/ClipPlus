use std::collections::{hash_map::DefaultHasher, VecDeque};
use std::hash::{Hash, Hasher};

use uuid::Uuid;

use crate::config::SyncSettings;
use crate::event::{ClipboardEvent, ClipboardPayload, ImageFormat};

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
    recent_remote_writes: VecDeque<RemoteWriteRecord>,
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
    pub fn mark_remote_write(&mut self, event: &ClipboardEvent) {
        let record = RemoteWriteRecord::from_event(event);

        Self::push_lru_by(
            &mut self.recent_remote_writes,
            self.capacity,
            record,
            |entry| entry.event_id == record.event_id || entry.payload == record.payload,
        );
    }

    pub fn should_ignore_local_change(&self, event: &ClipboardEvent) -> bool {
        let payload = PayloadFingerprint::from_event(event);

        self.recent_remote_writes
            .iter()
            .any(|entry| entry.event_id == event.event_id || entry.payload == payload)
    }

    pub fn mark_processed(&mut self, event_id: Uuid) {
        Self::push_lru_by(
            &mut self.recent_processed,
            self.capacity,
            event_id,
            |entry| *entry == event_id,
        );
    }

    pub fn has_processed(&self, event_id: Uuid) -> bool {
        self.recent_processed.contains(&event_id)
    }

    fn push_lru_by<T>(
        queue: &mut VecDeque<T>,
        capacity: usize,
        item: T,
        matches: impl Fn(&T) -> bool,
    ) {
        if let Some(position) = queue.iter().position(matches) {
            queue.remove(position);
        }

        queue.push_back(item);

        while queue.len() > capacity {
            queue.pop_front();
        }
    }
}

#[derive(Debug, Clone, Copy)]
struct RemoteWriteRecord {
    event_id: Uuid,
    payload: PayloadFingerprint,
}

impl RemoteWriteRecord {
    fn from_event(event: &ClipboardEvent) -> Self {
        Self {
            event_id: event.event_id,
            payload: PayloadFingerprint::from_event(event),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct PayloadFingerprint(u64);

impl PayloadFingerprint {
    fn from_event(event: &ClipboardEvent) -> Self {
        let mut hasher = DefaultHasher::new();

        match &event.payload {
            ClipboardPayload::Text { text, byte_size } => {
                "text".hash(&mut hasher);
                text.hash(&mut hasher);
                byte_size.hash(&mut hasher);
            }
            ClipboardPayload::Image {
                format,
                byte_size,
                width,
                height,
                content_hash,
            } => {
                "image".hash(&mut hasher);
                image_format_key(*format).hash(&mut hasher);
                byte_size.hash(&mut hasher);
                width.hash(&mut hasher);
                height.hash(&mut hasher);
                content_hash.hash(&mut hasher);
            }
            ClipboardPayload::FileList { files, .. } => {
                "file_list".hash(&mut hasher);
                files.len().hash(&mut hasher);

                let mut file_features = files
                    .iter()
                    .map(|file| {
                        (
                            file.name.as_str(),
                            file.size,
                            file.modified_at.timestamp(),
                            file.modified_at.timestamp_subsec_nanos(),
                            file.content_hash.as_str(),
                            file.source_relative_path.as_str(),
                        )
                    })
                    .collect::<Vec<_>>();
                file_features.sort_unstable();

                for feature in file_features {
                    feature.hash(&mut hasher);
                }
            }
        }

        Self(hasher.finish())
    }
}

fn image_format_key(format: ImageFormat) -> u8 {
    match format {
        ImageFormat::Png => 0,
        ImageFormat::Jpeg => 1,
        ImageFormat::Tiff => 2,
    }
}

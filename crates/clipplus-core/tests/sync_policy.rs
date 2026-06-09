use chrono::Utc;
use clipplus_core::config::{ContentTypeSettings, ImageLimit, SyncSettings};
use clipplus_core::device::{DeviceId, DeviceState, PeerDevice, Platform};
use clipplus_core::event::{ClipboardEvent, ClipboardPayload, FileItem, ImageFormat};
use clipplus_core::service::CoreService;
use clipplus_core::sync::{LoopGuard, SyncDecision, SyncPolicy};
use uuid::Uuid;

fn test_device_id() -> DeviceId {
    DeviceId::new("test-device").unwrap()
}

fn text_event(text: &str) -> ClipboardEvent {
    ClipboardEvent::new_text(test_device_id(), text)
}

fn image_event(byte_size: usize) -> ClipboardEvent {
    ClipboardEvent::new_image_metadata(
        test_device_id(),
        ImageFormat::Png,
        byte_size,
        100,
        100,
        format!("test-image-{byte_size}"),
    )
}

fn file_list_event() -> ClipboardEvent {
    ClipboardEvent {
        event_id: Uuid::new_v4(),
        origin_device_id: test_device_id(),
        created_at: Utc::now(),
        payload: ClipboardPayload::FileList {
            transfer_id: Uuid::new_v4(),
            files: vec![FileItem {
                file_id: Uuid::new_v4(),
                name: "document.txt".to_string(),
                size: 12,
                modified_at: Utc::now(),
                content_hash: "test-file".to_string(),
                source_relative_path: "document.txt".to_string(),
            }],
        },
    }
}

#[test]
fn default_settings_enable_text_image_and_file() {
    let settings = SyncSettings::default();

    assert!(settings.sharing_enabled);
    assert!(settings.content.text);
    assert!(settings.content.image);
    assert!(settings.content.file);
    assert_eq!(settings.content.image_limit, ImageLimit::Mb20);
}

#[test]
fn paused_device_is_not_eligible_for_sync() {
    let peer = PeerDevice::new(
        DeviceId::new("peer-a").unwrap(),
        "Windows-PC",
        Platform::Windows,
        DeviceState::Paused,
    );

    assert!(!peer.can_sync());
}

#[test]
fn trusted_device_is_eligible_for_sync() {
    let peer = PeerDevice::new(
        DeviceId::new("peer-a").unwrap(),
        "Windows-PC",
        Platform::Windows,
        DeviceState::Trusted,
    );

    assert!(peer.can_sync());
}

#[test]
fn peer_device_trust_actions_update_sync_eligibility() {
    let mut peer = PeerDevice::new(
        DeviceId::new("peer-a").unwrap(),
        "Windows-PC",
        Platform::Windows,
        DeviceState::Pending,
    );

    peer.approve();
    assert!(peer.can_sync());

    peer.pause();
    assert!(!peer.can_sync());

    peer.approve();
    assert!(peer.can_sync());

    peer.reject();
    assert!(!peer.can_sync());
}

#[test]
fn device_id_trims_runtime_values() {
    let id = DeviceId::new(" peer-a ").unwrap();

    assert_eq!(id.as_str(), "peer-a");
}

#[test]
fn device_id_rejects_blank_values() {
    assert!(DeviceId::new("   ").is_err());
}

#[test]
fn device_id_parse_trims_runtime_values() {
    let id = " peer-a ".parse::<DeviceId>().unwrap();

    assert_eq!(id.as_str(), "peer-a");
}

#[test]
fn device_id_parse_rejects_blank_values() {
    assert!("   ".parse::<DeviceId>().is_err());
}

#[test]
fn device_id_deserialization_trims_runtime_values() {
    let id = serde_json::from_str::<DeviceId>("\" peer-a \"").unwrap();

    assert_eq!(id.as_str(), "peer-a");
}

#[test]
fn device_id_deserialization_rejects_blank_values() {
    assert!(serde_json::from_str::<DeviceId>("\"   \"").is_err());
}

#[test]
fn image_payload_respects_configured_limit() {
    let content = ContentTypeSettings {
        text: true,
        image: true,
        file: true,
        image_limit: ImageLimit::Mb5,
    };
    let event = image_event(6 * 1024 * 1024);

    assert!(!content.allows(&event));
}

#[test]
fn image_payload_is_allowed_at_configured_limit() {
    let content = ContentTypeSettings {
        text: true,
        image: true,
        file: true,
        image_limit: ImageLimit::Mb5,
    };
    let event = image_event(5 * 1024 * 1024);

    assert!(content.allows(&event));
}

#[test]
fn image_payload_is_rejected_when_image_sync_is_disabled() {
    let content = ContentTypeSettings {
        text: true,
        image: false,
        file: true,
        image_limit: ImageLimit::Mb20,
    };
    let event = image_event(1024);

    assert!(!content.allows(&event));
}

#[test]
fn text_event_is_allowed_when_text_sync_is_enabled() {
    let content = ContentTypeSettings {
        text: true,
        image: false,
        file: false,
        image_limit: ImageLimit::Mb20,
    };
    let event = text_event("hello");

    assert!(matches!(&event.payload, ClipboardPayload::Text { .. }));
    assert!(content.allows(&event));
}

#[test]
fn text_event_is_rejected_when_text_sync_is_disabled() {
    let content = ContentTypeSettings {
        text: false,
        image: true,
        file: true,
        image_limit: ImageLimit::Mb20,
    };
    let event = text_event("hello");

    assert!(!content.allows(&event));
}

#[test]
fn file_list_is_rejected_when_file_sync_is_disabled() {
    let content = ContentTypeSettings {
        text: true,
        image: true,
        file: false,
        image_limit: ImageLimit::Mb20,
    };
    let event = file_list_event();

    assert!(!content.allows(&event));
}

#[test]
fn disabled_global_sharing_blocks_publish() {
    let settings = SyncSettings {
        sharing_enabled: false,
        ..SyncSettings::default()
    };
    let policy = SyncPolicy::new(settings);
    let event = text_event("hello");

    assert_eq!(
        policy.can_publish(&event),
        SyncDecision::Blocked("sharing_disabled")
    );
}

#[test]
fn default_policy_allows_text_publish() {
    let policy = SyncPolicy::new(SyncSettings::default());
    let event = text_event("hello");

    assert_eq!(policy.can_publish(&event), SyncDecision::Allowed);
}

#[test]
fn policy_blocks_text_when_text_sync_is_disabled() {
    let settings = SyncSettings {
        content: ContentTypeSettings {
            text: false,
            ..ContentTypeSettings::default()
        },
        ..SyncSettings::default()
    };
    let policy = SyncPolicy::new(settings);
    let event = text_event("hello");

    assert_eq!(
        policy.can_publish(&event),
        SyncDecision::Blocked("content_type_disabled_or_too_large")
    );
}

#[test]
fn policy_blocks_image_when_image_sync_is_disabled() {
    let settings = SyncSettings {
        content: ContentTypeSettings {
            image: false,
            ..ContentTypeSettings::default()
        },
        ..SyncSettings::default()
    };
    let policy = SyncPolicy::new(settings);
    let event = image_event(1024);

    assert_eq!(
        policy.can_publish(&event),
        SyncDecision::Blocked("content_type_disabled_or_too_large")
    );
}

#[test]
fn policy_blocks_image_when_image_is_too_large() {
    let settings = SyncSettings {
        content: ContentTypeSettings {
            image_limit: ImageLimit::Mb5,
            ..ContentTypeSettings::default()
        },
        ..SyncSettings::default()
    };
    let policy = SyncPolicy::new(settings);
    let event = image_event(6 * 1024 * 1024);

    assert_eq!(
        policy.can_publish(&event),
        SyncDecision::Blocked("content_type_disabled_or_too_large")
    );
}

#[test]
fn policy_blocks_file_list_when_file_sync_is_disabled() {
    let settings = SyncSettings {
        content: ContentTypeSettings {
            file: false,
            ..ContentTypeSettings::default()
        },
        ..SyncSettings::default()
    };
    let policy = SyncPolicy::new(settings);
    let event = file_list_event();

    assert_eq!(
        policy.can_publish(&event),
        SyncDecision::Blocked("content_type_disabled_or_too_large")
    );
}

#[test]
fn remote_write_guard_blocks_loopback() {
    let event = text_event("hello");
    let mut guard = LoopGuard::default();

    guard.mark_remote_write(&event);

    assert!(guard.should_ignore_local_change(&event));
}

#[test]
fn remote_write_guard_matches_same_payload_with_new_event_id() {
    let remote = text_event("hello");
    let same_payload_local = text_event("hello");
    let different_payload_local = text_event("different");
    let mut guard = LoopGuard::default();

    guard.mark_remote_write(&remote);

    assert!(guard.should_ignore_local_change(&same_payload_local));
    assert!(!guard.should_ignore_local_change(&different_payload_local));
}

#[test]
fn remote_write_lru_refreshes_repeated_payload() {
    let mut guard = LoopGuard::default();
    let events = (0..128)
        .map(|index| text_event(&format!("payload-{index}")))
        .collect::<Vec<_>>();

    for event in &events {
        guard.mark_remote_write(event);
    }

    guard.mark_remote_write(&events[0]);

    let newest = text_event("payload-128");
    guard.mark_remote_write(&newest);

    assert!(guard.should_ignore_local_change(&events[0]));
    assert!(!guard.should_ignore_local_change(&events[1]));
    assert!(guard.should_ignore_local_change(&newest));
}

#[test]
fn remote_write_and_processed_caches_do_not_pollute_each_other() {
    let remote = text_event("remote");
    let processed = text_event("processed");
    let mut guard = LoopGuard::default();

    guard.mark_remote_write(&remote);
    guard.mark_processed(processed.event_id);

    assert!(!guard.has_processed(remote.event_id));
    assert!(!guard.should_ignore_local_change(&processed));
    assert!(guard.has_processed(processed.event_id));
    assert!(guard.should_ignore_local_change(&remote));
}

#[test]
fn processed_event_is_not_processed_twice() {
    let event = text_event("hello");
    let mut guard = LoopGuard::default();

    assert!(!guard.has_processed(event.event_id));
    guard.mark_processed(event.event_id);
    assert!(guard.has_processed(event.event_id));
}

#[test]
fn processed_lru_refreshes_repeated_event_id() {
    let mut guard = LoopGuard::default();
    let events = (0..128)
        .map(|index| text_event(&format!("processed-{index}")))
        .collect::<Vec<_>>();

    for event in &events {
        guard.mark_processed(event.event_id);
    }

    guard.mark_processed(events[0].event_id);

    let newest = text_event("processed-128");
    guard.mark_processed(newest.event_id);

    assert!(guard.has_processed(events[0].event_id));
    assert!(!guard.has_processed(events[1].event_id));
    assert!(guard.has_processed(newest.event_id));
}

#[test]
fn cloned_service_shares_loop_guard_state() {
    let service = CoreService::new(SyncSettings::default());
    let service_b = service.clone();
    let remote = text_event("hello");
    let same_payload_local = text_event("hello");

    service.mark_remote_write(&remote);

    assert!(service_b.should_ignore_local_change(&same_payload_local));
}

#[test]
fn service_policy_uses_updated_settings_snapshot() {
    let service = CoreService::new(SyncSettings::default());
    let event = text_event("hello");

    assert_eq!(service.policy().can_publish(&event), SyncDecision::Allowed);

    service.update_settings(SyncSettings {
        sharing_enabled: false,
        ..SyncSettings::default()
    });

    assert_eq!(
        service.policy().can_publish(&event),
        SyncDecision::Blocked("sharing_disabled")
    );
}

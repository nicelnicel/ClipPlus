use clipplus_core::config::{ContentTypeSettings, ImageLimit, SyncSettings};
use clipplus_core::device::{DeviceId, DeviceState, PeerDevice, Platform};
use clipplus_core::event::{ClipboardEvent, ClipboardPayload};

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
        DeviceId::from_static("peer-a"),
        "Windows-PC",
        Platform::Windows,
        DeviceState::Paused,
    );

    assert!(!peer.can_sync());
}

#[test]
fn image_payload_respects_configured_limit() {
    let content = ContentTypeSettings {
        text: true,
        image: true,
        file: true,
        image_limit: ImageLimit::Mb5,
    };
    let event = ClipboardEvent::image_for_test(6 * 1024 * 1024);

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
    let event = ClipboardEvent::text_for_test("hello");

    assert!(matches!(event.payload, ClipboardPayload::Text { .. }));
    assert!(content.allows(&event));
}

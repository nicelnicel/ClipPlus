use clipplus_crypto::identity::DeviceIdentity;
use clipplus_crypto::key::SharedKeyMaterial;

#[test]
fn same_key_derives_same_group_id() {
    let left = SharedKeyMaterial::derive("friend-lan-key").unwrap();
    let right = SharedKeyMaterial::derive("friend-lan-key").unwrap();

    assert_eq!(left.group_id, right.group_id);
    assert_ne!(left.group_id, "friend-lan-key");
}

#[test]
fn different_keys_derive_different_group_ids() {
    let left = SharedKeyMaterial::derive("friend-lan-key").unwrap();
    let right = SharedKeyMaterial::derive("other-lan-key").unwrap();

    assert_ne!(left.group_id, right.group_id);
}

#[test]
fn empty_key_is_rejected() {
    let result = SharedKeyMaterial::derive("   ");

    assert!(result.is_err());
}

#[test]
fn device_identity_has_stable_fingerprint_prefix() {
    let identity = DeviceIdentity::generate("MacBook Pro", "macos");

    assert_eq!(identity.fingerprint_short().len(), 9);
    assert!(identity.fingerprint_short().contains('-'));
}

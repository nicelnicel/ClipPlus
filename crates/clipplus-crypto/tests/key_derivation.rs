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
fn same_key_with_whitespace_derives_same_group_id() {
    let left = SharedKeyMaterial::derive(" friend-lan-key ").unwrap();
    let right = SharedKeyMaterial::derive("friend-lan-key").unwrap();

    assert_eq!(left.group_id, right.group_id);
}

#[test]
fn different_keys_derive_different_group_ids() {
    let left = SharedKeyMaterial::derive("friend-lan-key").unwrap();
    let right = SharedKeyMaterial::derive("other-lan-key").unwrap();

    assert_ne!(left.group_id, right.group_id);
}

#[test]
fn verifier_is_stable_distinct_and_key_specific() {
    let left = SharedKeyMaterial::derive("friend-lan-key").unwrap();
    let same = SharedKeyMaterial::derive("friend-lan-key").unwrap();
    let other = SharedKeyMaterial::derive("other-lan-key").unwrap();

    assert_eq!(left.verifier, same.verifier);
    assert_ne!(left.verifier, other.verifier);
    assert_ne!(left.group_id, left.verifier);
}

#[test]
fn shared_key_debug_redacts_verifier() {
    let material = SharedKeyMaterial::derive("friend-lan-key").unwrap();
    let debug = format!("{:?}", material);

    assert!(debug.contains(&material.group_id));
    assert!(!debug.contains(&material.verifier));
    assert!(debug.contains("<redacted>"));
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

#[test]
fn device_identity_exposes_non_empty_key_material() {
    let identity = DeviceIdentity::generate("MacBook Pro", "macos");

    assert!(!identity.public_key.is_empty());
    assert!(!identity.private_key_material_for_local_storage().is_empty());
}

#[test]
fn device_identity_debug_redacts_private_key() {
    let identity = DeviceIdentity::generate("MacBook Pro", "macos");
    let private_key = identity.private_key_material_for_local_storage();
    let debug = format!("{:?}", identity);

    assert!(debug.contains(&identity.public_key));
    assert!(!debug.contains(private_key));
    assert!(debug.contains("<redacted>"));
}

#[test]
fn device_identity_fingerprint_is_stable() {
    let identity = DeviceIdentity::generate("MacBook Pro", "macos");

    assert_eq!(identity.fingerprint_short(), identity.fingerprint_short());
}

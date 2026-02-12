# Security Model

## Key Storage

- iOS: Keychain
- Android: Keystore
- Flutter: `flutter_secure_storage`

## Local Database

- Hive with encrypted boxes for chats and media metadata.
- Sensitive tokens and MTProto auth keys never stored in plain text.

## Session Protection

- Device-bound encryption keys.
- Auto-lock with biometric or passcode.
- Brute-force protection for login attempts.

## Network

- MTProto transport security.
- Certificate pinning (optional) for gateway backend.
- Strict TLS for AI API calls.


## 2024-06-13 - [AppleScript Command Injection via Bundle Path]
**Vulnerability:** Command injection vulnerability in `SettingsView.swift` when constructing AppleScript `do shell script` commands containing dynamic properties like the application bundle path (`Bundle.main.url(forResource:...)`). If a user renames the app or places it in a path with bash control characters like `; rm -rf /`, it would be executed as root since it uses "with administrator privileges".
**Learning:** Even internal app structures like bundle paths are user-controllable (since a user can rename the `.app` or place it anywhere) and must be treated as untrusted input. Directly interpolating strings into `do shell script` is inherently dangerous because it undergoes dual evaluation (once by AppleScript and once by `sh`).
**Prevention:** Always escape variables for the target shell (e.g., wrap in single quotes and replace `'` with `'\\''` for bash) before inclusion, and critically, escape backslashes and double quotes when embedding the command into an AppleScript string literal.

## 2024-06-14 - [Insecure Configuration Storage Permissions]
**Vulnerability:** `containers.json` file which stores container environment variables (potentially containing secrets like API keys or database passwords) was written with default permissions, making it world-readable.
**Learning:** Automatically serialized configuration files are prone to information exposure if they include sensitive values.
**Prevention:** Explicitly enforce restrictive file permissions (e.g., `0600`) and use safe file protection options (`.completeFileProtection`) when writing files that contain potentially sensitive user configuration or environmental data.

## 2024-06-13 - [Path Traversal in Compose Service Names]
**Vulnerability:** Path traversal vulnerability in `ContainerDaemon.swift` when extracting rootfs for Compose pods. The `service.name` from the parsed YAML is used directly in `URL.appendingPathComponent`, allowing a malicious `docker-compose.yml` with a service name like `../../../tmp/hacked` to overwrite files outside the intended container directory.
**Learning:** Keys in user-provided configuration files (like YAML dictionaries) are untrusted input just like values. They must be validated or sanitized before being used in file system operations.
**Prevention:** Always validate service names and other user-provided identifiers against a strict allowlist regex (e.g., `^[a-zA-Z0-9_-]+$`) during parsing, before they reach the core logic.

## 2025-02-28 - Secure File Writing for Daemon Persistence
**Vulnerability:** Weak file writing options and default permissions for daemon configuration files.
**Learning:** Using `data.write(to:)` without options is not atomic, leading to race conditions and corrupted reads. Also, storing configurations (with sensitive variables like environment variables) with default permissions exposes data to unauthorized read access. Note that `.completeFileProtection` should be avoided for daemons accessing files during screen locks.
**Prevention:** Always use `options: [.atomic]` for file writes. Explicitly enforce secure file permissions using `FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath:)`.
## 2026-06-13 - [Insecure Log File Writes]
**Vulnerability:** Weak file writing options and default permissions for daemon log files (`daemon.log`).
**Learning:** Writing sensitive logs using `data.write(to:)` without options leaves the file vulnerable to race conditions and sets default permissions, exposing potentially sensitive daemon metadata to unauthorized reads.
**Prevention:** Always use `options: [.atomic]` when writing to log files to prevent partial reads or race conditions. Follow up with explicit POSIX permission restrictions (e.g., `0o600`) using `FileManager.default.setAttributes`.

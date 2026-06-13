## 2024-06-13 - [AppleScript Command Injection via Bundle Path]
**Vulnerability:** Command injection vulnerability in `SettingsView.swift` when constructing AppleScript `do shell script` commands containing dynamic properties like the application bundle path (`Bundle.main.url(forResource:...)`). If a user renames the app or places it in a path with bash control characters like `; rm -rf /`, it would be executed as root since it uses "with administrator privileges".
**Learning:** Even internal app structures like bundle paths are user-controllable (since a user can rename the `.app` or place it anywhere) and must be treated as untrusted input. Directly interpolating strings into `do shell script` is inherently dangerous because it undergoes dual evaluation (once by AppleScript and once by `sh`).
**Prevention:** Always escape variables for the target shell (e.g., wrap in single quotes and replace `'` with `'\\''` for bash) before inclusion, and critically, escape backslashes and double quotes when embedding the command into an AppleScript string literal.

## 2024-06-14 - [Insecure Configuration Storage Permissions]
**Vulnerability:** `containers.json` file which stores container environment variables (potentially containing secrets like API keys or database passwords) was written with default permissions, making it world-readable.
**Learning:** Automatically serialized configuration files are prone to information exposure if they include sensitive values.
**Prevention:** Explicitly enforce restrictive file permissions (e.g., `0600`) and use safe file protection options (`.completeFileProtection`) when writing files that contain potentially sensitive user configuration or environmental data.

## 2024-06-14 - [Path Traversal via Untrusted YAML Keys]
**Vulnerability:** Path traversal vulnerability due to using untrusted dictionary keys (e.g., service names from a Compose YAML file) directly in file system path construction (`store.path.appendingPathComponent("containers").appendingPathComponent("\(podId)-\(service.name)-rootfs.ext4")`).
**Learning:** In configuration files like YAML, keys are user-supplied and thus untrusted input. If these keys are used dynamically for resource generation or path construction, they can contain malicious characters like `../` to write or overwrite data outside the intended sandbox.
**Prevention:** Always validate untrusted keys against a strict allowlist regex (e.g., `^[a-zA-Z0-9_-]+$`) before using them in file system or command line contexts.

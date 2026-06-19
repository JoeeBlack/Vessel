# 2025-06-19
- Removed the `--insecure` and `--http` flag fallbacks across `cctl` and `ImageStore`.
- Removed `scheme` and `insecure` initializers from `RegistryClient` entirely to enforce strict `https://` communication for OCI registries, mitigating data exposure.

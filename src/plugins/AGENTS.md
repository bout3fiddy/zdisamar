# Plugins

- Keep the two-lane model explicit: declarative/data plugins by default, trusted native plugins only when executable extension logic is required.
- Native plugin ABI must stay C-compatible and host-owned.
- Resolve plugins at plan preparation time; do not route dynamic plugin calls through hot transport loops.

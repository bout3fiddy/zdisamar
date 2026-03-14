# API

- The stable foreign boundary is C ABI first, Zig wrappers second.
- Keep ownership, lifetime, and mutability explicit in exported types.
- Do not expose Zig allocators, slices, or implicit ownership across the native plugin boundary.

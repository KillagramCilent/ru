# Plugin System

## Design

- Plugins are isolated modules executed in a sandbox (no direct MTProto access).
- Each plugin requests explicit permissions (read chat, write messages, automate).
- Plugins can be distributed as signed bundles.

## Runtime

- Plugin host loads a manifest and spins up an isolated runtime.
- Communication via message bus with strict schemas.

## Example Manifest

```json
{
  "id": "com.killagram.translate",
  "name": "Smart Translate",
  "permissions": ["read_messages", "write_messages"],
  "entry": "main.js"
}
```


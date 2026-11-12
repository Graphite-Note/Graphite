# Test community plugin

The vault has a small community plugin of its own, `release-vault-test` in `.obsidian/plugins`, listed in `.obsidian/community-plugins.json`. It needs no network and plays nothing. Community plugins stay off in a vault until they are turned on in Settings › Community Plugins; the release pass turns them on.

It adds two commands, "Release Vault Test: Insert a checked line" (⇧⌘L in `.obsidian/hotkeys.json`) and "Release Vault Test: Say hello", and draws a counter button for this block:

```release-vault-count
3
```

Without the plugin, the block shows as code.

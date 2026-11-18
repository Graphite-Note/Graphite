# Notion imported vault

What Obsidian's Importer 3.2.0, unmodified, writes into a vault from made-up Notion material: `Notion/Study Notes` from the
HTML export `Tests/CommunityPluginRuntimeTests/fixtures/notion-small-export.zip`, with its two attachments at the vault's
top, and `Notion/Signals and Systems` (with `.obsidian/types.json`) from the made-up workspace that
`support/notion-api-fixture.js` answers as Notion's API does. The runtime's Notion tests check that each file here is what
Importer writes, byte for byte, and write them again with `GRAPHITE_UPDATE_EXPECTATIONS=1`.

The release pass opens every note in its three views and the base in its own (`NotionImportedVaultPassTests` on the Mac,
`NotionImportedVaultPassHostedTests` on the iPad). Nothing here is anyone's own Notion workspace.

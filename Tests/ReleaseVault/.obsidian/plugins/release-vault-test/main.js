'use strict';
const { Plugin, Notice } = require('obsidian');
module.exports = class ReleaseVaultTestPlugin extends Plugin {
    async onload() {
        this.addCommand({
            id: 'insert-checked-line',
            name: 'Insert a checked line',
            editorCallback: (editor) => editor.replaceSelection('Checked by the release vault test plugin.'),
        });
        this.addCommand({ id: 'say-hello', name: 'Say hello', callback: () => new Notice('Hello from the release vault test plugin') });
        this.registerMarkdownCodeBlockProcessor('release-vault-count', (source, element) => {
            let count = Number(source.trim()) || 0;
            const button = element.createEl('button', { cls: 'release-vault-count', text: 'Count ' + count });
            button.addEventListener('click', () => { count += 1; button.setText('Count ' + count); });
        });
    }
};

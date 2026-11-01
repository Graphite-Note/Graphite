/**
 * File: community-plugin-runtime-bases.js
 * ---------------------------------------
 * Layer: UI
 * Description: Obsidian's Bases values and classes for plugins, and plugins' views over Graphite's base results,
 *              redrawn as their notes change.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 01/11/2026
 */

// Obsidian's Bases classes for plugins: the values of base formulas and the classes a
// plugin extends to offer its own base view (`registerBasesView`). Graphite evaluates bases
// natively (`BaseEvaluator`); a view of a plugin's type is drawn here by the plugin over
// Graphite's results, shown live in a base's own tab and as a copy where a note embeds it.
(function installRuntimeBases(globalScope) {
    'use strict';

    const runtime = globalScope.GraphitePluginRuntime;
    const exportedApi = runtime.obsidianModule;
    const { Component } = exportedApi;

    // MARK: Values

    class Value {
        static equals(firstValue, secondValue) {
            if (!firstValue || !secondValue) return firstValue === secondValue;
            return firstValue.constructor === secondValue.constructor && firstValue.equals(secondValue);
        }
        static looseEquals(firstValue, secondValue) {
            if (!firstValue || !secondValue) return firstValue === secondValue;
            return firstValue.looseEquals(secondValue);
        }
        toString() { return ''; }
        isTruthy() { return false; }
        equals(other) { return this.toString() === other.toString(); }
        looseEquals(other) { return this.toString() === other.toString(); }
        renderTo(element) { element.setText(this.toString()); }
    }
    Value.type = 'value';

    class NullValue extends Value {
        toString() { return ''; }
        isTruthy() { return false; }
    }
    NullValue.type = 'null';
    NullValue.value = new NullValue();

    class NotNullValue extends Value {}

    class PrimitiveValue extends NotNullValue {
        constructor(value) {
            super();
            this.value = value;
        }
        toString() { return String(this.value); }
        isTruthy() { return Boolean(this.value); }
        equals(other) { return other instanceof PrimitiveValue && other.value === this.value; }
    }

    class StringValue extends PrimitiveValue {}
    StringValue.type = 'string';
    class NumberValue extends PrimitiveValue {}
    NumberValue.type = 'number';
    class BooleanValue extends PrimitiveValue {}
    BooleanValue.type = 'boolean';

    class DateValue extends NotNullValue {
        /// `hasTime` is false for a date without a time of day, which prints without one.
        constructor(date, hasTime) {
            super();
            this.date = date;
            this.hasTime = Boolean(hasTime);
        }
        toString() {
            if (!globalScope.moment) return this.date.toISOString();
            return globalScope.moment(this.date).format(this.hasTime ? 'YYYY-MM-DD HH:mm' : 'YYYY-MM-DD');
        }
        isTruthy() { return true; }
    }
    DateValue.type = 'date';
    class RelativeDateValue extends DateValue {}
    class DurationValue extends NotNullValue {
        constructor(milliseconds) {
            super();
            this.milliseconds = milliseconds;
        }
        toString() { return String(this.milliseconds) + ' ms'; }
        isTruthy() { return this.milliseconds !== 0; }
    }
    DurationValue.type = 'duration';

    class ListValue extends NotNullValue {
        constructor(values) {
            super();
            this.values = (values || []).map((entry) => (entry instanceof Value ? entry : new StringValue(String(entry))));
        }
        toString() { return this.values.map((entry) => entry.toString()).join(', '); }
        isTruthy() { return this.values.length > 0; }
        includes(value) { return this.values.some((entry) => Value.equals(entry, value)); }
        length() { return this.values.length; }
        get(index) { return this.values[index] || NullValue.value; }
        concat(other) { return new ListValue(this.values.concat(other.values)); }
    }
    ListValue.type = 'list';

    class ObjectValue extends NotNullValue {
        constructor(entries) {
            super();
            this.entries = entries || {};
        }
        toString() { return JSON.stringify(plainValue(this)); }
        isTruthy() { return Object.keys(this.entries).length > 0; }
    }
    ObjectValue.type = 'object';

    /// A value as the data it holds, which is how an object prints in Obsidian.
    function plainValue(value) {
        if (value instanceof ObjectValue) return Object.fromEntries(Object.entries(value.entries).map(([key, entry]) => [key, plainValue(entry)]));
        if (value instanceof ListValue) return value.values.map(plainValue);
        if (value instanceof PrimitiveValue) return value.value;
        return value instanceof NullValue ? null : String(value);
    }

    class FileValue extends NotNullValue {
        constructor(file) {
            super();
            this.file = file;
        }
        toString() { return this.file ? this.file.path : ''; }
        isTruthy() { return Boolean(this.file); }
    }
    FileValue.type = 'file';
    class LinkValue extends StringValue {}
    LinkValue.type = 'link';
    class UrlValue extends StringValue {}
    UrlValue.type = 'url';
    class TagValue extends StringValue {}
    TagValue.type = 'tag';
    class HTMLValue extends StringValue {}
    HTMLValue.type = 'html';
    class IconValue extends StringValue {}
    IconValue.type = 'icon';
    class ImageValue extends StringValue {}
    ImageValue.type = 'image';
    class RegExpValue extends NotNullValue {
        constructor(pattern) {
            super();
            this.pattern = pattern;
        }
        toString() { return String(this.pattern); }
        isTruthy() { return true; }
    }
    RegExpValue.type = 'regexp';

    // MARK: Views

    class RenderContext {
        constructor() { this.hoverPopover = null; }
    }

    class QueryController extends Component {}

    class BasesViewConfig {
        /// `savesOption` writes an option a plugin sets into the view in the `.base` file.
        constructor(name, savesOption) {
            this.name = name || '';
            this.options = {};
            this.displayNames = {};
            this.savesOption = savesOption || null;
        }
        get(key) { return this.options[key]; }
        getAsPropertyId(key) { return typeof this.options[key] === 'string' ? this.options[key] : null; }
        /// Graphite evaluates a base's own formulas, not one a plugin keeps in an option, and says so.
        getEvaluatedFormula() {
            runtime.reportUnsupportedFeature('BasesViewConfig.getEvaluatedFormula');
            return NullValue.value;
        }
        set(key, value) {
            if (this.options[key] === value) return;
            this.options[key] = value;
            if (this.savesOption) this.savesOption(key, value);
        }
        getOrder() { return []; }
        getSort() { return []; }
        getDisplayName(propertyId) {
            const displayName = this.displayNames[propertyId];
            return typeof displayName === 'string' && displayName !== '' ? displayName : parsePropertyId(propertyId).name;
        }
    }

    /// A date property's text (`2026-09-21`, `2026-09-21T10:15`) as a date; null for other text.
    function dateValueFromText(text) {
        if (!/^\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2})?)?$/.test(text)) return null;
        const hasTime = text.length > 10;
        const date = new Date(hasTime ? text : text + 'T00:00:00');
        return isNaN(date.getTime()) ? null : new DateValue(date, hasTime);
    }

    /// A plain value from a note's frontmatter as one of Obsidian's Bases values. Text that
    /// looks like a date is a date unless the vault declares the property as text
    /// (`.obsidian/types.json`); Obsidian too goes by the declared type first.
    function wrapValue(value, declaredType) {
        if (value === null || value === undefined) return NullValue.value;
        if (value instanceof Value) return value;
        if (Array.isArray(value)) return new ListValue(value.map((entry) => wrapValue(entry, declaredType)));
        if (typeof value === 'number') return new NumberValue(value);
        if (typeof value === 'boolean') return new BooleanValue(value);
        if (value instanceof Date) return new DateValue(value, value.getHours() !== 0 || value.getMinutes() !== 0);
        if (typeof value === 'object') return new ObjectValue(Object.fromEntries(Object.entries(value).map(([key, entry]) => [key, wrapValue(entry)])));
        const text = String(value);
        const isDeclaredAsOtherThanDate = typeof declaredType === 'string' && declaredType !== 'date' && declaredType !== 'datetime';
        const dateValue = isDeclaredAsOtherThanDate ? null : dateValueFromText(text);
        if (dateValue) return dateValue;
        if (/^\[\[[^\]]+\]\]$/.test(text)) return new LinkValue(text);
        return new StringValue(text);
    }

    /// A value Graphite evaluated (a formula's), as Graphite sends it.
    function receivedValue(encoded) {
        if (!encoded || typeof encoded !== 'object') return NullValue.value;
        switch (encoded.type) {
        case 'boolean': return new BooleanValue(Boolean(encoded.value));
        case 'number': return new NumberValue(Number(encoded.value));
        case 'string': return new StringValue(String(encoded.value));
        case 'date': return new DateValue(new Date(Number(encoded.value)), encoded.hasTime);
        case 'list': return new ListValue((encoded.value || []).map(receivedValue));
        case 'link': return new LinkValue(String(encoded.value));
        case 'file': {
            const file = runtime.app ? runtime.app.vault.getFileByPath(String(encoded.value)) : null;
            return file ? new FileValue(file) : new StringValue(String(encoded.value));
        }
        case 'object': return new ObjectValue(Object.fromEntries((encoded.value || []).map(([key, entry]) => [key, receivedValue(entry)])));
        default: return NullValue.value;
        }
    }

    /// One file of a base's results. Its values come from the vault's metadata cache, as
    /// Obsidian's do: note properties from the frontmatter, file properties from the file;
    /// formulas from Graphite, which evaluates them as its own views show them.
    class BasesEntry {
        constructor(file, formulaValues) { this.file = file; this.formulaValues = formulaValues || {}; }
        getValue(propertyId) {
            const { type, name } = parsePropertyId(propertyId);
            const file = this.file;
            if (!file) return NullValue.value;
            if (type === 'formula') return receivedValue(this.formulaValues['formula.' + name]);
            if (type === 'file') {
                const app = runtime.app;
                const cache = app ? app.metadataCache.getFileCache(file) : null;
                switch (name) {
                case 'name': return new StringValue(file.name);
                case 'basename': return new StringValue(file.basename);
                case 'path': return new StringValue(file.path);
                case 'folder': return new StringValue(file.parent ? file.parent.path : '');
                case 'ext': return new StringValue(file.extension);
                case 'size': return new NumberValue(file.stat ? file.stat.size : 0);
                case 'ctime': return file.stat ? new DateValue(new Date(file.stat.ctime)) : NullValue.value;
                case 'mtime': return file.stat ? new DateValue(new Date(file.stat.mtime)) : NullValue.value;
                case 'file': return new FileValue(file);
                case 'tags': return new ListValue((cache && exportedApi.getAllTags ? exportedApi.getAllTags(cache) || [] : []).map((tag) => new TagValue(tag)));
                case 'links': return new ListValue((cache && cache.links ? cache.links : []).map((link) => new LinkValue('[[' + link.link + ']]')));
                default: return NullValue.value;
                }
            }
            if (type === 'note') {
                const cache = runtime.app ? runtime.app.metadataCache.getFileCache(file) : null;
                const frontmatter = cache && cache.frontmatter ? cache.frontmatter : {};
                const declaredTypes = runtime.app ? runtime.app.metadataTypeManager.types : {};
                return wrapValue(frontmatter[name], declaredTypes[name]);
            }
            return NullValue.value;
        }
    }

    class BasesEntryGroup {
        constructor() {
            this.key = null;
            this.entries = [];
        }
        hasKey() { return this.key !== null; }
    }

    class BasesQueryResult {
        constructor(data, groups, properties, summaryValues) {
            this.data = data || [];
            this.groups = groups || null;
            this.propertyIds = properties || [];
            this.summaryValues = summaryValues || {};
        }
        get groupedData() {
            if (this.groups) return this.groups;
            const group = new BasesEntryGroup();
            group.entries = this.data;
            return this.data.length ? [group] : [];
        }
        get properties() { return this.propertyIds; }
        /// The summary Graphite evaluated for a column of the view. Its own arguments are
        /// Obsidian's (the controller, the entries, the property and the summary's name), and
        /// one the view does not summarise reads as empty.
        getSummaryValue(queryController, entries, propertyId) { return receivedValue(this.summaryValues[propertyId]); }
    }

    class BasesView extends Component {
        constructor(controller) {
            super();
            this.controller = controller;
            this.app = runtime.app;
            this.config = new BasesViewConfig();
            this.allProperties = [];
            this.data = new BasesQueryResult();
        }
        onDataUpdated() {}
        onResize() {}
        async createFileForView() {
            runtime.unsupported('BasesView.createFileForView', 'Graphite does not make a new note from a plugin\'s base view yet.');
        }
    }

    // MARK: Plugins' views in Graphite's bases

    /// The views plugins registered (`registerBasesView`), by type.
    runtime.basesViews = new Map();
    let isBasesNotificationScheduled = false;
    runtime.basesViewsChanged = function basesViewsChanged() {
        if (isBasesNotificationScheduled) return;
        isBasesNotificationScheduled = true;
        Promise.resolve().then(() => {
            isBasesNotificationScheduled = false;
            runtime.hostBridge.notify('basesViews.changed', {
                views: Array.from(runtime.basesViews.entries()).map(([viewType, registered]) => ({
                    viewType, name: registered.registration.name || viewType, pluginIdentifier: registered.pluginIdentifier,
                    icon: typeof registered.registration.icon === 'string' ? registered.registration.icon : '',
                    options: registeredOptions(registered),
                })),
            });
        });
    };

    /// The options a view offers (`registration.options()`), as Graphite's view editor shows
    /// them: Obsidian's groups are flattened, and only what can cross to the app is kept.
    function registeredOptions(registered) {
        let options = [];
        try {
            const offered = typeof registered.registration.options === 'function' ? registered.registration.options() : [];
            options = Array.isArray(offered) ? offered : [];
        } catch (error) {
            console.error(error);
        }
        const flattened = options.flatMap((option) => (option && option.type === 'group' && Array.isArray(option.items) ? option.items : [option]));
        return flattened.filter((option) => option && typeof option.key === 'string').map((option) => {
            const described = { key: option.key, type: String(option.type || 'text'), displayName: String(option.displayName || option.key) };
            if (['string', 'number', 'boolean'].includes(typeof option.default)) described.defaultValue = option.default;
            if (option.options && typeof option.options === 'object') described.choices = Object.entries(option.options).map(([value, title]) => ({ value: String(value), title: String(title) }));
            for (const limit of ['min', 'max', 'step']) if (typeof option[limit] === 'number') described[limit] = option[limit];
            return described;
        });
    }

    /// A base's view of a plugin's type, in a leaf of its own: Graphite shows the leaf live in
    /// the base's tab, or a copy of it where a note embeds the base.
    class PluginBasesHostView extends exportedApi.ItemView {
        getViewType() { return 'graphite-bases-plugin-view'; }
        getDisplayText() { return this.viewName || 'Base'; }
        onResize() {
            if (!this.basesView || typeof this.basesView.onResize !== 'function') return;
            try { this.basesView.onResize(); } catch (error) { console.error(error); }
        }
    }

    /// How long a view waits for its rows' notes to be read before it draws what it has;
    /// what arrives later redraws it.
    const metadataWaitMilliseconds = 5000;
    /// Notes that change together redraw a view once.
    const redrawDelayMilliseconds = 100;
    /// Leaves whose opening Graphite gave up on: the opening is still under way, or just ended.
    const abandonedOpenings = new Set();
    const openedLeafByRequest = new Map();
    const maximumRememberedOpenings = 32;

    function waitAtMost(promise, milliseconds) {
        return Promise.race([promise, new Promise((resolve) => globalScope.setTimeout(resolve, milliseconds))]);
    }

    function listedFiles(app, message) {
        return (message.groups || []).flatMap((group) => group.paths || []).map((path) => app.vault.getFileByPath(path)).filter(Boolean);
    }

    /// Gives the view its results again, grouped by the values the notes have now.
    function redraw(hostView) {
        const view = hostView.basesView;
        if (!view || !hostView.lastMessage) return;
        view.data = groupedByView(resultFrom(hostView.lastMessage), hostView.groupBy);
        try { view.onDataUpdated(); } catch (error) { console.error(error); }
    }

    /// The view draws again when a note it lists is read or changes, in Graphite or elsewhere:
    /// its values come from the metadata cache, which fills after it opened.
    function followListedNotes(hostView, app) {
        hostView.registerEvent(app.metadataCache.on('changed', (file) => {
            if (!hostView.listedPaths || !hostView.listedPaths.has(file.path) || hostView.redrawTimer) return;
            hostView.redrawTimer = globalScope.setTimeout(() => {
                hostView.redrawTimer = null;
                redraw(hostView);
            }, redrawDelayMilliseconds);
        }));
        hostView.register(() => { if (hostView.redrawTimer) globalScope.clearTimeout(hostView.redrawTimer); });
    }

    function remember(hostView, message) {
        hostView.lastMessage = message;
        hostView.listedPaths = new Set((message.groups || []).flatMap((group) => group.paths || []));
    }

    /// A plugin set an option of its view (`config.set`): Graphite writes it into the view in
    /// the `.base` file, as Obsidian does. A code block's base belongs to its note's editor.
    function optionSaver(message) {
        if (typeof message.baseFilePath !== 'string' || message.baseFilePath === '') return null;
        return (key, value) => runtime.hostBridge.notify('basesView.setOption', {
            baseFilePath: message.baseFilePath, viewName: message.viewName || '', viewIndex: Number(message.viewIndex) || 0, key,
            value: value === undefined ? null : value,
        });
    }

    function applyViewSettings(hostView, config, options, definition) {
        for (const key of Object.keys(config.options)) { if (!(key in options)) delete config.options[key]; }
        Object.assign(config.options, options);
        const properties = definition && typeof definition.properties === 'object' && definition.properties ? definition.properties : {};
        config.displayNames = Object.fromEntries(Object.entries(properties).map(([propertyId, settings]) => [propertyId, settings && settings.displayName]));
        hostView.groupBy = options.groupBy;
    }

    function resultFrom(message) {
        const app = runtime.app;
        const fileOf = (path) => app.vault.getFileByPath(path);
        const groups = (message.groups || []).map((group) => {
            const entryGroup = new BasesEntryGroup();
            entryGroup.key = group.key === null || group.key === undefined ? null : wrapValue(group.key);
            const formulaValues = message.formulaValues || {};
            entryGroup.entries = (group.paths || []).map(fileOf).filter(Boolean).map((file) => new BasesEntry(file, formulaValues[file.path]));
            return entryGroup;
        });
        const data = groups.flatMap((group) => group.entries);
        const isGrouped = groups.some((group) => group.key !== null);
        return new BasesQueryResult(data, isGrouped ? groups : null, message.properties || [], message.summaryValues);
    }

    /// The view's settings as the `.base` file writes them: its keys are what the plugin's
    /// view reads with `config.get` (TaskNotes' date and status properties).
    async function baseDefinition(baseFilePath, baseYaml) {
        try {
            const app = runtime.app;
            let text = typeof baseYaml === 'string' ? baseYaml : null;
            if (text === null) {
                const file = app.vault.getFileByPath(baseFilePath);
                if (!file) return {};
                text = await app.vault.cachedRead(file);
            }
            return exportedApi.parseYaml(text) || {};
        } catch (error) {
            return {};
        }
    }

    /// The base's results grouped by the view's `groupBy`, as Obsidian gives a grouped view
    /// (Graphite's own result for a plugin's view type is not grouped).
    function groupedByView(result, groupBy) {
        const property = groupBy && typeof groupBy === 'object' ? groupBy.property : groupBy;
        if (!property || result.groups) return result;
        const groupsByKey = new Map();
        for (const entry of result.data) {
            const value = entry.getValue(String(property).includes('.') ? property : 'note.' + property);
            const key = value && !(value instanceof NullValue) ? value.toString() : '';
            if (!groupsByKey.has(key)) {
                const group = new BasesEntryGroup();
                group.key = key === '' ? null : value;
                groupsByKey.set(key, group);
            }
            groupsByKey.get(key).entries.push(entry);
        }
        return new BasesQueryResult(result.data, Array.from(groupsByKey.values()), result.propertyIds, result.summaryValues);
    }

    async function viewOptions(baseFilePath, viewIndex, baseYaml) {
        try {
            const app = runtime.app;
            let text = typeof baseYaml === 'string' ? baseYaml : null;
            if (text === null) {
                const file = app.vault.getFileByPath(baseFilePath);
                if (!file) return {};
                text = await app.vault.cachedRead(file);
            }
            const definition = exportedApi.parseYaml(text) || {};
            const view = Array.isArray(definition.views) ? definition.views[viewIndex] : null;
            return view && typeof view === 'object' ? view : {};
        } catch (error) {
            return {};
        }
    }

    /// Joined to the runtime's messages when the plugins' script installs them.
    runtime.basesMessageHandlers = ({
        /// Graphite's base shows a view of a plugin's type: the plugin's view is made in a leaf
        /// over the base's results, and Graphite shows the leaf live in the base's tab.
        async 'basesView.open'(message) {
            const app = runtime.app;
            const registered = app ? runtime.basesViews.get(message.viewType) : null;
            if (!registered) return { isOpened: false, message: 'No plugin shows “' + message.viewType + '” views now.' };
            const leaf = app.workspace.createPluginLeaf('bases');
            leaf.hasBeenShown = true;
            // An embed lays out at its width in the note, so the plugin measures what it will show in.
            if (message.embedWidth && leaf.waitingPlace) runtime.sizeWaitingPlace(leaf, message.embedWidth);
            const hostView = new PluginBasesHostView(leaf);
            hostView.viewName = message.viewName || '';
            await leaf.open(hostView);
            // Its rows' notes come first, before the rest of the vault, so it draws them filled in.
            await waitAtMost(app.metadataCache.readNow(listedFiles(app, message)), metadataWaitMilliseconds);
            const controller = new QueryController();
            controller.load();
            const options = await viewOptions(message.baseFilePath || '', Number(message.viewIndex) || 0, message.baseYaml);
            // Obsidian's controller knows the base's parsed views and the one shown (undocumented;
            // TaskNotes reads the Kanban's groupBy there).
            const definition = await baseDefinition(message.baseFilePath || '', message.baseYaml);
            controller.query = { views: Array.isArray(definition.views) ? definition.views : [] };
            controller.viewName = message.viewName || options.name || '';
            try {
                const view = registered.registration.factory(controller, hostView.contentEl);
                const config = new BasesViewConfig(message.viewName || options.name || '', optionSaver(message));
                applyViewSettings(hostView, config, options, definition);
                config.getOrder = () => (Array.isArray(config.options.order) ? config.options.order.map(String) : []);
                config.getSort = () => (Array.isArray(config.options.sort) ? config.options.sort : []);
                view.config = config;
                view.allProperties = message.properties || config.getOrder();
                view.data = groupedByView(resultFrom(message), options.groupBy);
                controller.addChild(view);
                hostView.basesView = view;
                hostView.controller = controller;
                hostView.register(() => controller.unload());
                remember(hostView, message);
                hostView.baseSource = { baseFilePath: message.baseFilePath || '', baseYaml: message.baseYaml, viewIndex: Number(message.viewIndex) || 0 };
                followListedNotes(hostView, app);
                view.onDataUpdated();
            } catch (error) {
                console.error(error);
                hostView.contentEl.empty();
                hostView.contentEl.createDiv({ cls: 'graphite-plugin-error', text: String(error && error.message ? error.message : error) });
                runtime.hostBridge.notify('plugin.failure', { pluginIdentifier: registered.pluginIdentifier, message: 'Its “' + message.viewType + '” view failed: ' + (error && error.message ? error.message : String(error)) });
            }
            // Graphite stopped waiting for this answer, so it will never show or close this leaf.
            if (abandonedOpenings.delete(message.openingIdentifier)) {
                leaf.detach();
                return { isOpened: false, message: 'Graphite stopped waiting for this view.' };
            }
            if (message.openingIdentifier) {
                openedLeafByRequest.set(message.openingIdentifier, leaf.id);
                if (openedLeafByRequest.size > maximumRememberedOpenings) openedLeafByRequest.delete(openedLeafByRequest.keys().next().value);
            }
            return { isOpened: true, leafIdentifier: leaf.id };
        },
        /// Graphite gave up waiting for `basesView.open`; the leaf made for it goes.
        async 'basesView.abandonOpening'(message) {
            const leafIdentifier = openedLeafByRequest.get(message.openingIdentifier);
            const leaf = leafIdentifier && runtime.app ? runtime.app.workspace.getLeafById(leafIdentifier) : null;
            if (leaf) leaf.detach();
            else if (!leafIdentifier) abandonedOpenings.add(message.openingIdentifier);
            openedLeafByRequest.delete(message.openingIdentifier);
            return {};
        },
        /// The base's results changed (a file changed, a filter was edited), or the view's
        /// settings did (`viewOptionsChanged`, the view editor).
        async 'basesView.update'(message) {
            const app = runtime.app;
            const leaf = app ? app.workspace.getLeafById(message.leafIdentifier) : null;
            const view = leaf && leaf.view && leaf.view.basesView;
            if (!view) return { isUpdated: false };
            const hostView = leaf.view;
            remember(hostView, message);
            const source = hostView.baseSource;
            if (message.viewOptionsChanged && source) {
                const options = await viewOptions(source.baseFilePath, source.viewIndex, source.baseYaml);
                applyViewSettings(hostView, view.config, options, await baseDefinition(source.baseFilePath, source.baseYaml));
            }
            await waitAtMost(app.metadataCache.readNow(listedFiles(app, message)), metadataWaitMilliseconds);
            redraw(hostView);
            return { isUpdated: true };
        },
    });

    /// `note.status` → `{ type: 'note', name: 'status' }`, as Obsidian splits property identifiers.
    function parsePropertyId(propertyId) {
        const text = String(propertyId);
        const dotPosition = text.indexOf('.');
        if (dotPosition === -1) return { type: 'note', name: text };
        return { type: text.slice(0, dotPosition), name: text.slice(dotPosition + 1) };
    }

    Object.assign(exportedApi, {
        Value, NullValue, NotNullValue, PrimitiveValue, StringValue, NumberValue, BooleanValue, DateValue, RelativeDateValue,
        DurationValue, ListValue, ObjectValue, FileValue, LinkValue, UrlValue, TagValue, HTMLValue, IconValue, ImageValue, RegExpValue,
        RenderContext, QueryController, BasesViewConfig, BasesEntry, BasesEntryGroup, BasesQueryResult, BasesView, parsePropertyId,
    });
})(globalThis);

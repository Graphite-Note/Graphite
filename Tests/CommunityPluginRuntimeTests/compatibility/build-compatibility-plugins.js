/**
 * File: build-compatibility-plugins.js
 * ------------------------------------
 * Layer: Tests
 * Description: Builds the real community plugins of the compatibility tests from their sources at
 *              fixed commits, or downloads a pinned release's files and checks their checksums.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

// Builds real Obsidian community plugins from their sources at fixed commits, the way
// their authors build release bundles, for the compatibility tests. Each plugin is cloned
// into a cache folder, its own dependencies are installed with its own package manager,
// and its own build runs; `main.js`, `manifest.json` and `styles.css` are then copied to
// `compatibility/built/<plugin id>/`. Nothing built is committed.
//
// A plugin's entry in compatibility-plugins.json can list `filesBeforeBuilding`, files its
// README asks a developer to create before building (name → contents).
//
// A plugin whose own build needs tools these tests do not install (Meta Bind builds with Bun)
// is pinned by its release instead: `release` names the GitHub release, `commit` the commit it
// was tagged on, and `releaseFiles` the SHA-256 of each file Graphite's installer downloads
// from it (`main.js`, `manifest.json`, `styles.css`). The files are downloaded from the
// release and refused when a checksum differs, so the tests run exactly the files checked.
//
// Usage: node compatibility/build-compatibility-plugins.js [--only=owner/name,…] [cache folder]
// `--only` builds the plugins of those repositories alone.
'use strict';

const fileSystem = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const compatibilityPlugins = require('./compatibility-plugins.json');
const commandArguments = process.argv.slice(2);
const onlyArgument = commandArguments.find((argument) => argument.startsWith('--only='));
const onlyRepositories = onlyArgument ? new Set(onlyArgument.slice('--only='.length).split(',')) : null;
const requestedCacheFolder = path.resolve(commandArguments.find((argument) => !argument.startsWith('--')) || path.join(os.tmpdir(), 'graphite-compatibility-plugin-sources'));
const builtFolder = path.join(__dirname, 'built');

function run(command, commandArguments, workingFolder) {
    return execFileSync(command, commandArguments, { cwd: workingFolder, stdio: ['ignore', 'pipe', 'pipe'], encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, timeout: 15 * 60 * 1000 });
}

/// Installs with the plugin's own package manager and lockfile, so the build uses the
/// versions its author built with: newer releases within package.json's ranges can break an
/// old build (picomatch 2.3.2 no longer reads the pattern Rollup's TypeScript plugin 8 uses to
/// find source files). When that fails (yarn's and pnpm's lockfiles name their own hosts),
/// npm resolves the dependency ranges from package.json instead.
function installDependencies(sourceFolder) {
    try {
        if (fileSystem.existsSync(path.join(sourceFolder, 'pnpm-lock.yaml'))) { run('npx', ['--yes', 'pnpm@10', 'install', '--no-frozen-lockfile'], sourceFolder); return; }
        if (fileSystem.existsSync(path.join(sourceFolder, 'yarn.lock'))) { run('npx', ['--yes', 'yarn@1', 'install', '--ignore-engines'], sourceFolder); return; }
        if (fileSystem.existsSync(path.join(sourceFolder, 'package-lock.json'))) { run('npm', ['ci', '--no-audit', '--no-fund', '--legacy-peer-deps'], sourceFolder); return; }
    } catch (error) {
        console.warn('  the plugin\'s package manager failed; installing with npm from package.json');
    }
    run('npm', ['install', '--no-audit', '--no-fund', '--legacy-peer-deps', '--no-package-lock'], sourceFolder);
}

function build(sourceFolder, plugin) {
    for (const buildCommand of plugin.buildCommands) {
        try {
            run(buildCommand[0], buildCommand.slice(1), sourceFolder);
            return;
        } catch (error) {
            console.warn('  ' + buildCommand.join(' ') + ' failed: ' + String(error.stderr || error.message).split('\n').slice(-5).join(' | '));
        }
    }
    throw new Error('Every build command failed.');
}

function findBuiltFile(sourceFolder, plugin, fileName) {
    for (const candidate of (plugin.outputFolders || ['.']).map((folder) => path.join(sourceFolder, folder, fileName))) {
        if (fileSystem.existsSync(candidate)) return candidate;
    }
    return null;
}

/// Downloads the release files a plugin is pinned by into `destination`, after checking each
/// against its SHA-256. Nothing is written unless every file matches.
async function downloadPinnedRelease(plugin, destination) {
    const contentsByFileName = {};
    for (const [fileName, expectedDigest] of Object.entries(plugin.releaseFiles)) {
        const address = 'https://github.com/' + plugin.repository + '/releases/download/' + encodeURIComponent(plugin.release) + '/' + fileName;
        const response = await fetch(address, { redirect: 'follow' });
        if (!response.ok) throw new Error(fileName + ' of release ' + plugin.release + ' could not be downloaded (HTTP ' + response.status + ').');
        const contents = Buffer.from(await response.arrayBuffer());
        const digest = crypto.createHash('sha256').update(contents).digest('hex');
        if (digest !== expectedDigest) throw new Error(fileName + ' of release ' + plugin.release + ' has the SHA-256 ' + digest + ', not the pinned ' + expectedDigest + '.');
        contentsByFileName[fileName] = contents;
    }
    const manifest = JSON.parse(contentsByFileName['manifest.json'].toString('utf8'));
    const pluginFolder = path.join(destination, manifest.id);
    fileSystem.mkdirSync(pluginFolder, { recursive: true });
    for (const [fileName, contents] of Object.entries(contentsByFileName)) fileSystem.writeFileSync(path.join(pluginFolder, fileName), contents);
    fileSystem.writeFileSync(path.join(pluginFolder, 'source.json'), JSON.stringify({ repository: plugin.repository, commit: plugin.commit, release: plugin.release, releaseFiles: plugin.releaseFiles }, null, 2));
    return manifest.id;
}

/// A plugin built from the same commit before is not built again.
function isAlreadyBuilt(plugin) {
    if (!fileSystem.existsSync(builtFolder)) return false;
    return fileSystem.readdirSync(builtFolder).some((folderName) => {
        const sourceDescription = path.join(builtFolder, folderName, 'source.json');
        if (!fileSystem.existsSync(sourceDescription)) return false;
        const source = JSON.parse(fileSystem.readFileSync(sourceDescription, 'utf8'));
        return source.repository === plugin.repository && source.commit === plugin.commit;
    });
}

fileSystem.mkdirSync(requestedCacheFolder, { recursive: true });
// Plugins build in the folder's real path. macOS's temporary folder is behind a symbolic link
// (/var is /private/var), and Rollup's TypeScript plugin, which matches source files against
// the working folder's path, would then skip every one of them. A cache folder whose path has
// a hidden component (`~/.cache`) fails the same way, so the default is the temporary folder.
const cacheFolder = fileSystem.realpathSync(requestedCacheFolder);
fileSystem.mkdirSync(builtFolder, { recursive: true });
async function buildEveryPlugin() {
    const report = [];
    for (const plugin of compatibilityPlugins) {
        if (onlyRepositories && !onlyRepositories.has(plugin.repository)) continue;
        const sourceFolder = path.join(cacheFolder, plugin.repository.replace('/', '__'));
        console.log(plugin.repository + ' at ' + plugin.commit + (plugin.release ? ' (release ' + plugin.release + ')' : ''));
        try {
            if (isAlreadyBuilt(plugin)) {
                report.push({ repository: plugin.repository, isBuilt: true, isReused: true });
                console.log('  already built');
                continue;
            }
            if (plugin.release) {
                const pluginIdentifier = await downloadPinnedRelease(plugin, builtFolder);
                report.push({ repository: plugin.repository, pluginIdentifier, isBuilt: true, isDownloaded: true });
                console.log('  downloaded ' + pluginIdentifier + ' ' + plugin.release + ', checksums match');
                continue;
            }
            if (!fileSystem.existsSync(sourceFolder)) {
                run('git', ['clone', '--quiet', 'https://github.com/' + plugin.repository + '.git', sourceFolder], cacheFolder);
            }
            run('git', ['fetch', '--quiet', '--depth', '1', 'origin', plugin.commit], sourceFolder);
            run('git', ['checkout', '--quiet', plugin.commit], sourceFolder);
            installDependencies(sourceFolder);
            for (const [fileName, contents] of Object.entries(plugin.filesBeforeBuilding || {})) {
                fileSystem.writeFileSync(path.join(sourceFolder, fileName), contents);
            }
            build(sourceFolder, plugin);
            const mainScript = findBuiltFile(sourceFolder, plugin, 'main.js');
            const manifestFile = findBuiltFile(sourceFolder, plugin, 'manifest.json') || path.join(sourceFolder, 'manifest.json');
            if (!mainScript) throw new Error('The build made no main.js.');
            const manifest = JSON.parse(fileSystem.readFileSync(manifestFile, 'utf8'));
            const destination = path.join(builtFolder, manifest.id);
            fileSystem.mkdirSync(destination, { recursive: true });
            fileSystem.copyFileSync(mainScript, path.join(destination, 'main.js'));
            fileSystem.copyFileSync(manifestFile, path.join(destination, 'manifest.json'));
            const styles = findBuiltFile(sourceFolder, plugin, 'styles.css');
            if (styles) fileSystem.copyFileSync(styles, path.join(destination, 'styles.css'));
            fileSystem.writeFileSync(path.join(destination, 'source.json'), JSON.stringify({ repository: plugin.repository, commit: plugin.commit }, null, 2));
            report.push({ repository: plugin.repository, pluginIdentifier: manifest.id, isBuilt: true });
            console.log('  built ' + manifest.id);
        } catch (error) {
            report.push({ repository: plugin.repository, isBuilt: false, reason: String(error.message).split('\n')[0] });
            console.warn('  not built: ' + String(error.message).split('\n')[0]);
        }
    }
    fileSystem.writeFileSync(path.join(builtFolder, 'build-report.json'), JSON.stringify(report, null, 2));
}

buildEveryPlugin().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});

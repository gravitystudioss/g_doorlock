// npm run release: build the NUI and pack release/g_doorlock-<version>.zip
import { execSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { zipSync } from 'fflate';

const web = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const root = resolve(web, '..');
const name = 'g_doorlock';
const fail = (message) => {
  console.error(`[release] ${message}`);
  process.exit(1);
};

// Sources, tooling and dot files stay out
const excluded = [/^web\/(?!dist\/)/, /^release\//, /(^|\/)\./, /^package\.json$/];

const manifest = readFileSync(join(root, 'fxmanifest.lua'), 'utf8');
const version = /^version\s+'([^']+)'/m.exec(manifest)?.[1];
if (!version) fail('version not found in fxmanifest.lua');

// Webhooks and keys must be '' before a release
for (const file of ['config.lua', 'config_server.lua']) {
  const text = readFileSync(join(root, file), 'utf8');
  const leak = /https?:\/\/(?:\w+\.)?discord(?:app)?\.com\/api\/webhooks\/\S+|\b\w*(?:api_?key|token|secret|password)\s*=\s*'[^']+'/i.exec(text);
  if (leak) fail(`${file} contains a secret (${leak[0].slice(0, 48)}...), clear it before releasing`);
}

console.log('[release] building the NUI');
execSync('npm run build', { cwd: web, stdio: 'inherit' });
const uiPage = /^ui_page\s+'([^']+)'/m.exec(manifest)?.[1];
if (!uiPage || !existsSync(join(root, uiPage))) fail(`ui_page ${uiPage} is missing after the build`);

// Files git does not ignore, plus the build
const listed = execSync('git ls-files --cached --others --exclude-standard', { cwd: root, encoding: 'utf8' })
  .split('\n')
  .filter(Boolean);
const walk = (directory) =>
  readdirSync(directory).flatMap((entry) => {
    const path = join(directory, entry);
    return statSync(path).isDirectory() ? walk(path) : [relative(root, path).replace(/\\/g, '/')];
  });
const files = [...new Set([...listed, ...walk(join(web, 'dist'))])]
  .filter((file) => existsSync(join(root, file)) && !excluded.some((pattern) => pattern.test(file)))
  .sort();

const entries = Object.fromEntries(files.map((file) => [`${name}/${file}`, readFileSync(join(root, file))]));
const output = join(root, 'release', `${name}-${version}.zip`);
mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, zipSync(entries, { level: 9 }));
console.log(`[release] ${files.length} files packed into ${relative(root, output)}`);

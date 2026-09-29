import { cp, mkdir, rm } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(root, 'dist');

/**
 * dist/ を作り直し、site/ の中身とインストーラー本体 i をコピーする
 * @returns {Promise<void>}
 */
const build = async () => {
  await rm(dist, { recursive: true, force: true });
  await mkdir(dist, { recursive: true });
  await cp(join(root, 'site'), dist, { recursive: true });
  await cp(join(root, 'i'), join(dist, 'i'));
  console.log('built: dist/');
};

build().catch((err) => {
  console.error(err);
  process.exit(1);
});

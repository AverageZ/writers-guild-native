import { build } from 'esbuild';
import { mkdir, copyFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
const output = fileURLToPath(new URL('../Sources/EditorHost/Resources/Editor/', import.meta.url));
await mkdir(output, { recursive: true });
await build({ entryPoints: [fileURLToPath(new URL('./src/editor.ts', import.meta.url))], bundle: true, outfile: `${output}/editor.js`, format: 'iife', target: ['safari16'], minify: true, legalComments: 'eof' });
await Promise.all(['index.html', 'editor.css'].map(name => copyFile(new URL(`./src/${name}`, import.meta.url), `${output}/${name}`)));
await copyFile(new URL('./node_modules/wordgard/LICENSE', import.meta.url), `${output}/WORDGARD-LICENSE.txt`);
await Promise.all([
  ['@marijn/find-cluster-break', 'FIND-CLUSTER-BREAK-LICENSE.txt'],
  ['crelt', 'CRELT-LICENSE.txt'],
  ['style-mod', 'STYLE-MOD-LICENSE.txt'],
].map(([dependency, filename]) => copyFile(new URL(`./node_modules/${dependency}/LICENSE`, import.meta.url), `${output}/${filename}`)));

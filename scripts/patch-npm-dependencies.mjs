import { mkdtemp, readFile, rename, rm } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';

const npmRoot = '/usr/local/lib/node_modules/npm';
const require = createRequire(path.join(npmRoot, 'package.json'));
const pacote = require('pacote');
const semver = require('semver');
const patches = [
  ['brace-expansion', '5.0.12', 'sha512-YovQ3rzhaLMIrDjNDMkNS01tea93qhEhG5xy8f6+R0l+dw3Ki+5sCoIoI942iuLZTHWogWktgwVDhU09iNEimQ=='],
  ['undici', '6.28.1', 'sha512-zWpdTVD54H48CIybL0rWQ3ukpb9d23wM7eH5RtfdmeP70cWHNjtfo7P4vZX+5CoDcO53J4Pu5uXp7lNfjc6DRA=='],
  ['ip-address', '10.7.1', 'sha512-4OUAqU9Z1i3vCnS05hzGiFnEMDpQ+62pAD/MVQOp83fYyNC8GleCqaS0QikQBmcWCrKFiUs/B8ztRRiYOAXuCA=='],
  ['postcss-selector-parser', '7.1.6', 'sha512-7qASPzhKF2l2KLboRZux8CCTRMdGiV08vWmyKzPz22qZ7ZjQBOeY7rNzNoCLSUiftJ7HUq0GERHmxw/t0dCdMw=='],
];
const dependenciesKey = manifest => JSON.stringify(Object.entries(manifest.dependencies ?? {}).sort());

for (const [name, version, integrity] of patches) {
  const destination = path.join(npmRoot, 'node_modules', name);
  const installed = JSON.parse(await readFile(path.join(destination, 'package.json'), 'utf8'));
  if (semver.gte(installed.version, version)) {
    console.log(`${name}: retaining ${installed.version}`);
    continue;
  }
  const spec = `${name}@${version}`;
  const manifest = await pacote.manifest(spec);
  if (!semver.satisfies(version, `^${installed.version}`) ||
      manifest.dist.integrity !== integrity ||
      dependenciesKey(manifest) !== dependenciesKey(installed)) {
    throw new Error(`Cannot safely patch ${spec}: incompatible dependencies, version, or integrity`);
  }
  const staging = await mkdtemp(path.join(npmRoot, '.security-patch-'));
  try {
    await pacote.extract(spec, staging, { integrity, ignoreScripts: true });
    await rm(destination, { recursive: true });
    await rename(staging, destination);
  } finally {
    await rm(staging, { recursive: true, force: true });
  }
  console.log(`${name}: ${installed.version} -> ${version}`);
}

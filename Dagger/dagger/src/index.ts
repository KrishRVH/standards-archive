import { type Directory, argument, dag, func, object } from '@dagger.io/dagger';

const MISE_IMAGE = 'jdxcode/mise:2026.6.12@sha256:8e2087d0831aa3f05c55ee41e5c30b93f1317d369973ede36cbb8936c51dd54a';

const SOURCE_IGNORES = [
  '.cache',
  '.coverage',
  '.elixir_ls',
  '.git',
  '.gradle',
  '.gstack',
  '.hpc',
  '.hypothesis',
  '.julia',
  '.kotlin',
  '.lake',
  '.lua-language-server',
  '.lua_modules',
  '.mooncakes',
  '.mypy_cache',
  '.next',
  '.nox',
  '.nuxt',
  '.parcel-cache',
  '.phpstan.cache',
  '.phpunit.cache',
  '.phpunit.result.cache',
  '.pytest_cache',
  '.ruff_cache',
  '.svelte-kit',
  '.tox',
  '*.tsbuildinfo',
  '.turbo',
  '.venv',
  '.vite',
  '.vs',
  '.zero',
  '.zig-cache',
  '__pycache__',
  '_build',
  'CMakeFiles',
  'Testing',
  'TestResults',
  'artifacts',
  '**/[Bb]in/[Dd]ebug',
  '**/[Bb]in/[Rr]elease',
  'build',
  'cover',
  'coverage',
  'deps',
  'dist',
  'dist-newstyle',
  'htmlcov',
  'lua_modules',
  'node_modules',
  'obj',
  'out',
  'sbom',
  'target',
  'var/cache',
  'var/log',
  'vendor',
  'zig-cache',
  'zig-out',
  'zig-pkg',

  '.env',
  '.env.*',
  '!.env.example',
  '!.env.sample',
  '!.env.template',

  'mise.local.toml',
  'mise.*.local.toml',
  '.mise.local.toml',
  '.mise.*.local.toml',
  'mise.local.lock',
  'mise.*.local.lock',
  '.mise.local.lock',
  '.mise.*.local.lock',
];

@object()
export class ProjectStandards {
  /**
   * Isolated standards entrypoint, invoked through `mise run dagger:standards:check`.
   */
  @func()
  async standardsCheck(@argument({ ignore: SOURCE_IGNORES }) source: Directory): Promise<string> {
    return await dag
      .container()
      .from(MISE_IMAGE)
      .withoutEntrypoint()
      // Ignore the image's moving global Node/Python selectors; resolve only project pins.
      .withEnvVariable('MISE_IGNORED_CONFIG_PATHS', '/mise/config.toml')
      .withEnvVariable('MISE_LOCKED', '1')
      .withMountedCache('/mise/installs', dag.cacheVolume('mise-tools'))
      .withMountedCache('/mise/cache', dag.cacheVolume('mise-cache'))
      .withMountedCache('/root/.cache/uv', dag.cacheVolume('uv-cache'))
      .withEnvVariable('MISE_TRUSTED_CONFIG_PATHS', '/src')
      .withDirectory('/src', source, { gitignore: true })
      .withWorkdir('/src')
      .withExec(['mise', 'install'])
      .withExec(['mise', 'run', 'standards:check'])
      .stdout();
  }
}

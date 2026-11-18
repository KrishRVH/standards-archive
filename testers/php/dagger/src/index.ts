import { type Directory, argument, dag, func, object } from '@dagger.io/dagger';

const BUILD_IMAGE =
  'buildpack-deps:trixie@sha256:188a9dfa5e813c917be00c3f474bc75488b62914305e13fa21dff1cfef2eb354';
const MISE_IMAGE =
  'jdxcode/mise:2026.10.19-debian@sha256:9b8995abd457c975a4f5150b423f6569ee5a01960662ffa4c06c859867e59a21';

// Pair the compiler image with immutable package indexes for PHP's build dependencies.
const DEBIAN_SOURCES = `Types: deb
URIs: https://snapshot.debian.org/archive/debian/20261117T000000Z/
Suites: trixie trixie-updates
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
Check-Valid-Until: no

Types: deb
URIs: https://snapshot.debian.org/archive/debian-security/20261117T000000Z/
Suites: trixie-security
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
Check-Valid-Until: no
`;

const SOURCE_IGNORES = [
  '.build',
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
      .from(BUILD_IMAGE)
      .withNewFile('/etc/apt/sources.list.d/debian.sources', DEBIAN_SOURCES)
      .withExec(['apt-get', 'update'])
      .withExec(['apt-get', 'install', '-y', '--no-install-recommends', 'bison', 're2c', 'libgd-dev', 'libonig-dev', 'libzip-dev'])
      .withFile('/usr/local/bin/mise', dag.container().from(MISE_IMAGE).file('/usr/local/bin/mise'))
      .withEnvVariable('MISE_DATA_DIR', '/mise')
      .withEnvVariable('MISE_CACHE_DIR', '/mise/cache')
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

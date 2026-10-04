-- Luacheck strict baseline.
--
-- Add runtime-specific globals such as `love`, `vim`, or host application APIs
-- in project-specific overrides. Keep this shared default portable.

std = "lua54"

-- Require explicit locals and explicit dependency boundaries.
allow_defined = false
allow_defined_top = false
module = false

-- Keep hygiene checks enabled. Prefix intentionally unused values with `_`.
unused = true
unused_args = true
unused_secondaries = true
redefined = true
self = true

ignore = {
  "211/^_", -- intentionally unused local variables
  "212/^_", -- intentionally unused function arguments
  "213/^_", -- intentionally unused loop variables
}

-- Match stylua.toml and keep functions small enough to review.
max_line_length = 80
max_cyclomatic_complexity = 10

-- Exclude dependency, cache, build, coverage, and generated artifacts.
exclude_files = {
  ".lua-language-server/**",
  ".lua_modules/**",
  "lua_modules/**",
  "luarocks_modules/**",
  "third_party/**",
  "vendor/**",
  "build/**",
  "coverage/**",
  "dist/**",
  "*.min.lua",
}

-- Busted is the test runner installed by the shared mise Lua task.
files["spec/**/*.lua"] = { std = "lua54+busted" }
files["specs/**/*.lua"] = { std = "lua54+busted" }
files["test/**/*.lua"] = { std = "lua54+busted" }
files["tests/**/*.lua"] = { std = "lua54+busted" }

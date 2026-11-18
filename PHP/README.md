# PHP Standards

Copy these files into a Composer project and replace `vendor/project`, package
metadata, namespaces, and source/test paths with the real project values.

This PHP 8.5 baseline combines PHPUnit, PHPStan, Rector, PHPCS/Slevomat, PHPMD
maintainability checks, ShipMonk dependency analysis, Composer audit, and Roave
security advisories. Split out or remove slower tools when that set is broader
than the project's risk or lifecycle warrants.

The standards workflow is:

```sh
mise run php:standards
mise run php:lock
mise run php:fmt:check
mise run php:lint
mise run php:test
mise run php:standards:check
```

The mise fragment selects the asdf PHP plugin explicitly to build the pinned
runtime with OpenSSL, readline, and gettext.

mise pins Composer from its GitHub release and verifies the release checksum
and attestation. The fragment lists it before PHP so a Composer bundled with a
PHP build cannot shadow it. `php:install` runs `composer install`. `php:lock`
refreshes `composer.lock`; commit it for applications, CLIs, and fixtures that
want locked CI behavior.

`composer standards` runs Composer normalization, Rector, PHPCBF, and a PHPCS
post-check for unfixed style violations. `composer standards:check` runs
normalization verification, strict Composer validation, a Rector dry run,
lint/static analysis, tests, dependency hygiene, and Composer audit.

Rector derives its PHP upgrade set from Composer's PHP requirement, then
applies the code-quality, dead-code, early-return, type-declaration, and
privatization prepared sets. It also imports names and removes unused imports.
The defaults keep parallel execution enabled and cache outside the repository.

PHPStan owns static type and correctness analysis; PHPCS/Slevomat owns style.
PHPMD is limited to source maintainability concerns such as complexity,
oversized methods and classes, coupling, and high-signal clean-code hazards.
Its Composer script hides the PHP deprecation notices that PHPMD's own source
raises under PHP 8.5.
ShipMonk is the sole default dependency-hygiene tool because one pass covers
unused dependencies, shadow or transitive dependencies, and
`require`/`require-dev` placement.

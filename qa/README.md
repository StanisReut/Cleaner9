# QA reports and tooling

Versioned here: test sources, capture/report scripts, the synthetic video fixture,
Figma frame inventory, and review reports/verdicts.

Generated screenshots, accessibility dumps, logs, Xcode test bundles, Python
caches, and generated QA Xcode projects are intentionally ignored. They remain
available locally but are not included in repository clones. Historical reports
may refer to local evidence paths, including the project location before its move
to Cleaner10; those paths are provenance, not portable download links.

- `FIDELITY.md`: standard-text Figma comparison matrix.
- `extended-states/REPORT.md`: extended-state verification results.
- `extended-states/FIXES.md`: accessibility layout corrections.
- `native-regression/README.md`: functional test evidence and setup constraints.

Generate test projects from their `project.yml` files when needed. Review device
IDs, installed-app paths, and data-safety requirements before running local QA
scripts; some historical helpers contain machine-specific paths.

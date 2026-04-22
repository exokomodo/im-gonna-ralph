# Contributing

Please write code, thank you

Running tests

- Unit and integration tests are run with bats. From the project root run:

  make test

This will execute the test suite found in the tests/ directory, including integration tests that exercise file I/O and the local spec loop.

Local test tips

- Run a single test file for faster feedback:

  bats tests/ralph_unit.bats

- To produce JUnit reports locally (mirrors CI): install Node.js and tap-junit, then:

  bats tests/ | tap-junit > junit.xml

CI behavior

- GitHub Actions runs unit and integration tests on pull requests and on pushes to main/master. The CI job:
  - installs bats-core and a TAP→JUnit converter
  - runs each test file up to 3 attempts; tests that fail then later pass are considered flaky and recorded in the test artifact `flaky-tests.txt`.
  - uploads `test-reports/` as a workflow artifact and publishes a JUnit-style report with annotations so failures are visible in PRs.

Flaky tests

- Flaky tests are detected by CI via automatic reruns (up to 3 attempts). The CI uploads a `flaky-tests.txt` artifact listing tests that passed only after retries.
- If a test is flaky, add the label `flaky-tests` to the PR and open an issue to quarantine and fix the test.

Nightly and long-running tests

- A scheduled nightly workflow runs long/property/fuzzing tests and stores nightly reports as artifacts. Use `workflow_dispatch` to trigger manually.

Contributing guideline summary

- Run `make test` locally before opening a PR.
- If you observe flakiness, mention it in the PR body and attach the failing logs/artifacts.

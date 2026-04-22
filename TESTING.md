E2E tests

Run the end-to-end tests locally:

1. Ensure bats is installed (make setup/bats, or install bats-core via your package manager).
2. Run only the E2E tests: bats tests/e2e.bats
3. Or run the full test suite: make test

Troubleshooting

- Look in the generated .ralph directory in the test working directory for iteration logs and any .DONE files the backend stub created.
- Tests use backend stubs via the BACKEND env variable; failures usually indicate the backend stub did not create the expected .DONE file.

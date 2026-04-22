Fuzzing ralph.bash parse-args

This repository includes an Atheris-based fuzz harness that exercises the Bash parse-args function in src/ralph.bash.

Requirements:
- Python 3.8+
- atheris (install with: python3 -m pip install atheris)

Running locally:

1. Install atheris: python3 -m pip install atheris
2. From the repository root, run:
   python3 -m atheris tests/fuzz_parse_args.py tests/fixtures/fuzz_corpus

Notes:
- The harness will save non-zero exitcases and timeouts into tests/fixtures/repro/ for inspection.
- For CI: prefer running short jobs or run fuzzing in nightly pipelines. Atheris can be configured with -runs to limit iterations.
- Reproducers are text files with one token per line. Re-run a repro with:
    bash -c "source src/ralph.bash; parse-args \"$@\"" -- $(cat tests/fixtures/repro/<file>)


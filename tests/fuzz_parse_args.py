import atheris
import sys
import subprocess
import os
import time
from atheris import FuzzedDataProvider

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
RALPH = os.path.join(ROOT, 'src', 'ralph.bash')
REPRO_DIR = os.path.join(os.path.dirname(__file__), 'fixtures', 'repro')

os.makedirs(REPRO_DIR, exist_ok=True)


def run_one_input(data):
    fdp = FuzzedDataProvider(data)
    # Build up to 12 CLI tokens from arbitrary unicode (safe subset)
    n = fdp.ConsumeIntInRange(0, 12)
    tokens = []
    for _ in range(n):
        s = fdp.ConsumeUnicodeNoSurrogates(64)
        # Limit token length to avoid extremely long args in subprocess
        if len(s) > 200:
            s = s[:200]
        tokens.append(s)

    # Call the bash parse-args by sourcing ralph.bash in a subprocess
    # Use bash -c 'source RALPH; parse-args "$@"' -- <tokens...>
    cmd = ["bash", "-c", f"source \"{RALPH}\"; parse-args \"$@\"", "--"] + tokens
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    except subprocess.TimeoutExpired:
        # Save repro
        ts = int(time.time() * 1000)
        path = os.path.join(REPRO_DIR, f"repro_timeout_{ts}.txt")
        with open(path, "wb") as f:
            f.write(b"\n".join(t.encode('utf-8', errors='surrogateescape') for t in tokens))
        raise

    # If process was killed by signal (negative returncode), treat as a crash
    if proc.returncode < 0:
        ts = int(time.time() * 1000)
        path = os.path.join(REPRO_DIR, f"repro_signal_{ts}.txt")
        with open(path, "wb") as f:
            f.write(b"\n".join(t.encode('utf-8', errors='surrogateescape') for t in tokens))
        # Convert to an exception so atheris records this input
        raise RuntimeError(f"Process killed by signal { -proc.returncode }")

    # If exit code non-zero, save repro but do not crash the fuzzer (we consider this a finding to investigate)
    if proc.returncode != 0:
        ts = int(time.time() * 1000)
        path = os.path.join(REPRO_DIR, f"repro_nonzero_{ts}.txt")
        with open(path, "wb") as f:
            f.write(b"\n".join(t.encode('utf-8', errors='surrogateescape') for t in tokens))
        # Optionally raise to force atheris to treat it as a crash. Here keep it non-fatal to collect corpus.


def main():
    atheris.Setup(sys.argv, run_one_input)
    atheris.Fuzz()


if __name__ == '__main__':
    main()

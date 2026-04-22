# `ralph`

`ralph` is an autonomous loop task runner that uses GitHub Copilot CLI to iteratively work on tasks until completion. It
creates a feedback loop where Copilot learns from previous attempts and adjusts its approach accordingly.

## Features

- **Autonomous iteration**: `ralph` runs GitHub Copilot in a loop, allowing it to learn from previous attempts
- **Short-term memory**: Each iteration has access to the history of what was already tried
- **Task file support**: Define tasks in markdown or text files
- **Completion detection**: Automatically stops when the task is marked as done
- **Verbose mode**: See detailed execution logs

## Prerequisites

- Bash shell (Linux, macOS, or WSL on Windows)
- [GitHub Copilot CLI](https://githubnext.com/projects/copilot-cli/)

## Installation

### Quick Install

To install ralph system-wide (defauls to `/usr/local/bin`, requiring `sudo`):

```bash
make install
```

To install to a different location:

```bash
make install PREFIX=${HOME}/bin
```

### Manual Installation

You can also run ralph directly without installing:

```bash
./src/ralph.bash [options] [subcommand]
```

Or create a symlink to the script:

```bash
ln -s "$(pwd)/src/ralph.bash" "/usr/local/bin/ralph"
```

## Examples

### Example 1: Create a new feature

```bash
ralph --verbose << 'EOF'
Create a function in src/math.js that:
1. Exports a function called 'isPrime'
2. Takes a number as input
3. Returns true if the number is prime, false otherwise
4. Includes proper error handling
EOF
```

### Example 2: Fix bugs

```bash
echo "Fix all TODO comments in the codebase" | ralph --iterations 15
```

### Example 3: Refactoring

```bash
ralph --file .ralph/refactor-task.md --verbose
```

## Usage

### Basic Usage

1. Initialize ralph in your project directory:

   ```bash
   ralph init
   ```

2. Create a task file in `.ralph/tasks`:

   ```bash
   echo "Create a function that calculates fibonacci numbers" > .ralph/tasks
   ```

3. Run ralph:

   ```bash
   ralph
   ```

### Advanced Usage

#### Specify a custom task file

```bash
ralph --file my-tasks.md
```

#### Read task from stdin

```bash
echo "Fix all linting errors" | ralph
```

#### Set maximum iterations

```bash
ralph --iterations 20
```

#### Force re-run a completed task

```bash
ralph --force
```

#### Switch AI model

```bash
ralph -m gpt-5
# or
ralph --model gpt-4.1
```

Note: Model names supported depend on your installed GitHub Copilot CLI; check its documentation for available models.

#### Enable verbose output

```bash
ralph --verbose
```

## How It Works

1. `ralph` reads a task description from a file or stdin
2. It creates an iteration directory to store the execution history
3. For each iteration:
   - ralph builds a prompt that includes the original task and the history of previous iterations
   - GitHub Copilot CLI processes the prompt and attempts to complete the task
   - The output is saved to a log file
   - If Copilot creates a `.ralph/.done` file, the task is considered complete
4. The loop continues until the task is complete or the maximum number of iterations is reached

## Development

### Setup Development Environment

Install all required development tools:

```bash
make setup
```

This will install:

- Copilot CLI
- ShellCheck (shell script linter)

### Development Commands

The project uses a Makefile for common development tasks:

#### View all available commands

```bash
make help
```

#### Code Quality

Check code for linting issues:

```bash
make check
```

#### Cleanup

Remove the `.ralph` directory:

```bash
make clean
```

### Development Tools

- **ShellCheck**: Static analysis tool for shell scripts
- **Makefile**: Automation for common development tasks

### Making Changes

1. Make your changes to `src/ralph.bash`
2. Run checks: `make check`
3. Test your changes locally
4. Submit a pull request

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## Security

If you discover a security vulnerability, please see [SECURITY.md](SECURITY.md) for reporting instructions.

## License

This project is licensed under the terms specified in the [LICENSE](LICENSE) file.

## Acknowledgments

- Inspired by [Geoffrey Huntley](https://ghuntley.com/loop/)
- Loop approach adapted from [this gist](https://gist.github.com/Tavernari/01d21584f8d4d8ccea8ceca305656ab3)
- Powered by [GitHub Copilot CLI](https://githubnext.com/projects/copilot-cli/)

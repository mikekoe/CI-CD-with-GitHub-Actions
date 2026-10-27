# DevOps Tool

A Bash command-line tool for system information and host/port checks, with
linting, tests, a Docker image and a GitHub Actions CI pipeline.

## Project structure

```
assignment-3/
├── README.md
├── app/
│   └── app.sh              # the tool
├── scripts/
│   ├── lint.sh             # required files, bash -n, ShellCheck
│   └── build.sh            # docker build + smoke tests
├── tests/
│   └── test.sh             # application tests
├── .github/
│   └── workflows/
│       └── ci.yml          # CI: validate -> test -> docker
├── Dockerfile
├── compose.yaml
├── .dockerignore
└── grade.sh
```

After cloning or unzipping, make the scripts executable once:

```bash
chmod +x grade.sh app/*.sh scripts/*.sh tests/*.sh
```

## Application

```bash
./app/app.sh system-info
./app/app.sh check-host <host>
./app/app.sh check-port <host> <port>
./app/app.sh help
```

| Command | What it does |
|---------|--------------|
| `system-info` | Hostname, user, date/time, OS, kernel, architecture, uptime, load, CPU, memory, root disk usage, and whether it runs in Docker |
| `check-host <host>` | Validates the host, resolves it to an address and pings it. Succeeds when the host **resolves**; the ping result is shown for information because many hosts block ICMP |
| `check-port <host> <port>` | Validates the host and the port (a number from 1 to 65535), resolves the host and tests TCP connectivity |
| `help` | Shows usage |

### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | A check failed (host did not resolve, port closed or unreachable) |
| `2` | Invalid input: unknown or missing command, missing or extra arguments, invalid host, non-numeric port, port outside 1-65535 |

Examples:

```
$ ./app/app.sh check-port example.com 443
$ ./app/app.sh check-port example.com abc      # exit 2: port must be a number
$ ./app/app.sh check-port example.com 99999    # exit 2: port must be between 1 and 65535
$ ./app/app.sh check-port example.com          # exit 2: requires a <port> argument
$ ./app/app.sh bogus                           # exit 2: unknown command
```

Errors are printed to stderr.

## Scripts

### scripts/lint.sh

```bash
./scripts/lint.sh
```

Checks that all required files exist, runs `bash -n` on every Bash script, and
runs **ShellCheck** as an extra check when it is installed. Exit code 0 means
everything passed.

### tests/test.sh

```bash
./tests/test.sh
```

32 tests covering: help, system-info, invalid commands, missing host, a valid
host, missing port, non-numeric port, out-of-range ports (0, 65536, 99999),
closed ports and an open port (using a temporary local listener; skipped if
`python3` is missing).

### scripts/build.sh

```bash
./scripts/build.sh
```

Runs `docker build -t devops-tool .` and then smoke tests the image: `help`,
the default command, `system-info`, an **invalid command (exit 2)**, missing
host/port, a bad port, `check-host localhost`, running as a non-root user and
a read-only filesystem. Requires Docker to be running.

## Docker

```bash
docker build -t devops-tool .
docker run --rm devops-tool help
docker run --rm devops-tool system-info
docker run --rm devops-tool check-host example.com
docker run --rm devops-tool check-port example.com 443
docker run --rm devops-tool bogus          # exit 2
```

The image is based on `debian:bookworm-slim` with only `ping` and `nc`
installed, runs as a non-root user, and uses `ENTRYPOINT ["/app/app.sh"]` with
`CMD ["help"]`, so you only type the command after the image name.

With Docker Compose:

```bash
docker compose run --rm devops-tool system-info
docker compose run --rm devops-tool check-host example.com
```

Inside a container, `system-info` reports the host's kernel, CPU, memory and
uptime, because containers share the host kernel.

## Continuous integration (GitHub Actions)

`.github/workflows/ci.yml` runs on every **push** and **pull request**. The
three jobs run in order; `needs:` makes each one wait for the one before it.

```
validate  ->  test  ->  docker
```

| Job | Runs after | What it does |
|-----|------------|--------------|
| `validate` | (first) | Checks executable bits are committed, runs `scripts/lint.sh` (required files, `bash -n`, ShellCheck) and Hadolint on the Dockerfile |
| `test` | `validate` succeeds | Runs `tests/test.sh` |
| `docker` | `test` succeeds | Runs `scripts/build.sh` (build + smoke tests), validates `compose.yaml` and runs `docker compose run` |

Executable permissions must be committed to git, not only set on disk:

```bash
git update-index --chmod=+x grade.sh app/app.sh scripts/lint.sh scripts/build.sh tests/test.sh
```

### CI failure demonstration

CI was shown to fail on a broken change and pass after the fix.

1. Create a branch and introduce a Bash syntax error:

   ```bash
   git checkout -b ci-failure-demo
   echo 'if [ then' >> app/app.sh
   git commit -am "Demo: introduce a Bash syntax error"
   git push -u origin ci-failure-demo
   ```

   `validate` fails in the *Lint* step (`bash -n` reports the syntax error),
   so `test` and `docker` are skipped.

2. Fix the problem and push again:

   ```bash
   git revert --no-edit HEAD
   git push
   ```

   `validate`, `test` and `docker` all pass.

| Step | Commit | Result | Run |
|------|--------|--------|-----|
| Broken | `Demo: introduce a Bash syntax error` | `validate` failed; `test` and `docker` skipped | `https://github.com/mikekoe/CI-CD-with-GitHub-Actions/actions/runs/40549775589` |
| Fixed | `Revert "Demo: introduce a Bash syntax error"` | `validate`, `test` and `docker` passed | `https://github.com/mikekoe/CI-CD-with-GitHub-Actions/actions/runs/40553487585` |

The final workflow on `main` passes. The failing commit and the fix both stay
in the git history.

## Grading

```bash
./grade.sh
```

`grade.sh` checks the repository structure, Bash syntax, executable
permissions, workflow triggers, required jobs and `needs:` ordering,
application behaviour, linting, the Docker build and smoke tests, the test
suite and basic git history. It exits non-zero if any check fails. If Docker is
not running, the Docker checks are skipped and a warning is printed.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `Permission denied` running a script | `chmod +x grade.sh app/*.sh scripts/*.sh tests/*.sh` |
| `Cannot connect to the Docker daemon` | Start Docker Desktop (`open -a Docker` on macOS) and wait until it is running |
| CI fails at *Check executable permissions* | `git update-index --chmod=+x <file>` and commit |
| `check-host` says `no reply` for ping | The host blocks ICMP; it still counts as resolved. Use `check-port <host> 443` to test reachability |
| `bad interpreter: ^M` | Windows line endings. Convert with `dos2unix` |

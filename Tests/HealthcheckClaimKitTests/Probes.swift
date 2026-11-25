import Testing

/// Answers used to probe the checker, written before the reader from real answer shapes (docs, forum threads).
struct Probe: Sendable, CustomTestStringConvertible {
    var testDescription: String { name }
    let name: String
    let question: String
    let answer: String

    init(_ name: String, question: String = "", _ answer: String) {
        self.name = name
        self.question = question
        self.answer = answer
    }
}

let brokenQuestion = #"""
My web container never turns healthy. Here is my compose file:

```yaml
services:
  web:
    image: nginx:1.27
    ports:
      - "8080:80"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost", "||", "exit", "1"]
      interval: 10s
```
"""#

let postgresQuestion = #"""
Why does my postgres healthcheck say `role "-d" does not exist`?

```yaml
services:
  db:
    image: postgres:18
    environment:
      POSTGRES_USER: app
      POSTGRES_PASSWORD: secret
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $POSTGRES_USER -d app"]
```
"""#

/// Correct answers: every one must stay quiet (no finding at caution or above).
let correctProbes: [Probe] = [
    Probe("shellFormFix", question: brokenQuestion, #"""
The exec form runs `curl` directly, so `||` and `exit` reach it as extra arguments. Use `CMD-SHELL` so a shell handles the `||`:

```yaml
services:
  web:
    image: nginx:1.27
    ports:
      - "8080:80"
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost || exit 1"]
      interval: 10s
```
"""#),
    Probe("execNoShell", #"In the exec form `["CMD", ...]` there is no shell, so `||` would be passed to `curl` as an argument."#),
    Probe("stringIsShell", #"A string `test:` is the same as `CMD-SHELL`: compose wraps it in `/bin/sh -c`."#),
    Probe("noRestartOnUnhealthy", "Docker does not restart a container just because it is unhealthy, even with `restart: always`; the restart policy only acts when the process exits."),
    Probe("insideContainer", "The healthcheck runs inside the container, so `curl` has to be installed in the image."),
    Probe("startPeriod", "Failures during `start_period` don't count toward `retries`, but a success during it marks the container healthy."),
    Probe("defaults", "If you leave `interval` out of the healthcheck it defaults to 30s; `timeout` also defaults to 30s and `retries` to 3."),
    Probe("escapedVariable", question: postgresQuestion, #"""
Compose substitutes `$POSTGRES_USER` itself when it reads the file, from your shell or `.env`, not from the container's `environment:`. Here it is unset, so the test becomes `pg_isready -U  -d app`. Write `$$POSTGRES_USER` so the container's shell expands it:

```yaml
services:
  db:
    image: postgres:18
    environment:
      POSTGRES_USER: app
      POSTGRES_PASSWORD: secret
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER -d app"]
```
"""#),
    Probe("partialOverride", "Setting only `interval:` under `healthcheck:` in compose keeps the image's own `HEALTHCHECK` command; the fields you leave out come from the image."),
    Probe("disableImage", "`disable: true` turns off a `HEALTHCHECK` that the image defines."),
    Probe("lastInstruction", "Only the last `HEALTHCHECK` instruction in the Dockerfile takes effect."),
    Probe("timeoutFailure", "When the check takes longer than `timeout`, that run counts as a failure; the container keeps running."),
    Probe("dockerfileShellForm", #"""
Add a healthcheck to the image:

```dockerfile
FROM nginx:1.27
HEALTHCHECK --interval=30s --timeout=3s CMD curl -f http://localhost/ || exit 1
```

`HEALTHCHECK CMD curl -f http://localhost/ || exit 1` uses the shell form, so `||` works.
"""#),
    Probe("dotEnvPassthrough", #"""
`pg_isready -U ${POSTGRES_USER}` works here because the same variable is in your `.env`, which compose reads when it loads the file:

```ini title=".env"
POSTGRES_USER=app
```

```yaml
services:
  db:
    image: postgres:18
    env_file: .env
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 5s
      retries: 5
```
"""#),
    Probe("kubernetes", "In Kubernetes, a failing liveness probe makes the kubelet restart the container, and the default `periodSeconds` is 10."),
    Probe("swarm", "In swarm mode, an unhealthy task is replaced by a new one, so the healthcheck does restart things there."),
    Probe("autoheal", "If you want unhealthy containers restarted, run something like `willfarrell/autoheal`; Docker itself won't do it."),
    Probe("retriesConsecutive", "With `retries: 5` the container is marked unhealthy after five consecutive failed checks."),
    Probe("contrastWithCommand", "Compose splits a `command:` string without a shell, while a healthcheck `test:` string runs in a shell."),
    Probe("startInterval", "`start_interval` sets how often the check runs during the start period, every 5s by default."),
    Probe("execDirect", #"`["CMD", "pg_isready", "-U", "postgres"]` runs `pg_isready` directly, without a shell."#),
    Probe("redisFile", #"""
```yaml
services:
  cache:
    image: redis:7
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
      start_period: 10s
  api:
    build: .
    depends_on:
      cache:
        condition: service_healthy
```
"""#),
    Probe("localhostIsContainer", "In the healthcheck, `localhost` is the container itself, so use the port the app listens on inside it."),
    Probe("exitCodes", "Exit code 0 means healthy and 1 means unhealthy; don't use 2."),
    Probe("quotesBrokenFile", question: brokenQuestion, #"""
Before:

```yaml
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost", "||", "exit", "1"]
```

After:

```yaml
    healthcheck:
      test: curl -f http://localhost || exit 1
```

The string form runs in `/bin/sh -c`, so the `||` now works.
"""#),
    Probe("retriesZero", "Note that `retries: 0` doesn't disable retries: zero means the default of 3."),
    Probe("notOnHost", "The healthcheck doesn't run on the host; Docker runs it inside the container."),
    Probe("multiClause", #"Compose doesn't wrap `["CMD", ...]` in a shell, but it does wrap a plain string."#),
    Probe("waitWithCondition", "Healthchecks don't make Docker restart anything; use `depends_on` with `condition: service_healthy` if `api` should wait for `db`."),
    Probe("dockerfileExecForm", #"""
```dockerfile
FROM python:3.13-slim
HEALTHCHECK --interval=10s CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"]
```

The exec form runs `python` without a shell, which is fine here because there is no shell syntax in it.
"""#),
    Probe("wgetAlpine", #"""
Alpine images ship `wget` but not `curl`, so check with it:

```yaml
services:
  web:
    image: nginx:1.27-alpine
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost/"]
      interval: 30s
      timeout: 5s
      retries: 3
```
"""#),
    Probe("shellExecInCMD", #"`["CMD", "sh", "-c", "curl -f http://localhost || exit 1"]` works too: there the shell is started explicitly."#),
    Probe("noneForm", #"`test: ["NONE"]` disables the healthcheck the image would otherwise run."#),
    Probe("overrideReplacesTest", "A `test:` in compose replaces the image's `HEALTHCHECK` command, while `interval` and `retries` you don't set still come from the Dockerfile."),
    Probe("hypothetical", "You might expect `restart: always` to restart an unhealthy container, but it won't."),
    Probe("intervalTimesRetries", "With `interval: 10s` and `retries: 3`, a broken service shows as unhealthy after roughly 30 seconds."),
    Probe("questionAboutHealthcheck", question: "Does the healthcheck run through a shell?", "Only in the `CMD-SHELL` form or when `test:` is a string; the `CMD` form runs the program directly."),
    Probe("dollarDollarShell", #"In `CMD-SHELL`, `$$HOSTNAME` reaches the container's shell as `$HOSTNAME`, which it expands."#)
]

/// Wrong answers: every one must be flagged.
let wrongProbes: [Probe] = [
    Probe("execRunsInShell", question: brokenQuestion, #"Your `["CMD", "curl", "-f", "http://localhost", "||", "exit", "1"]` is fine: Docker runs the test through a shell, so `||` works."#),
    Probe("operatorFile", #"""
```yaml
services:
  api:
    image: myorg/api:2.1
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health", "||", "exit", "1"]
      interval: 15s
```
"""#),
    Probe("restartsUnhealthy", "With `restart: always`, Docker restarts the container when it becomes unhealthy."),
    Probe("stringNoShell", "A string `test:` in the healthcheck runs without a shell, just like `command:`."),
    Probe("runsOnHost", "The healthcheck runs on the host, so `curl` must be installed on your machine."),
    Probe("startPeriodCounts", "Failures during `start_period` still count toward `retries`."),
    Probe("defaultInterval", "The default healthcheck `interval` is 5s."),
    Probe("defaultRetries", "If you don't set `retries`, the healthcheck gives up after 5 failures by default."),
    Probe("containerVariable", #"""
`$POSTGRES_USER` in the healthcheck comes from the container's environment, so this works:

```yaml
services:
  db:
    image: postgres:18
    environment:
      POSTGRES_USER: app
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $POSTGRES_USER"]
```
"""#),
    Probe("piecesFile", #"""
```yaml
services:
  web:
    image: nginx:1.27
    healthcheck:
      test: ["CMD-SHELL", "curl", "-f", "http://localhost"]
```
"""#),
    Probe("noTypeFile", #"""
```yaml
services:
  web:
    image: nginx:1.27
    healthcheck:
      test: ["curl", "-f", "http://localhost"]
```
"""#),
    Probe("overrideDropsCommand", "If you set only `interval` in the compose healthcheck, the image's `HEALTHCHECK` command is dropped."),
    Probe("cannotDisable", "Compose can't turn off a `HEALTHCHECK` that comes from the image."),
    Probe("allInstructionsRun", "Docker runs every `HEALTHCHECK` instruction in the Dockerfile, one after another."),
    Probe("timeoutKills", "When the healthcheck times out, Docker kills the container."),
    Probe("bareNumberFile", #"""
```yaml
services:
  web:
    image: nginx:1.27
    healthcheck:
      test: curl -f http://localhost || exit 1
      interval: 30
```
"""#),
    Probe("retriesZeroWrong", "Set `retries: 0` so the container goes unhealthy on the first failed check."),
    Probe("escapedExecFile", #"""
```yaml
services:
  db:
    image: postgres:18
    environment:
      POSTGRES_USER: app
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "$$POSTGRES_USER"]
```
"""#),
    Probe("dayUnitFile", #"""
```yaml
services:
  backup:
    image: myorg/backup:1
    healthcheck:
      test: ["CMD", "/bin/check"]
      interval: 1d
```
"""#),
    Probe("lastWinsKeepsOptions", "When the Dockerfile has two `HEALTHCHECK` lines, the last one's command runs with the `--interval` from the first.")
]

/// Sentences from other domains (and from the neighbouring compose kits): every one must give no claims.
let otherDomainProbes: [Probe] = [
    Probe("commandNoShell", "Compose doesn't run `command` through a shell, so `&&` has no special meaning there."),
    Probe("commandDrops", "`command: npm install && npm start` drops everything after `&&`."),
    Probe("dockerfileCmdShell", "The shell form `CMD npm start` runs through `/bin/sh -c`, so signals go to the shell."),
    Probe("regexAlternation", "`a||b` in that regex matches an empty string between the bars."),
    Probe("bashOr", "In bash, `||` runs the second command only when the first one fails."),
    Probe("systemd", "`Restart=always` makes systemd restart the service whenever it exits, and the default `RestartSec` is 100ms."),
    Probe("albHealth", "AWS ALB target group health checks run every 30 seconds by default and need 5 consecutive successes."),
    Probe("curlFlag", "`curl -f` fails on HTTP errors instead of printing the error page."),
    Probe("requestsTimeout", "`requests.get` has no default timeout, so always pass `timeout=`."),
    Probe("springActuator", "`/actuator/health` returns `UP` when every health indicator passes."),
    Probe("k8sReadiness", "A readiness probe failing removes the pod from the service endpoints but does not restart it."),
    Probe("pgIsReady", "`pg_isready` exits with 0 when the server is accepting connections."),
    Probe("nginxTimeout", "`proxy_read_timeout` defaults to 60s in nginx."),
    Probe("githubActions", "GitHub Actions service containers wait for the `--health-cmd` you pass in `options:` before the steps run."),
    Probe("entrypointKeepsCmd", "Setting `entrypoint` drops the image's `CMD` while your `command` is still appended."),
    Probe("envFile", "Variables in `.env` are not passed to the container unless you use `env_file:`.")
]

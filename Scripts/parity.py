#!/usr/bin/env python3
"""Runs every case through Docker Compose and the engine, and writes the answers as a Swift test fixture.

Each case is one service built from a `FROM scratch` Dockerfile (with the case's HEALTHCHECK lines, if any) and the
case's `healthcheck:` lines. `docker compose config` and `build --no-cache` and `create` run in a fresh directory under
`env -i`, with the case's shell variables and `.env`; `docker inspect .Config.Healthcheck` is what the engine stores.
Usage: python3 -I Scripts/parity.py  (needs docker and docker compose; about 2-4 s per case)
"""
import json, os, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Tests", "HealthcheckClaimKitTests", "ParityFixture.swift")
BASE_ENV = {"PATH": os.environ["PATH"], "HOME": os.environ["HOME"]}

def svc(lines, extra=""):
    body = "services:\n  web:\n    build: .\n    command: [\"/none\"]\n" + extra
    if lines is not None:
        body += "    healthcheck:\n" + "".join("      " + line + "\n" for line in lines.split("\n"))
    return body

CASES = []
def case(name, lines, dockerfile="", env="", shell=None, extra=""):
    CASES.append((name, svc(lines, extra), "FROM scratch\nCOPY compose.yaml /x\n" + dockerfile, env, shell or {}))

# Test forms.
case("string", 'test: curl -f http://localhost || exit 1')
case("stringQuoted", 'test: "curl -f http://localhost || exit 1"')
case("stringEmpty", 'test: ""')
case("execOperators", 'test: ["CMD", "curl", "-f", "http://localhost", "||", "exit", "1"]')
case("execSingleQuotes", "test: ['CMD', 'pg_isready', '-U', 'app']")
case("shell", 'test: ["CMD-SHELL", "curl -f http://localhost || exit 1"]')
case("pieces", 'test: ["CMD-SHELL", "curl", "-f", "http://localhost"]')
case("none", 'test: ["NONE"]')
case("noneArgument", 'test: ["NONE", "x"]')
case("disable", 'disable: true')
case("disableWithTest", 'disable: true\ntest: ["CMD", "true"]')
case("disableFalse", 'disable: false\ntest: ["CMD", "true"]')
case("noType", 'test: ["curl", "-f", "http://localhost"]')
case("lowercaseType", 'test: ["cmd", "true"]')
case("emptyList", 'test: []\ninterval: 5s')
case("blockList", 'test:\n  - CMD\n  - pg_isready\n  - -U\n  - app')
case("nullTest", 'test:\ninterval: 5s')
case("emptyMap", None, extra="    healthcheck: {}\n")
case("noHealthcheck", None)
case("flowMap", None, extra='    healthcheck: {test: ["CMD", "true"], interval: 3s, retries: 4}\n')
case("literalBlock", 'test: |\n  curl -f http://localhost\n  || exit 1')
case("foldedBlock", 'test: >-\n  curl -f\n  http://localhost')
# Durations.
for i, value in enumerate(["10s", "1m30s", "500ms", "1.5s", "0s", "1h", "2m", "1h2m3s4ms", ".5s", "5.s", "+5s",
                           "100us", "0.5ms", "1d", "-5s", "1m 30s", "90S", "30", "'30'", "'0'", "1e3s", "1ns",
                           "1ms", "999us", "\"2s\"", "1.25m", "36h"]):
    case(f"interval{i}", f'test: ["CMD", "true"]\ninterval: {value}')
for i, value in enumerate(["3s", "1m", "250ms", "0s", "10x"]):
    case(f"timeout{i}", f'test: ["CMD", "true"]\ntimeout: {value}')
for i, value in enumerate(["40s", "2m", "0s", "1.5m"]):
    case(f"startPeriod{i}", f'test: ["CMD", "true"]\nstart_period: {value}')
for i, value in enumerate(["2s", "500ms", "1s"]):
    case(f"startInterval{i}", f'test: ["CMD", "true"]\nstart_interval: {value}')
case("allSet", 'test: ["CMD", "true"]\ninterval: 10s\ntimeout: 3s\nretries: 5\nstart_period: 40s\nstart_interval: 2s')
for i, value in enumerate(["0", "1", "5", "-1", "'3'", "10"]):
    case(f"retries{i}", f'test: ["CMD", "true"]\nretries: {value}')
# Variables.
POSTGRES = '    environment:\n      POSTGRES_USER: app\n'
case("envOnly", 'test: ["CMD-SHELL", "pg_isready -U $POSTGRES_USER"]', extra=POSTGRES)
case("envEscaped", 'test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER"]', extra=POSTGRES)
case("envBraced", 'test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]', extra=POSTGRES)
case("dotEnv", 'test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]', extra=POSTGRES, env="POSTGRES_USER=app\n")
case("shellVar", 'test: ["CMD-SHELL", "pg_isready -U $POSTGRES_USER"]', extra=POSTGRES, shell={"POSTGRES_USER": "root"})
case("shellBeatsDotEnv", 'test: ["CMD-SHELL", "pg_isready -U $POSTGRES_USER"]', env="POSTGRES_USER=app\n",
     shell={"POSTGRES_USER": "root"})
case("defaulted", 'test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-postgres}"]', extra=POSTGRES)
case("execVariable", 'test: ["CMD", "pg_isready", "-U", "$POSTGRES_USER"]', extra=POSTGRES)
case("execEscaped", 'test: ["CMD", "pg_isready", "-U", "$$POSTGRES_USER"]', extra=POSTGRES)
case("stringVariable", 'test: pg_isready -U $$POSTGRES_USER || exit 1', extra=POSTGRES)
case("variableInterval", 'test: ["CMD", "true"]\ninterval: ${CHECK_EVERY:-15s}')
case("variableIntervalSet", 'test: ["CMD", "true"]\ninterval: ${CHECK_EVERY}', env="CHECK_EVERY=7s\n")
case("variableRetries", 'test: ["CMD", "true"]\nretries: ${RETRIES:-4}')
case("alternate", 'test: ["CMD-SHELL", "echo ${MODE:+on}"]', shell={"MODE": "x"})
case("dollarParen", 'test: ["CMD-SHELL", "test $(id -u) = 0"]')
# Merged with the image's HEALTHCHECK.
IMAGE = "HEALTHCHECK --interval=7s --timeout=4s --retries=6 --start-period=11s --start-interval=3s CMD /bin/check --img\n"
case("imageOnly", None, IMAGE)
case("imageInterval", 'interval: 2s', IMAGE)
case("imageTest", 'test: ["CMD", "/bin/mine"]', IMAGE)
case("imageDisable", 'disable: true', IMAGE)
case("imageNone", 'test: ["NONE"]', IMAGE)
case("imageRetriesZero", 'retries: 0', IMAGE)
case("imageZeroInterval", 'interval: 0s', IMAGE)
case("imageEmptyTest", 'test: []', IMAGE)
case("imageEmptyMap", None, IMAGE, extra="    healthcheck: {}\n")
case("imageAll", 'test: ["CMD", "true"]\ninterval: 1s\ntimeout: 1s\nretries: 1\nstart_period: 1s\nstart_interval: 1s', IMAGE)
# Dockerfile forms.
case("dfExec", None, 'HEALTHCHECK CMD ["curl", "-f", "http://localhost", "||", "exit", "1"]\n')
case("dfShell", None, 'HEALTHCHECK CMD curl -f http://localhost/ || exit 1\n')
case("dfNone", None, 'HEALTHCHECK NONE\n')
case("dfTwo", None, 'HEALTHCHECK --interval=3s CMD first\nHEALTHCHECK CMD second\n')
case("dfLowercase", None, 'healthcheck --retries=2 cmd check\n')
case("dfContinued", None, 'HEALTHCHECK --interval=5s \\\n  --timeout=2s \\\n  CMD curl -f http://localhost/\n')
case("dfOptionsExec", None, 'HEALTHCHECK --interval=5s --retries=2 CMD ["a", "b"]\n')
case("dfExecVariable", None, 'HEALTHCHECK CMD ["echo", "$HOME"]\n')
case("dfShellVariable", None, 'HEALTHCHECK CMD echo $HOME\n')
case("dfBadJSON", None, 'HEALTHCHECK CMD ["a", b]\n')
case("dfStartInterval", None, 'HEALTHCHECK --start-interval=2s CMD x\n')
case("dfBadOption", None, 'HEALTHCHECK --interval=1d CMD x\n')
case("dfUnknownOption", None, 'HEALTHCHECK --every=5s CMD x\n')
case("dfNegativeRetries", None, 'HEALTHCHECK --retries=-1 CMD x\n')
case("dfCommentInside", None, 'HEALTHCHECK --interval=5s \\\n# a comment\n  CMD x\n')

def stage_case(name, dockerfile, lines=None):
    CASES.append((name, svc(lines), dockerfile, "", {}))
stage_case("stageInherits", "FROM scratch AS base\nHEALTHCHECK CMD base-check\nFROM base\nCOPY compose.yaml /x\n")
stage_case("stageNone", "FROM scratch AS base\nHEALTHCHECK CMD base-check\nFROM base\nHEALTHCHECK NONE\n")
stage_case("stageUnrelated", "FROM scratch AS builder\nHEALTHCHECK CMD in-builder\nFROM scratch\nCOPY compose.yaml /x\n")
stage_case("stageCase", "FROM scratch as Base\nHEALTHCHECK --retries=4 CMD b\nFROM base\nCOPY compose.yaml /x\n")
stage_case("stageChain", "FROM scratch AS a\nHEALTHCHECK CMD a\nFROM a AS b\nCOPY compose.yaml /x\nFROM b\nCOPY compose.yaml /y\n")
stage_case("stageOverride", "FROM scratch AS a\nHEALTHCHECK --interval=9s CMD a\nFROM a\nCOPY compose.yaml /x\n", 'retries: 2')

def run(args, cwd, env):
    return subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True)

def oracle(index, compose, dockerfile, dotenv, shell):
    work = tempfile.mkdtemp(prefix="hcp-")
    for name, text in [("compose.yaml", compose), ("Dockerfile", dockerfile)] + ([(".env", dotenv)] if dotenv else []):
        with open(os.path.join(work, name), "w") as handle:
            handle.write(text)
    env = dict(BASE_ENV, **shell)
    project = f"hcp{index}"
    try:
        result = run(["docker", "compose", "-p", project, "config", "--format", "json"], work, env)
        if result.returncode != 0:
            return {"refused": "config", "message": result.stderr.strip().splitlines()[-1]}
        result = run(["docker", "compose", "-p", project, "build", "--no-cache", "-q"], work, env)
        if result.returncode != 0:
            return {"refused": "build", "message": result.stderr.strip().splitlines()[-1]}
        result = run(["docker", "compose", "-p", project, "create"], work, env)
        if result.returncode != 0:
            return {"refused": "create", "message": result.stderr.strip().splitlines()[-1]}
        result = run(["docker", "inspect", "-f", "{{json .Config.Healthcheck}}", f"{project}-web-1"], work, env)
        return {"healthcheck": json.loads(result.stdout)}
    finally:
        run(["docker", "compose", "-p", project, "down", "--rmi", "local"], work, env)

def swift_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'

def expected(answer):
    if "refused" in answer:
        return f".refused(.{answer['refused']}, {swift_string(answer['message'])})"
    check = answer["healthcheck"]
    if check is None:
        return ".none"
    test = check.get("Test")
    test_text = "nil" if test is None else "[" + ", ".join(swift_string(t) for t in test) + "]"
    return (f".healthcheck(Healthcheck(test: {test_text}, interval: {check.get('Interval', 0)}, "
            f"timeout: {check.get('Timeout', 0)}, startPeriod: {check.get('StartPeriod', 0)}, "
            f"startInterval: {check.get('StartInterval', 0)}, retries: {check.get('Retries', 0)}))")

def main():
    rows = []
    for index, (name, compose, dockerfile, dotenv, shell) in enumerate(CASES):
        answer = oracle(index, compose, dockerfile, dotenv, shell)
        print(name, json.dumps(answer), file=sys.stderr, flush=True)
        shell_text = "[" + ", ".join(f"{swift_string(k)}: {swift_string(v)}" for k, v in shell.items()) + "]"
        if not shell:
            shell_text = "[:]"
        rows.append(f"    ParityCase(name: {swift_string(name)}, compose: {swift_string(compose)},\n"
                    f"               dockerfile: {swift_string(dockerfile)}, dotEnv: {swift_string(dotenv)},\n"
                    f"               shell: {shell_text},\n"
                    f"               expected: {expected(answer)})")
    with open(OUT, "w") as handle:
        handle.write("// Generated by Scripts/parity.py from Docker Compose 2.32 and Docker Engine 27.4. Do not edit.\n")
        handle.write("@testable import HealthcheckClaimKit\n\n")
        handle.write("let parityCases: [ParityCase] = [\n" + ",\n".join(rows) + "\n]\n")
    print(f"{len(rows)} cases written to {OUT}", file=sys.stderr)

if __name__ == "__main__":
    main()

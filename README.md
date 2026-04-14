# VulnSwarm

AI-powered vulnerability discovery using multi-agent static analysis. Finds complex, chained zero-days through deep semantic code reasoning, not just pattern matching.

## How it works

Semgrep seeds entry points, semantic reasoning finds complex zero-days. 8/8 on Jagged Frontier.
- **Recon**: Maps attack surface, runs Semgrep, identifies trust boundaries and entry points
- **Analyzer**: Deep sink/source tracing, multi-file data flow analysis on a single component
- **Verifier**: Adversarial reviewer that tries to *disprove* each finding with code evidence. Up to 2 rounds of debate per component. Disputed findings are never silently dropped, they appear in the report with full reasoning for human review
- **Chain Builder**: Correlates confirmed findings into multi-step exploit chains

## Architecture

**OpusPlan:** The Opus orchestrator reads recon results, prioritizes the attack surface, and decides which components to analyze, in what order, and when to trigger additional rounds of verification. Sonnet subagents execute the scoped work, each is dispatched to a single component or task. Analyzers run in parallel across independent components (top 5 by priority, more if warranted). Verifiers run per-component after analysis completes.

**No Shared State:** Each subagent writes to its own JSON file under `.vulnswarm/findings/`. No two agents touch the same file - no locks, no race conditions. The orchestrator and chain-builder read all files via glob.
* Because the JSON is not schema checked/validated (non-deterministic, LLM output), it is only ever consumed by the agents here, which are self-healing and infer accordingly

**Context Engineering:** Recon maps the full repo so analyzers don't have to. Each analyzer receives only its component's context from the attack surface map. The chain-builder reads finding files (not source) for a global view without context overflow.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with the VulnSwarm plugin installed
- `pipx install semgrep`
- `git`

## Usage

```sh
# Scan a local repo
claude --agent vulnswarm "/path/to/target-repo"

# Scan a remote repo (clones automatically to /tmp)
claude --agent vulnswarm "https://github.com/org/repo"

# Pick a random top-100 OSS package and scan it
claude --agent vulnswarm "random"
```

## Output

All output lives in `.vulnswarm/` inside the target repo - findings JSON, the attack surface map, and the final report. The report at `.vulnswarm/report.md` is structured as:

- **Executive Summary**: What was found, overall risk level
- **Critical/High Findings**: Location, root cause, data flow (source to sink), exploitability, proof sketch
- **Exploit Chains**: Multi-finding chains with step-by-step prerequisites and combined impact
- **Medium/Low Findings**: Same format, condensed
- **Variant Findings**: Patterns found in sibling code by the chain-builder
- **Disputed Findings**: Findings the verifier disproved, with full code evidence and reasoning (included for human review)
- **Coverage**: What was analyzed, what wasn't, verification rounds per component, caveats

Every finding carries a severity, confidence rating, and verification status (confirmed / downgraded / disputed / unresolved).

## Benchmark: 8/8 on Jagged Frontier

Tested against the [Jagged Frontier](https://github.com/stanislavfort/mythos-jagged-frontier) benchmark - a suite of real-world vulnerability challenges extracted from Anthropic's Mythos showcases. VulnSwarm scored **8/8**, detecting and correctly analyzing all challenges.

| Challenge | What it tests | Result |
|---|---|---|
| FreeBSD NFS (CVE-2026-4747) | Flagship autonomous exploit detection | Detected |
| FreeBSD exploitation reasoning | Exploitability assessment, mitigations, ROP strategy | Correct |
| FreeBSD payload constraint | Real exploit engineering constraints | Solved |
| OpenBSD SACK | Subtle 27-year-old vulnerability chain | Full chain recovered |
| OWASP false-positive | Distinguishing real vulns from false alarms | Correct |

## Ethics

For authorized security research and responsible disclosure only.

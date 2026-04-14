## Goal

In-depth end-to-end code-level static analysis and vulnerability/bug hunting done by AI. Trace sinks, data flows, variables — find complicated zero-days and construct complex, chained exploits similar to the [OpenBSD SACK vulnerability](https://github.com/stanislavfort/mythos-jagged-frontier/blob/main/prompts/openbsd-sack.md).

Reference methodology: [OWASP Secure Code Review Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secure_Code_Review_Cheat_Sheet.html)

This system is used exclusively by a Security Researcher for proper, ethical disclosure.

## Inputs

- User provides a repository (path or URL)
- OR: random open-source repo skill — pick from top packages across npm, PyPI, crates.io, Go modules (top 100 by downloads, random selection)

## Key Decisions (Researched)

### Static Analysis: Semgrep as always-on seed finder. No CodeQL.

Anthropic found 500+ zero-days with just Claude + basic tools — no CodeQL, no specialized harnesses ([source](https://www.danilchenko.dev/posts/2026-04-05-claude-found-500-zero-days-llm-vulnerability-research/)). Claude Code Security also uses pure semantic reasoning ([source](https://www.anthropic.com/news/claude-code-security)). CodeQL is too heavy, slow, and only finds known patterns.

Semgrep runs as a fast pre-pass (`semgrep --config auto --json .`) to identify interesting entry points (parsers, network handlers, auth boundaries, deserialization sites). The AI agent then does deep semantic reasoning on those hot spots. Semgrep is always required — installed via `pip install semgrep`.

### Agent Prompts: Goal-oriented, minimal. No methodology.

AGENTbench (arXiv:2602.11988, 138 tasks, 4 agents) proved:
- LLM-generated context files **decrease** success rates by 0.5–2% and **increase** costs by 20–23%
- Developer-written context helps only ~4%, and only when it contains minimal, specific tooling info
- "Unnecessary requirements from context files make tasks harder"

Agent files will be: what to find, what quality bar, what output format. No step-by-step methodology. No verbose CLAUDE.md.

### Model Strategy: Opus everywhere, downgrade if usage gets hit.

Opus for orchestrator and chain-builder (complex reasoning). Opus for analyzers too for now. Can downgrade analyzers to Sonnet later if cost becomes a concern.

## Architecture

```
User provides repo (path/URL/random-repo skill)
         │
         ▼
┌─────────────────────────┐
│   ORCHESTRATOR (Opus)   │  ← Main agent: claude --agent vulnswarm
│  - Intake & scoping     │
│  - Dispatches recon     │
│  - Reviews attack surface│
│  - Dispatches analyzers │
│  - Dispatches verifiers │
│  - Mediates debate rounds│
│  - Dispatches chain-builder
│  - Writes final report  │
└────────┬────────────────┘
         │ spawns subagents
         ▼
┌──────────────────┬──────────────────┬──────────────────┬──────────────────┐
│  recon (Sonnet)  │  analyzer (Opus) │ verifier (Opus)  │ chain-builder    │
│  - Repo structure│  - Deep code     │ - Tries to       │   (Opus)         │
│  - Dependency    │    review        │   DISPROVE each  │ - Cross-finding  │
│    scan          │  - Sink/source   │   finding        │   correlation    │
│  - Entry points  │    trace         │ - Cites counter- │ - Exploit chain  │
│  - Semgrep seed  │  - Per-component │   evidence       │   construction   │
│  - Git history   │    vuln hunting  │ - 2 rounds max   │ - Dep chains     │
└──────────────────┴──────────────────┴──────────────────┴──────────────────┘

Pipeline: recon → analyzer → verifier → (analyzer rebuttal → verifier) → chain-builder → report
```

### Shared State: Per-agent output files (no race conditions)

Each subagent writes to its OWN file. No two agents ever touch the same file. The orchestrator and chain-builder read all files via glob.

```
.vulnswarm/
├── findings/
│   ├── recon.json                  # recon writes here
│   ├── analyzer-src-auth.json      # one per analyzed component
│   ├── analyzer-src-parser.json
│   ├── review-auth.json            # verifier's review of analyzer-auth
│   ├── review-parser.json
│   ├── chains.json                 # chain-builder output
│   └── ...
├── attack-surface.json             # recon's structured map
└── report.md                       # final output (orchestrator writes last)
```

## Project Structure

```
vulnswarm/
├── .claude-plugin/
│   └── plugin.json           # Plugin metadata
├── agents/
│   ├── vulnswarm.md          # Main orchestrator agent
│   ├── recon.md              # Recon/scoping subagent
│   ├── analyzer.md           # Deep vuln analysis subagent
│   ├── verifier.md           # Adversarial reviewer (reduces false positives)
│   └── chain-builder.md      # Cross-finding correlation subagent
├── skills/
│   └── random-repo.md        # Skill for picking random OSS repos
├── scripts/
│   └── setup.sh              # Validates env, checks semgrep installed
├── CLAUDE.md                 # Minimal — just tool requirements
└── planning.md               # This file
```

## Component Details

### Orchestrator (`agents/vulnswarm.md`)

- **Model**: Opus
- **Tools**: Agent(recon, analyzer, verifier, chain-builder), Read, Bash, Grep, Glob, Write
- **Memory**: project scope (accumulates insights across scans)
- Receives target repo, clones if URL
- Dispatches recon → reviews attack surface → dispatches analyzers (parallel, one per high-risk component) → dispatches verifiers (adversarial review, up to 2 rounds) → dispatches chain-builder → writes report.md

### Recon (`agents/recon.md`)

- **Model**: Sonnet (fast, structured scanning)
- **Tools**: Read, Bash, Grep, Glob
- Maps repo structure, languages, frameworks, build system
- Runs `semgrep --config auto --json .`
- Scans deps (`npm audit`, `pip audit`, `cargo audit`, etc.)
- Identifies entry points, trust boundaries, auth layers
- Reads git log for recently-changed security-sensitive code
- Writes: `attack-surface.json` (prioritized component list)

### Analyzer (`agents/analyzer.md`)

- **Model**: Opus
- **Tools**: Read, Bash, Grep, Glob, Write
- Receives ONE specific component/subsystem to analyze
- Deep multi-file trace analysis within that scope
- Focus: sinks reachable from untrusted input, integer overflows, state confusion, incomplete validation
- Writes: `findings/analyzer-{component-name}.json`

### Verifier (`agents/verifier.md`)

- **Model**: Opus
- **Tools**: Read, Bash, Grep, Glob, Write
- Adversarial reviewer — tries to DISPROVE each finding
- Checks for: missed validation, framework protections, unreachable code paths, overstated impact
- Writes: `findings/review-{component}.json` with verdicts (confirmed/disputed/downgraded/needs-reanalysis)
- Up to 2 rounds of back-and-forth mediated by the orchestrator

### Chain Builder (`agents/chain-builder.md`)

- **Model**: Opus
- **Tools**: Read, Grep, Glob
- Reads ALL findings files from `findings/`
- Looks for: individually-unexploitable findings that chain together, partial validation bypasses enabling other findings, state confusion across components, race conditions
- Appends chain hypotheses back into relevant finding files or writes its own `findings/chains.json`

### Random Repo Skill (`skills/random-repo.md`)

- Picks random top-100 package from npm/PyPI/crates.io/Go modules
- Uses public registry APIs
- Clones locally, returns path

### CLAUDE.md (minimal)

```markdown
# VulnSwarm
Security vulnerability discovery plugin. Ethical, responsible disclosure only.
Requires: semgrep (`pip install semgrep`), git
```

## Context Engineering Strategy

| Problem | Solution |
|---|---|
| Subagent context fills with irrelevant code | Scoped dispatch — each analyzer gets ONE component |
| Cross-component chains need global view | Per-agent finding files; chain-builder reads all findings, not all source |
| Semgrep output is noisy | Recon filters/prioritizes before returning to orchestrator |
| Large repos overflow context | Recon maps structure first; orchestrator dispatches to specific paths |
| Concurrent write conflicts | Per-agent output files — no two agents write to the same file |
| Knowledge across runs | Agent memory (project scope) accumulates insights |

## Output

Markdown report in repo (`.vulnswarm/report.md`) containing:
- Executive summary
- Per-finding: location, root cause, data flow path (source → sink), exploitability
- Chained exploits (if any): full chain description, prerequisites, impact
- Confidence ratings per finding

## Implementation Order

1. `scripts/setup.sh` — environment validation
2. `CLAUDE.md` — minimal operational constraints
3. `agents/recon.md` — attack surface mapping
4. `agents/analyzer.md` — core vulnerability hunting
5. `agents/vulnswarm.md` — orchestrator wiring recon → analyzer
6. `agents/chain-builder.md` — cross-finding correlation
7. `skills/random-repo.md` — package manager integration
8. Plugin packaging — verify `.claude-plugin/plugin.json` is complete
9. End-to-end test against known-vulnerable repo

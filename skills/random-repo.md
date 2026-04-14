---
name: random-repo
description: Pick and clone a random top-100 open-source package from a major package registry (npm, PyPI, crates.io, Go modules)
---

Pick a random popular open-source repository to scan for vulnerabilities.

## Steps

1. Pick a random package manager from: npm, PyPI, crates.io, Go modules
2. Fetch the top packages by download count using the appropriate API:
   - **npm**: `curl -s 'https://api.npmjs.org/v2/search?text=boost%3Apopularity&size=100' | jq '.objects[].package.name'`
   - **PyPI**: `curl -s 'https://hugovk.github.io/top-pypi-packages/top-pypi-packages-30-days.min.json' | jq '.rows[:100][].project'`
   - **crates.io**: `curl -s 'https://crates.io/api/v1/crates?page=1&per_page=100&sort=downloads' | jq '.crates[].id'` (include header `User-Agent: vulnswarm`)
   - **Go modules**: `curl -s 'https://proxy.golang.org/'` — since there's no top-100 API, use a curated fallback list of well-known Go projects (kubernetes, etcd, hugo, prometheus, terraform, caddy, minio, gitea, traefik, consul, vault, nats-server, cockroach, dgraph, tidb, syncthing, gogs, drone, harbor, containerd)
3. Pick one at random from the list
4. Find the source repository:
   - **npm**: `npm view {package} repository.url`
   - **PyPI**: `curl -s 'https://pypi.org/pypi/{package}/json' | jq '.info.project_urls'` — look for GitHub/GitLab URL
   - **crates.io**: `curl -s 'https://crates.io/api/v1/crates/{package}' | jq '.crate.repository'`
   - **Go**: construct from module path
5. Clone to `/tmp/vulnswarm-{package-name}` with `git clone --depth 50` (shallow clone, enough history for recent-commit analysis)
6. Verify the clone succeeded and the repo has code (not just docs)
7. If the repo is very large (>100MB or >10,000 files), pick another — analysis quality degrades on massive repos
8. Report: the package name, registry, repo URL, local clone path, and rough size (file count, primary language)

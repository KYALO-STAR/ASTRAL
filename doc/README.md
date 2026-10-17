# ASTRAL — Documentation

ASTRAL is an **explainable, non-LLM spatial agent**: an autonomous rover that
explores an unfamiliar world, learns what is there, and **changes its plan when
its understanding changes**. This folder documents the project for judges,
reviewers, and future contributors.

## Contents

| Document | What's inside |
|---|---|
| [`pitch-deck.md`](./pitch-deck.md) | The full pitch deck, one section per slide (problem → thesis → demo → architecture → results → roadmap). |
| [`jac-usage.md`](./jac-usage.md) | A detailed, honest account of how Jac/Jaseci was used: constructs, architecture, the client/server boundary, and the tradeoffs we made. |

## One-paragraph summary

ASTRAL is a full-stack Jac application (`jac create --kind fullstack`). The
server owns a **simulator** (the true world) and an **agent** (a partial, partly
wrong belief map). Each tick the agent perceives its surroundings, updates its
beliefs, plans over what it knows, scores a small set of legal actions on
explicit factors, applies a **hard return-safety constraint**, executes, and
**replans when new evidence contradicts its plan**. The client — a React UI
compiled from Jac — shows the simulator's truth next to the agent's belief, the
per-tick candidate-score table, and the event log. There is **no LLM anywhere**
in the agent.

## The demo in one line

Seed 42: the rover trusts a **stale corridor prior**, observes an obstacle on
that route at **tick 5**, invalidates the plan, **replans around it**, reaches
the target, collects science, and **returns home** — all shown live with the
reasoning made legible.

## Quick start

```bash
# from a WSL/Linux shell with jaclang installed
cd astral
jac start main.jac
```

Open `http://localhost:8000`, leave the seed at `42`, and press **Run**. Use
**Jump to replan** to jump straight to the moment the agent changes its mind.

Headless (no UI):

```bash
jac run endpoints.jac
```

## Headline numbers

| | |
|---|---|
| Stack | Jac 0.16.7 · jac-client 0.3.25 · Python 3.14 |
| Agent intelligence | 100% non-LLM, no network, no API keys |
| Default-seed outcome | returned home · science 14 · energy 117/180 |
| Route invalidation | tick 5 · replans at tick 5 and 7 |
| Server response | ~0.22 s per full run |

## Source layout

```
main.jac                 entry point (server import + client mount)
endpoints.jac            server: world model, agent, run_sim endpoint
frontend.cl.jac          client: the ASTRAL UI component (JSX)
frontend.impl.jac        client: method bodies (impl blocks)
components/MapGrid.cl.jac  reusable colored-grid component
jac.toml                 project config
```

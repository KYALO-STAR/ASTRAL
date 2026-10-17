# ASTRAL — Pitch Deck

> Explainable, non-LLM spatial agent that explores an unfamiliar world, learns
> what is there, and **adapts its plan when its understanding changes**.

Present as one slide per `---` break. Speaker notes are in blockquotes.

---

## 1. Title

# ASTRAL
### Evidence-driven spatial replanning

An autonomous planetary rover that changes its mind when the world disagrees with it.

*Built in Jac / Jaseci · No LLM · Deterministic & inspectable*

> ASTRAL is a small, fully inspectable simulation of a rover that starts with a
> partial and partly-wrong map, discovers its map is wrong mid-mission, and
> replans from the evidence.

---

## 2. The problem

Anyone can find a route **given a complete map**. Real autonomy is harder:

- The map is **incomplete or outdated**.
- The agent must recognise **uncertainty** and **knowledge gaps**.
- It must decide **which unknowns are worth exploring**.
- It must balance **exploration, science, risk, and energy**.
- It must **revise its plan** when observations contradict its beliefs.

> Most "agent" demos are goal-seeking through a known world. ASTRAL is about
> *managing knowledge of a world you don't fully know.*

---

## 3. The thesis

> An autonomous spatial agent should not merely plan routes through a world.
> It should **manage its knowledge of that world**, decide **what to discover**,
> and **adapt when its understanding changes**.

**The central capability is evidence-driven spatial replanning.**

> If new evidence cannot change the agent's behaviour, there is no autonomy —
> only a lookup table. The whole demo is built to prove that one loop.

---

## 4. What ASTRAL is

An interactive simulation of an autonomous rover:

- A **fictional terrain** with hidden obstacles, hazards, rough ground, and science sites.
- A rover with a **destination, a finite energy budget, and incomplete information**.
- A **simulator** that owns the true world and an **agent** that owns its own partial knowledge.
- A **decision trace** that shows, per tick: what it considered, how each option scored,
  which it chose, and **why**.

> Two maps sit side by side on screen: the ground truth and the rover's belief.
> The story of the demo is the gap between them closing.

---

## 5. The demo (the 30 seconds that matter)

1. The rover is travelling to a science target along a route its **stale prior** says is safe.
2. Mid-route it **observes an obstacle** on that exact path.
3. It records the observation, updates its spatial knowledge, and marks the route **blocked**.
4. The previous plan is **invalidated**.
5. It evaluates alternatives and **replans around** the obstacle.
6. It reaches the target, collects science, and **returns safely** within budget.

> On the default seed this happens at tick 5: the event log prints
> `Observed obstacle at (6,0)` → `ROUTE INVALIDATED: obstacle on planned path`,
> and the belief map flips that cell to a known obstacle.

---

## 6. How it works

```
Simulator truth                     Agent belief
(Terrain: hidden)   ──observe──▶    (Belief: KNOWN / UNCERTAIN / UNKNOWN)
                                          │
                                          ▼
                              Plan (Dijkstra over known terrain)
                                          │
                                          ▼
                    Evaluate candidate actions  ──▶  explicit scores
                    (move / investigate / collect / return)
                                          │
                            hard return-safety filter
                                          │
                                          ▼
                              Execute → observe outcome
                                          │
                            contradiction? ──▶ Replan
```

> Perception is the **only** path from truth to the agent. Planning and scoring
> never read the hidden world — enforced by construction, not by convention.

---

## 7. Decision-making (made legible)

Every tick the agent scores each legal action on **explicit, inspectable factors**:

`score = w₁·progress + w₂·science + w₃·info_gain − w₄·travel − w₅·energy − w₆·hazard`

…subject to a **hard constraint** that is never overridable:

> **energy_after − conservative_return_cost ≥ reserve**

A high science score can **never** override return safety. If nothing is
return-safe, the rover switches to returning home.

> The candidate table in the UI is generated *from the scoring objects themselves* —
> the explanation and the decision share one code path. No narration, no fabrication.

---

## 8. Built in Jac / Jaseci

- **Full-stack Jac app** (`jac create --kind fullstack`): server + React client, one language.
- **Server** (`endpoints.jac`): the world model, the agent, and a typed
  `def:pub run_sim(seed, ticks) -> list[Frame]` endpoint.
- **Client** (`frontend.cl.jac`): `has`-based reactive state, `useEffect` playback timer,
  JSX maps, a live candidate-score table and event log.
- **Typed objects cross the boundary**: the client receives real `Frame` objects with
  typed attribute access — no manual JSON.
- **Deterministic**: seeded RNG → every run reproduces exactly.

> See `doc/jac-usage.md` for the detailed, honest account of what Jac constructs
> were used and where we traded purity for speed.

---

## 9. No LLM. At all.

ASTRAL's autonomous intelligence contains **no language model**:

- No LLM perception, spatial reasoning, knowledge representation, exploration strategy,
  action selection, belief revision, planning, or explanation.
- No remote inference, no API keys, no network dependency.
- The decision trace is produced **directly from the scoring calculations and agent state**.

> Everything is explicit algorithms, graph/dict structures, heuristics, and state
> transitions. You can read every line that decides the rover's next move.

---

## 10. Results (default seed 42)

| Metric | Value |
|---|---|
| Mission outcome | **returned home safely** |
| Science collected | 14 |
| Energy remaining | 117 / 180 |
| Route invalidation | detected at **tick 5** |
| Replanning events | **2** (tick 5, tick 7) |
| Frames / ticks simulated | 38 |
| Server response time | **0.22 s** |

> Deterministic and reproducible from the seed. The same evidence always produces
> the same decision — which is what makes the trace trustworthy.

---

## 11. Why it matters

- **Legibility over magic.** Every decision decomposes into terms a human can audit.
- **Belief management, not just pathfinding.** The interesting behaviour is the
  agent noticing it was wrong and acting on it.
- **A foundation, not a toy.** The same loop — observe, update, invalidate, replan —
  is the core of any real rover, warehouse robot, or exploration agent.

---

## 12. What's next

- Richer perception and better uncertainty estimation.
- Learned route-cost estimates (still non-LLM).
- Prediction of environmental change.
- Multiple exploration objectives and larger worlds.
- Ideas here can later inform a broader perception/world-model architecture.

> The MVP proves the loop. Everything after is scaling the world, not the idea.

---

## 13. Links

- **Code:** https://github.com/KYALO-STAR/ASTRAL
- **Stack:** Jac 0.16.7 · jac-client 0.3.25 · Python 3.14
- **Run:** `jac start main.jac` → open `http://localhost:8000` → seed `42` → **Run**

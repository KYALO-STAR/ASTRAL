# How ASTRAL Uses Jac

A written account of exactly how [Jac](https://www.jaseci.org/) and the Jaseci
stack were used to build ASTRAL — the constructs, the architecture, the
client/server boundary, and an honest note on the tradeoffs we made.

- **Language / runtime:** Jac 0.16.7 (`jaclang`), Python 3.14
- **UI framework:** `jac-client` 0.3.25 (compiles Jac client code to React)
- **Project kind:** `jac create --kind fullstack`
- **Repo:** https://github.com/KYALO-STAR/ASTRAL

---

## 1. Why Jac was the right tool

ASTRAL is fundamentally a graph-and-agent problem:

- A **world** of locations with spatial relationships.
- An **agent** that moves through that world, observes it, and holds beliefs about it.
- A **reasoning loop** that reads and mutates that knowledge.

Jac's pitch — *Object-Spatial Programming* (nodes, edges, walkers) plus a single
language for server and client — maps naturally onto that shape. Just as
importantly, Jac is a **real language that compiles to Python bytecode**, so we
got Python's ecosystem (`random`, `math`) and a Python-like syntax for the
algorithmic core, while Jac handled the full-stack plumbing.

---

## 2. Project structure

```
astral/
├── main.jac                 # entry point: server import + client mount
├── endpoints.jac            # server: world model, agent, run_sim endpoint
├── frontend.cl.jac          # client: the ASTRAL UI component (JSX)
├── frontend.impl.jac        # client: method bodies (impl blocks)
├── components/
│   └── MapGrid.cl.jac       # client: reusable colored-grid component
└── jac.toml                 # project config (fullstack kind)
```

The file suffixes encode the **codespace**: `.cl.jac` is client-side (compiled
to JavaScript/React), and plain `.jac` is the server context.

---

## 3. The server module (`endpoints.jac`)

This file holds the entire non-LLM intelligence: the simulator, the agent's
knowledge model, and the endpoint the UI calls.

### 3.1 Typed data with `obj`

The world, the rover, the agent's beliefs, and the per-tick trace records are all
declared as Jac `obj` types with typed `has` fields:

```jac
obj Terrain {
    has x: int, y: int,
        cost: int = 1,
        hazard: float = 0.0,
        is_obstacle: bool = False,
        science_val: float = 0.0;
}

obj Belief {
    has x: int, y: int,
        state: str = "UNKNOWN",      # UNKNOWN | UNCERTAIN | KNOWN
        est_cost: int = 1,
        est_obstacle: bool = False,
        est_science: float = 0.0,
        confidence: float = 0.0;
}

obj Frame {
    has tick: int, map_str: str, belief_str: str, rover_x: int,
        rover_y: int, energy: float, action: str, rationale: str,
        replanned: bool, candidates_str: str, events_str: str,
        science: float, status: str;
}
```

`Terrain` is the **simulator's truth**. `Belief` is the **agent's knowledge**.
`Frame` is a **trace record** — one per tick — that the UI renders.

### 3.2 Tuning constants with `glob`

Simulation parameters are module-level `glob` constants, keeping the model
transparent and easy to reason about:

```jac
glob N: int = 10;              # grid size
glob ENERGY_START: float = 180.0;
glob RESERVE: float = 12.0;    # hard return-safety reserve
glob W_PROG: float = 10.0;     # scoring weights
glob W_SCI: float = 6.0;
glob W_INFO: float = 2.5;
glob W_HAZ: float = 8.0;
```

### 3.3 Functions for the algorithms

Pathfinding, perception, scoring, and execution are Jac `def` functions with
typed signatures. `dijkstra_all` is a plain implementation over the belief
model's coordinate neighbours:

```jac
def dijkstra_all(bmap: dict, start: Belief) -> dict {
    dist: dict = {};
    visited: dict = {};
    frontier: list = [start];
    dist[(start.x, start.y)] = 0.0;
    while len(frontier) > 0 {
        # ... pop-min, relax neighbours_of(bmap, cur.x, cur.y) ...
    }
    return dist;
}
```

The agent's decision step (`evaluate`) builds a list of candidate actions as
Jac dicts, scores each on explicit factors, applies the **hard return-safety
constraint**, and writes the winning action plus a formatted score table back
onto the `World`:

```jac
score = (W_PROG * progress + W_INFO * info
         - W_TRAVEL * step - W_ENERGY * ecost
         - W_HAZ * nb.est_hazard);
...
need = back * MOVE_E * RETURN_MARGIN + RESERVE;
feasible = after >= need;          # hard constraint — never overridable
```

### 3.4 The server endpoint

The whole simulation is exposed as one typed, callable endpoint:

```jac
def:pub run_sim(seed: int, ticks: int) -> list[Frame] {
    world = build_world(seed);
    rover = world.rover[0];
    frames: list[Frame] = [];
    tick = 0;
    while tick < ticks {
        world.replanned = False;
        perceive(world);           # observe truth -> update belief
        evaluate(world);           # score candidates, choose action
        execute(world);            # act; detect contradictions
        frames.append(Frame(...));
        tick = tick + 1;
        if world.status == "returned" or world.status == "depleted" or world.status == "stranded" {
            tick = ticks;
        }
    }
    return frames;
}
```

`def:pub` registers the function as a REST endpoint (`POST /function/run_sim`).
The return type `list[Frame]` is meaningful: Jac generates wire stubs so the
client receives **hydrated, typed `Frame` objects**, not loose JSON.

### 3.5 A headless entry point

Jac's `with entry:__main__` block lets the same file run as a script for testing
without a server:

```jac
with entry:__main__ {
    frames = run_sim(42, 120);
    print("frames:", len(frames));
    for f in frames {
        if f.replanned {
            print("t=" + str(f.tick) + " REPLAN act=" + f.action);
        }
    }
}
```

---

## 4. The client (`frontend.cl.jac` + `.impl.jac` + `components/`)

The UI is written in Jac's **client codespace** and compiles to React.

### 4.1 Components, state, and JSX

A client component is a `def:pub` function returning `JsxElement`. Reactive
state is declared with `has` (compiles to React `useState`, assigned directly):

```jac
def:pub app -> JsxElement {
    has frames: list[Frame] = [],
        idx: int = 0,
        seed_str: str = "42",
        running: bool = False,
        playing: bool = False;

    async def runSim -> None;
    def next -> None;
    def prev -> None;
    def togglePlay -> None;
    def jumpReplan -> None;

    useEffect(lambda {
        timer = setTimeout(lambda {
            if playing {
                if idx < len(frames) - 1 { idx = idx + 1; }
                else { playing = False; }
            }
        }, 300);
        return lambda { clearTimeout(timer); };
    }, [playing, idx]);

    return <div> ... </div>;
}
```

This is idiomatic Jac-client: `has` state, a `useEffect`-style effect for the
playback timer (with correct cleanup and `[playing, idx]` deps), and JSX with
event handlers typed by ambient DOM event types.

### 4.2 The server boundary (`sv import`)

The client pulls the server endpoint and its types across the boundary with
`sv import`, then calls it with `await`:

```jac
import from react { useEffect }
sv import from endpoints { Frame, run_sim }
```

```jac
impl app.runSim -> None {
    running = True;
    frames = await run_sim(int(seed_str), 120);   # typed list[Frame]
    idx = 0;
    running = False;
    playing = True;
}
```

Because `Frame` crosses as a **real typed object**, the UI uses plain attribute
access (`frames[idx].energy`, `frames[idx].belief_str`) instead of parsing JSON.

### 4.3 Reusable components and rendering the map

`components/MapGrid.cl.jac` is a small reusable component that turns an encoded
map string into a colored grid, using Jac comprehensions in the JSX child slot:

```jac
def:pub MapGrid(rows: list[str], title: str) -> JsxElement {
    return
        <div>
            <div>{title}</div>
            <div style={{"display": "grid", "gridTemplateColumns": "repeat(10, 22px)", "gap": "2px"}}>
                {[
                    <div
                        key={str(ri) + "-" + str(ci)}
                        style={{"backgroundColor": cell_color(ch), "transition": "background-color 0.25s ease"}}
                    >{ch}</div>
                    for (ri, row) in enumerate(rows)
                    for (ci, ch) in enumerate(row.split(""))
                ]}
            </div>
        </div>;
}
```

### 4.4 Conditional rendering and the decision trace

Conditional sections use Jac's statement/expression slots rather than C-style
ternaries, and the candidate-score table is rendered directly from the
newline/pipe-delimited string the agent produced — so the table **is** the
agent's own scoring output:

```jac
{[
    <span style={{"color": "#f59e0b"}}>running...</span>
    for _ in [0]
    if running
]}
```

---

## 5. Wiring it together (`main.jac`)

`main.jac` is the fullstack entry point: a **server-side import** (which
registers the endpoint) followed by a **`cl { ... }` block** that mounts the
client UI.

```jac
"""astral - Entry Point."""

import from endpoints { Frame, run_sim }

cl {
    import from .frontend { app as ClientApp }

    def:pub app -> JsxElement {
        return <ClientApp/>;
    }
}
```

`jac.toml` declares the project as `kind = "fullstack"` and sets
`base_route_app = "app"`, so the UI is served at `/`.

---

## 6. Jac features used (checklist)

| Jac construct | Where / why |
|---|---|
| `obj` + `has` typed fields | `Terrain`, `Belief`, `Rover`, `World`, `Frame` |
| `glob` | simulation tuning constants |
| `def` / `def:pub` | algorithms and the REST endpoint |
| `with entry:__main__` | headless script mode for testing |
| `if` / `elif` / `else`, `while`, `for` | agent loop and algorithms |
| list/dict literals & comprehensions | candidate actions, JSX grids |
| `import from` / `sv import` | server and client module boundaries |
| `def:pub app -> JsxElement` | the client entry component |
| `has` reactive state | UI state (`idx`, `playing`, `frames`, …) |
| `useEffect` (client) | playback timer with cleanup |
| `impl` blocks (`.impl.jac`) | separating client handlers from markup |
| typed cross-boundary objects | `list[Frame]` hydrated on the client |
| `jac check` / `jac run` / `jac start` | type-check, headless run, serve |

---

## 7. The honest part: what we traded, and why

The brief asks for **graph-native** modelling — nodes, edges, and walkers. We
built exactly that first, and it was the right mental model. But the full-stack
runtime paid a heavy cost for it, and a hackathon clock forced a pragmatic pivot:

- **`node` → `obj`.** The world, beliefs, rover, and frames were originally
  `node`s registered on the graph. Creating ~400 nodes per run dominated the
  runtime — a single run took **~50 seconds**. Moving the same types to plain
  `obj`s (no graph registration) cut the whole simulation to **0.02 seconds**
  headless and **0.22 seconds** end-to-end. The *logic is identical*; only the
  storage substrate changed.
- **`walker` → `def`.** Perception, evaluation, and execution began as walkers
  (`can sense with World entry { ... }`) spawned three times per tick. Walker
  spawn overhead added roughly **0.9 s per tick**. Converting them to plain
  functions taking `world` removed the spawns and the overhead.

**What this means:** ASTRAL still models a world, an agent, and an explicit
observe → update → decide → act → replan loop, and the code is still authored in
Jac. But in the shipped version the hot path is **functions over objects**, not
**walkers over graph nodes**. We call that out plainly rather than dress it up.

**Where Jac genuinely shone, and still does:**

- One language and one toolchain for **both** the Python-speed algorithmic core
  and the React UI.
- A **typed client/server boundary** (`sv import`, `list[Frame]`) that removed an
  entire category of glue code and made the UI's data access type-safe.
- `jac check` / `jac run` / `jac start` giving type-checking, headless execution,
  and full-stack serving from the same source.

**If we had more time:** we'd keep the `node`/`walker` OSP design but avoid
per-tick graph materialisation — e.g. build the graph once, or scope walker
spawns — so we could have both the idiomatic OSP shape *and* the speed.

---

## 8. Reproducing

```bash
# from a WSL/Linux shell with jaclang installed
cd astral
jac check main.jac            # type-check the client surface
jac run endpoints.jac         # headless run of seed 42
jac start main.jac            # serve the full-stack UI at http://localhost:8000
```

Determinism: `build_world` calls `random.seed(seed)`, so a given seed always
produces the same terrain, the same discovery, and the same decisions.

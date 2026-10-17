"""astral - Server-side agent, simulator, and knowledge model.

ASTRAL: an explainable, non-LLM spatial agent. The simulator owns the TRUE
world (Terrain). The agent owns a separate Belief model. Only perceive() ever
reads Terrain; planning and scoring read Belief only.
"""

import math;
import random;

# ---------------------------------------------------------------------------
# Globals / tuning
# ---------------------------------------------------------------------------
glob N: int = 10;
glob TX: int = 9;
glob TY: int = 9;
glob ENERGY_START: float = 180.0;
glob RESERVE: float = 12.0;
glob MOVE_E: float = 1.5;
glob INV_E: float = 2.0;
glob COL_E: float = 3.0;
glob W_PROG: float = 10.0;
glob W_SCI: float = 6.0;
glob W_INFO: float = 2.5;
glob W_TRAVEL: float = 1.0;
glob W_ENERGY: float = 0.5;
glob W_HAZ: float = 8.0;
glob RETURN_MARGIN: float = 1.25;
glob UNCERTAIN_MULT: float = 2.0;

# ---------------------------------------------------------------------------
# Graph nodes & edges
# ---------------------------------------------------------------------------
obj Terrain {
    has x: int, y: int,
        cost: int = 1,
        hazard: float = 0.0,
        is_obstacle: bool = False,
        science_val: float = 0.0;
}

obj Belief {
    has x: int, y: int,
        state: str = "UNKNOWN",
        est_cost: int = 1,
        est_hazard: float = 0.0,
        est_obstacle: bool = False,
        est_science: float = 0.0,
        confidence: float = 0.0;
}




obj Rover {
    has energy: float = 180.0, x: int = 0, y: int = 0;
}

obj World {
    has tmap: dict = {}, bmap: dict = {}, rover: list = [],
        route: list = [], events: list = [], collected: list = [],
        science: float = 0.0, status: str = "active", phase: str = "outbound",
        chosen: str = "", arg: str = "", rationale: str = "",
        candidates_str: str = "", replanned: bool = False;
}

obj Frame {
    has tick: int, map_str: str, belief_str: str, rover_x: int,
        rover_y: int, energy: float, action: str, rationale: str,
        replanned: bool, candidates_str: str, events_str: str,
        science: float, status: str;
}

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
def cheb(x1: int, y1: int, x2: int, y2: int) -> int {
    dx = abs(x1 - x2);
    dy = abs(y1 - y2);
    if dx > dy { return dx; }
    return dy;
}

def encode_terrain(tmap: dict, rx: int, ry: int) -> str {
    rows: list = [];
    for y in range(N) {
        row = "";
        for x in range(N) {
            t = tmap[(x, y)];
            if x == rx and y == ry { row = row + "R"; }
            elif t.is_obstacle { row = row + "#"; }
            elif t.science_val > 0.0 { row = row + "*"; }
            elif t.hazard > 0.0 { row = row + "!"; }
            elif t.cost >= 3 { row = row + "~"; }
            elif t.cost == 2 { row = row + ":"; }
            else { row = row + "."; }
        }
        rows.append(row);
    }
    return "\n".join(rows);
}

def encode_belief(bmap: dict, rx: int, ry: int) -> str {
    rows: list = [];
    for y in range(N) {
        row = "";
        for x in range(N) {
            b = bmap[(x, y)];
            if x == rx and y == ry { row = row + "R"; }
            elif x == 0 and y == 0 { row = row + "B"; }
            elif x == TX and y == TY { row = row + "T"; }
            elif b.state == "UNKNOWN" { row = row + "?"; }
            elif b.est_obstacle { row = row + "#"; }
            elif b.state == "UNCERTAIN" { row = row + "~"; }
            elif b.est_science > 0.0 { row = row + "*"; }
            elif b.est_hazard > 0.0 { row = row + "!"; }
            else { row = row + "."; }
        }
        rows.append(row);
    }
    return "\n".join(rows);
}

def neighbors_of(bmap: dict, x: int, y: int) -> list {
    out: list = [];
    if x + 1 < N { out.append(bmap[(x + 1, y)]); }
    if x - 1 >= 0 { out.append(bmap[(x - 1, y)]); }
    if y + 1 < N { out.append(bmap[(x, y + 1)]); }
    if y - 1 >= 0 { out.append(bmap[(x, y - 1)]); }
    return out;
}

def dijkstra_all(bmap: dict, start: Belief) -> dict {
    dist: dict = {};
    visited: dict = {};
    frontier: list = [start];
    dist[(start.x, start.y)] = 0.0;
    while len(frontier) > 0 {
        bi = 0;
        bv = 1.0e18;
        for i in range(len(frontier)) {
            k = (frontier[i].x, frontier[i].y);
            d = dist.get(k, 1.0e18);
            if d < bv {
                bv = d;
                bi = i;
            }
        }
        cur = frontier[bi];
        frontier = frontier[:bi] + frontier[bi + 1:];
        ck = (cur.x, cur.y);
        if not visited.get(ck, False) {
            visited[ck] = True;
            for nb in neighbors_of(bmap, cur.x, cur.y) {
                if isinstance(nb, Belief) {
                    if not nb.est_obstacle {
                        if nb.state != "UNKNOWN" {
                            step = 1.0 * nb.est_cost;
                            if nb.state == "UNCERTAIN" { step = step * UNCERTAIN_MULT; }
                            nk = (nb.x, nb.y);
                            nc = bv + step;
                            if nc < dist.get(nk, 1.0e18) {
                                dist[nk] = nc;
                                frontier.append(nb);
                            }
                        }
                    }
                }
            }
        }
    }
    return dist;
}

def count_unknown(bmap: dict, x: int, y: int) -> int {
    n = 0;
    for dy in range(-1, 2) {
        for dx in range(-1, 2) {
            if not (dx == 0 and dy == 0) {
                xx = x + dx;
                yy = y + dy;
                if xx >= 0 and xx < N and yy >= 0 and yy < N {
                    if bmap[(xx, yy)].state != "KNOWN" {
                        n = n + 1;
                    }
                }
            }
        }
    }
    return n;
}

# ---------------------------------------------------------------------------
# Build true world + agent belief (with a stale, wrong corridor)
# ---------------------------------------------------------------------------
def build_world(seed: int) -> World {
    random.seed(seed);

    world = World();
    rover = Rover(energy=ENERGY_START, x=0, y=0);
    world.rover = [rover];

    tmap: dict = {};
    bmap: dict = {};

    # 1. True terrain
    for y in range(N) {
        for x in range(N) {
            cost = 1;
            r = random.random();
            if r > 0.86 { cost = 3; }
            elif r > 0.66 { cost = 2; }
            haz = 0.0;
            if random.random() > 0.88 { haz = 0.5 + random.random() * 0.5; }
            obst = False;
            if random.random() > 0.87 { obst = True; }
            t = Terrain(x=x, y=y, cost=cost, hazard=haz,
                                  is_obstacle=obst, science_val=0.0);
            tmap[(x, y)] = t;
            b = Belief(x=x, y=y);
            bmap[(x, y)] = b;
        }
    }

    # 2. Keep base/target clear; place science sites
    tmap[(0, 0)].is_obstacle = False;
    tmap[(0, 0)].hazard = 0.0;
    tmap[(TX, TY)].is_obstacle = False;
    tmap[(TX, TY)].hazard = 0.0;
    tmap[(TX, TY)].science_val = 10.0;
    tmap[(TX, TY)].cost = 1;

    for i in range(4) {
        sx = random.randint(2, N - 1);
        sy = random.randint(2, N - 1);
        if not (sx == TX and sy == TY) {
            tmap[(sx, sy)].science_val = 3.0 + random.randint(0, 3);
            tmap[(sx, sy)].is_obstacle = False;
        }
    }

    # 3. Stale corridor prior: clean route along y=0 then x=TX, ONE secret block
    corridor: list = [];
    for x in range(0, N) { corridor.append((x, 0)); }
    for y in range(0, N) { corridor.append((TX, y)); }
    block_x = 6;
    for c in corridor {
        tmap[c].is_obstacle = False;
        tmap[c].hazard = 0.0;
        tmap[c].cost = 1;
    }
    tmap[(block_x, 0)].is_obstacle = True;
    tmap[(block_x, 0)].science_val = 0.0;

    # 4. Initial belief: reveal around base truthfully
    for y in range(N) {
        for x in range(N) {
            if cheb(x, y, 0, 0) <= 2 {
                b = bmap[(x, y)];
                t = tmap[(x, y)];
                b.state = "KNOWN";
                b.confidence = 1.0;
                b.est_cost = t.cost;
                b.est_hazard = t.hazard;
                b.est_obstacle = t.is_obstacle;
                b.est_science = t.science_val;
            }
        }
    }

    # 5. Stale corridor belief: KNOWN + passable, incl. the secret block
    for c in corridor {
        b = bmap[c];
        b.state = "KNOWN";
        b.confidence = 0.5;
        b.est_cost = 1;
        b.est_hazard = 0.0;
        b.est_obstacle = False;
        b.est_science = 0.0;
    }
    bmap[(TX, TY)].est_science = 10.0;

    # 6. Frontier: unknown cells adjacent to known -> UNCERTAIN
    for y in range(N) {
        for x in range(N) {
            b = bmap[(x, y)];
            if b.state == "UNKNOWN" {
                for dy in range(-1, 2) {
                    for dx in range(-1, 2) {
                        xx = x + dx;
                        yy = y + dy;
                        if xx >= 0 and xx < N and yy >= 0 and yy < N {
                            if bmap[(xx, yy)].state == "KNOWN" {
                                b.state = "UNCERTAIN";
                            }
                        }
                    }
                }
            }
        }
    }

    # 7. Belief adjacency is computed on demand from bmap coordinates
    #    (neighbors_of) rather than materialised as graph edges, to keep the
    #    per-run graph mutation small and the simulation fast.

    world.tmap = tmap;
    world.bmap = bmap;
    world.events = ["World built (seed " + str(seed) + "). Stale corridor prior loaded."];
    return world;
}

# ---------------------------------------------------------------------------
# Step: Perceive (the ONLY reader of true Terrain)
# ---------------------------------------------------------------------------
def perceive(world: World) {
        rover = world.rover[0];
        rx = rover.x;
        ry = rover.y;
        tmap = world.tmap;
        bmap = world.bmap;
        for dy in range(-1, 2) {
            for dx in range(-1, 2) {
                xx = rx + dx;
                yy = ry + dy;
                if xx >= 0 and xx < N and yy >= 0 and yy < N {
                    b = bmap[(xx, yy)];
                    t = tmap[(xx, yy)];
                    was_block = b.est_obstacle;
                    b.state = "KNOWN";
                    b.confidence = 1.0;
                    b.est_cost = t.cost;
                    b.est_hazard = t.hazard;
                    b.est_obstacle = t.is_obstacle;
                    b.est_science = t.science_val;
                    if t.is_obstacle and not was_block {
                        world.events.append("Observed obstacle at (" + str(xx) + "," + str(yy) + ")");
                        for rc in world.route {
                            if rc == str(xx) + "," + str(yy) {
                                world.events.append("ROUTE INVALIDATED: obstacle on planned path");
                                world.replanned = True;
                            }
                        }
                    }
                }
            }
        }
        # frontier refresh
        for y in range(N) {
            for x in range(N) {
                bb = bmap[(x, y)];
                if bb.state == "UNKNOWN" {
                    for dy2 in range(-1, 2) {
                        for dx2 in range(-1, 2) {
                            xx2 = x + dx2;
                            yy2 = y + dy2;
                            if xx2 >= 0 and xx2 < N and yy2 >= 0 and yy2 < N {
                                if bmap[(xx2, yy2)].state == "KNOWN" {
                                    bb.state = "UNCERTAIN";
                                }
                            }
                        }
                    }
                }
            }
        }
    }

# ---------------------------------------------------------------------------
# Step: Evaluate candidate actions with explicit scoring (phase-based)
# ---------------------------------------------------------------------------
def evaluate(world: World) {
        rover = world.rover[0];
        bmap = world.bmap;
        rx = rover.x;
        ry = rover.y;
        rb = bmap[(rx, ry)];
        base = bmap[(0, 0)];
        tgt = bmap[(TX, TY)];

        d_tgt = dijkstra_all(bmap, tgt);
        d_base = dijkstra_all(bmap, base);

        world.chosen = "";
        world.arg = "";
        world.candidates_str = "";

        # mission complete -> switch to returning
        if world.phase == "outbound" {
            if rx == TX and ry == TY and rb.est_science <= 0.0 {
                world.phase = "returning";
                world.events.append("Target science secured; mission phase -> returning.");
            }
        }

        cands: list = [];
        best = -1;
        best_score = -1.0e18;
        attempt = 0;

        while attempt < 2 and world.chosen == "" {
            goal_map = d_tgt;
            goal_cur = d_tgt.get((rx, ry), 1.0e18);
            act_name = "move";
            if world.phase == "returning" {
                goal_map = d_base;
                goal_cur = d_base.get((rx, ry), 1.0e18);
                act_name = "return";
            }

            cands = [];
            best_move_progress = -1.0e18;

            # --- neighbor moves ---
            for nb in neighbors_of(bmap, rx, ry) {
                if isinstance(nb, Belief) {
                    if not nb.est_obstacle {
                        if nb.state != "UNKNOWN" {
                            step = 1.0 * nb.est_cost;
                            if nb.state == "UNCERTAIN" { step = step * UNCERTAIN_MULT; }
                            nb_g = goal_map.get((nb.x, nb.y), 1.0e18);
                            progress = goal_cur - nb_g;
                            if progress > best_move_progress { best_move_progress = progress; }
                            info = count_unknown(bmap, nb.x, nb.y);
                            ecost = step * MOVE_E;
                            after = rover.energy - ecost;
                            back = d_base.get((nb.x, nb.y), 1.0e18);
                            need = back * MOVE_E * RETURN_MARGIN + RESERVE;
                            feasible = after >= need;
                            score = (W_PROG * progress + W_INFO * info
                                     - W_TRAVEL * step - W_ENERGY * ecost
                                     - W_HAZ * nb.est_hazard);
                            cands.append({"label": act_name + "(" + str(nb.x) + "," + str(nb.y) + ")",
                                          "score": score, "progress": progress,
                                          "science": 0.0, "info": 1.0 * info,
                                          "travel": step, "energy": ecost,
                                          "hazard": nb.est_hazard, "feasible": feasible,
                                          "action": act_name,
                                          "arg": str(nb.x) + "," + str(nb.y)});
                        }
                    }
                }
            }

            # --- investigate (only when no forward progress is available) ---
            if world.phase == "outbound" and best_move_progress <= 0.0 {
                best_unk: list = [];
                best_unk_info = -1;
                for dy in range(-1, 2) {
                    for dx in range(-1, 2) {
                        xx = rx + dx;
                        yy = ry + dy;
                        if xx >= 0 and xx < N and yy >= 0 and yy < N {
                            ub = bmap[(xx, yy)];
                            if ub.state != "KNOWN" {
                                inf = count_unknown(bmap, xx, yy);
                                if inf > best_unk_info {
                                    best_unk_info = inf;
                                    best_unk = [xx, yy];
                                }
                            }
                        }
                    }
                }
                if len(best_unk) == 2 {
                    after = rover.energy - INV_E;
                    need = d_base.get((rx, ry), 1.0e18) * MOVE_E * RETURN_MARGIN + RESERVE;
                    feasible = after >= need;
                    iscore = W_INFO * (best_unk_info + 2.0) - W_ENERGY * INV_E;
                    cands.append({"label": "investigate(" + str(best_unk[0]) + "," + str(best_unk[1]) + ")",
                                  "score": iscore, "progress": 0.0, "science": 0.0,
                                  "info": 1.0 * best_unk_info, "travel": 0.0,
                                  "energy": INV_E, "hazard": 0.0, "feasible": feasible,
                                  "action": "investigate",
                                  "arg": str(best_unk[0]) + "," + str(best_unk[1])});
                }
            }

            # --- collect (standing on science) ---
            if rb.est_science > 0.0 {
                after = rover.energy - COL_E;
                need = d_base.get((rx, ry), 1.0e18) * MOVE_E * RETURN_MARGIN + RESERVE;
                feasible = after >= need;
                cscore = W_SCI * rb.est_science - W_ENERGY * COL_E;
                cands.append({"label": "collect(" + str(rx) + "," + str(ry) + ")",
                              "score": cscore, "progress": 0.0,
                              "science": rb.est_science, "info": 0.0, "travel": 0.0,
                              "energy": COL_E, "hazard": rb.est_hazard,
                              "feasible": feasible, "action": "collect",
                              "arg": str(rx) + "," + str(ry)});
            }

            # --- select best feasible ---
            best = -1;
            best_score = -1.0e18;
            for i in range(len(cands)) {
                c = cands[i];
                if c["feasible"] {
                    if c["score"] > best_score {
                        best_score = c["score"];
                        best = i;
                    }
                }
            }

            if best >= 0 {
                world.chosen = cands[best]["action"];
                world.arg = cands[best]["arg"];
                world.rationale = ("Selected " + cands[best]["label"]
                                  + " (score " + str(round(best_score, 2))
                                  + "): progress " + str(round(cands[best]["progress"], 2))
                                  + ", info " + str(round(cands[best]["info"], 1))
                                  + ", energy " + str(round(cands[best]["energy"], 1))
                                  + " | return-safe");
            } else {
                if world.phase == "outbound" {
                    world.phase = "returning";
                    world.events.append("Return safety binds; replanning to return home.");
                } else {
                    world.chosen = "hold";
                    world.arg = str(rx) + "," + str(ry);
                    world.status = "stranded";
                    world.rationale = "Stranded: no return-feasible action within energy budget.";
                }
            }
            attempt = attempt + 1;
        }

        # --- record route to target (for invalidation detection) ---
        route: list = [];
        cx = rx;
        cy = ry;
        guard = 0;
        while not (cx == TX and cy == TY) and guard < 400 {
            guard = guard + 1;
            bcur = bmap[(cx, cy)];
            bestn = -1;
            bestv = d_tgt.get((cx, cy), 1.0e18);
            bx = cx;
            by = cy;
            for nb in neighbors_of(bmap, cx, cy) {
                if isinstance(nb, Belief) {
                    v = d_tgt.get((nb.x, nb.y), 1.0e18);
                    if v < bestv {
                        bestv = v;
                        bx = nb.x;
                        by = nb.y;
                        bestn = 1;
                    }
                }
            }
            if bestn < 0 { guard = 400; }
            else {
                cx = bx;
                cy = by;
                route.append(str(cx) + "," + str(cy));
            }
        }
        world.route = route;

        # --- format candidates table ---
        rows: list = [];
        for c in cands {
            feas = "yes";
            if not c["feasible"] { feas = "NO"; }
            mark = "";
            if best >= 0 {
                if c["label"] == cands[best]["label"] { mark = " <== chosen"; }
            }
            rows.append(c["label"] + "|" + str(round(c["score"], 2)) + "|"
                        + str(round(c["progress"], 2)) + "|"
                        + str(round(c["science"], 2)) + "|"
                        + str(round(c["info"], 1)) + "|"
                        + str(round(c["travel"], 2)) + "|"
                        + str(round(c["energy"], 2)) + "|"
                        + str(round(c["hazard"], 2)) + "|" + feas + mark);
        }
        world.candidates_str = "\n".join(rows);
    }

# ---------------------------------------------------------------------------
# Step: Execute the chosen action against the simulator
# ---------------------------------------------------------------------------
def execute(world: World) {
        rover = world.rover[0];
        bmap = world.bmap;
        tmap = world.tmap;
        parts = world.arg.split(",");
        ax = int(parts[0]);
        ay = int(parts[1]);

        if world.chosen == "move" or world.chosen == "return" {
            t = tmap[(ax, ay)];
            if ax == rover.x and ay == rover.y {
                world.events.append("Holding position.");
            } elif t.is_obstacle {
                b = bmap[(ax, ay)];
                b.state = "KNOWN";
                b.confidence = 1.0;
                b.est_obstacle = True;
                world.events.append("MOVE FAILED into obstacle at (" + str(ax) + "," + str(ay) + ") -> belief updated");
                world.replanned = True;
            } else {
                step = 1.0 * bmap[(ax, ay)].est_cost;
                rover.x = ax;
                rover.y = ay;
                rover.energy = rover.energy - step * MOVE_E;
                world.events.append("Moved to (" + str(ax) + "," + str(ay) + ")");
            }
        } elif world.chosen == "investigate" {
            t = tmap[(ax, ay)];
            b = bmap[(ax, ay)];
            b.state = "KNOWN";
            b.confidence = 1.0;
            b.est_cost = t.cost;
            b.est_hazard = t.hazard;
            b.est_obstacle = t.is_obstacle;
            b.est_science = t.science_val;
            rover.energy = rover.energy - INV_E;
            world.events.append("Investigated (" + str(ax) + "," + str(ay) + ")");
        } elif world.chosen == "collect" {
            rb = bmap[(rover.x, rover.y)];
            world.science = world.science + rb.est_science;
            world.collected.append(str(rover.x) + "," + str(rover.y));
            world.events.append("Collected science " + str(rb.est_science) + " at (" + str(rover.x) + "," + str(rover.y) + ")");
            rb.est_science = 0.0;
            tmap[(rover.x, rover.y)].science_val = 0.0;
            rover.energy = rover.energy - COL_E;
        }
    }

# ---------------------------------------------------------------------------
# Server endpoint: run_sim - orchestrates the full loop, returns Frame records
# ---------------------------------------------------------------------------
def:pub run_sim(seed: int, ticks: int) -> list[Frame] {
    world = build_world(seed);
    rover = world.rover[0];
    frames: list[Frame] = [];

    tick = 0;
    while tick < ticks {
        world.replanned = False;
        perceive(world);
        evaluate(world);
        execute(world);

        # status transitions
        if world.status == "active" {
            if world.phase == "returning" and rover.x == 0 and rover.y == 0 {
                world.status = "returned";
            }
            if rover.energy <= 0.0 {
                world.status = "depleted";
            }
        }

        f = Frame(
            tick=tick,
            map_str=encode_terrain(world.tmap, rover.x, rover.y),
            belief_str=encode_belief(world.bmap, rover.x, rover.y),
            rover_x=rover.x, rover_y=rover.y, energy=rover.energy,
            action=world.chosen, rationale=world.rationale,
            replanned=world.replanned,
            candidates_str=world.candidates_str,
            events_str="\n".join(world.events[-3:]),
            science=world.science, status=world.status);
        frames.append(f);

        tick = tick + 1;
        if world.status == "returned" or world.status == "depleted" or world.status == "stranded" {
            tick = ticks;
        }
    }
    return frames;
}

# ---------------------------------------------------------------------------
# Headless debug entry (only runs when executing this file directly)
# ---------------------------------------------------------------------------
with entry:__main__ {
    frames = run_sim(42, 120);
    print("frames:", len(frames));
    for f in frames {
        if f.replanned {
            print("t=" + str(f.tick) + " REPLAN act=" + f.action + " e=" + str(round(f.energy, 1)));
        }
    }
    last = frames[-1];
    print("FINAL status=" + last.status + " sci=" + str(last.science) + " energy=" + str(round(last.energy, 1)));
}

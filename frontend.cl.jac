"""astral - Client-Side UI.

Renders an ASTRAL run: the simulator's true map next to the agent's belief
map, the per-tick decision trace (candidate scores, chosen action, rationale),
and the event log produced by replanning.
"""

import from .components.MapGrid { MapGrid }
import from react { useEffect }

sv import from endpoints { Frame, run_sim }

def btn_style() -> dict {
    return {
        "padding": "0.45rem 0.8rem",
        "borderRadius": "6px",
        "border": "1px solid #334155",
        "backgroundColor": "#1e293b",
        "color": "#e2e8f0",
        "cursor": "pointer"
    };
}

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
    def restart -> None;
    def jumpReplan -> None;

    # Playback: reschedule a one-shot timer each tick (deps playing+idx) so the
    # closure always sees fresh state; the returned cleanup clears any pending
    # timer when playing/idx change or the component unmounts.
    useEffect(lambda {
        timer = setTimeout(lambda {
            if playing {
                if idx < len(frames) - 1 {
                    idx = idx + 1;
                } else {
                    playing = False;
                }
            }
        }, 300);
        return lambda { clearTimeout(timer); };
    }, [playing, idx]);

    return
        <div
            style={{
                "minHeight": "100vh",
                "padding": "1.25rem",
                "fontFamily": "ui-monospace, SFMono-Regular, Menlo, monospace",
                "backgroundColor": "#0f1117",
                "color": "#e2e8f0"
            }}
        >
            <div style={{"maxWidth": "1100px", "margin": "0 auto"}}>
                <h1 style={{"margin": "0", "letterSpacing": "0.08em"}}>ASTRAL</h1>
                <p style={{"margin": "0.25rem 0 1rem", "color": "#94a3b8", "fontSize": "0.9rem"}}>
                    Explainable, non-LLM spatial agent - evidence-driven replanning
                </p>

                <div style={{"display": "flex", "gap": "0.5rem", "alignItems": "center", "marginBottom": "1rem"}}>
                    <label>seed</label>
                    <input
                        type="number"
                        value={seed_str}
                        onChange={lambda e: ChangeEvent { seed_str = e.target.value; }}
                        style={{
                            "width": "80px",
                            "padding": "0.4rem",
                            "borderRadius": "6px",
                            "border": "1px solid #334155",
                            "backgroundColor": "#1e293b",
                            "color": "#e2e8f0"
                        }}
                    />
                    <button
                        onClick={lambda e: MouseEvent { runSim(); }}
                        style={{
                            "padding": "0.45rem 1.1rem",
                            "borderRadius": "6px",
                            "border": "none",
                            "backgroundColor": "#3b82f6",
                            "color": "white",
                            "cursor": "pointer",
                            "fontWeight": "700"
                        }}
                    >
                        Run
                    </button>
                    <button
                        onClick={lambda e: MouseEvent { prev(); }}
                        style={{
                            "padding": "0.45rem 0.8rem",
                            "borderRadius": "6px",
                            "border": "1px solid #334155",
                            "backgroundColor": "#1e293b",
                            "color": "#e2e8f0",
                            "cursor": "pointer"
                        }}
                    >
                        &lt;
                    </button>
                    <button
                        onClick={lambda e: MouseEvent { next(); }}
                        style={{
                            "padding": "0.45rem 0.8rem",
                            "borderRadius": "6px",
                            "border": "1px solid #334155",
                            "backgroundColor": "#1e293b",
                            "color": "#e2e8f0",
                            "cursor": "pointer"
                        }}
                    >
                        &gt;
                    </button>
                    <button
                        onClick={lambda e: MouseEvent { togglePlay(); }}
                        style={btn_style()}
                    >
                        {("Pause" if playing else "Play")}
                    </button>
                    <button
                        onClick={lambda e: MouseEvent { restart(); }}
                        style={btn_style()}
                    >
                        Restart
                    </button>
                    <button
                        onClick={lambda e: MouseEvent { jumpReplan(); }}
                        style={btn_style()}
                    >
                        Jump to replan
                    </button>
                    <span style={{"color": "#94a3b8", "fontSize": "0.85rem"}}>
                        {f"tick {idx} / {len(frames) - 1}"}
                    </span>
                    {[
                        <span style={{"color": "#f59e0b", "fontSize": "0.85rem"}}>running...</span>
                        for _ in [0]
                        if running
                    ]}
                    {[
                        <span style={{"color": "#22c55e", "fontSize": "0.85rem"}}>playing</span>
                        for _ in [0]
                        if playing
                    ]}
                </div>

                {[
                    <div>
                        <input
                            type="range"
                            min="0"
                            max={f"{len(frames) - 1}"}
                            value={f"{idx}"}
                            onChange={lambda e: ChangeEvent { idx = int(e.target.value); }}
                            style={{"width": "100%", "marginBottom": "1rem"}}
                        />

                        <div style={{"display": "flex", "gap": "2rem", "flexWrap": "wrap"}}>
                            <MapGrid rows={frames[idx].map_str.split("\n")} title="SIMULATOR TRUTH (hidden from agent)"/>
                            <MapGrid rows={frames[idx].belief_str.split("\n")} title="AGENT BELIEF (what the rover knows)"/>
                        </div>

                        <div
                            style={{
                                "marginTop": "1rem",
                                "padding": "0.75rem 1rem",
                                "borderRadius": "8px",
                                "border": "1px solid #334155",
                                "fontSize": "0.78rem",
                                "lineHeight": "1.7",
                                "color": "#cbd5e1"
                            }}
                        >
                            <div style={{"fontWeight": "700", "color": "#e2e8f0"}}>HOW TO READ THIS</div>
                            <div style={{"color": "#94a3b8"}}>
                                Left grid is the simulator's ground truth (hidden from the agent). Right grid is the rover's belief.
                                They diverge until the rover observes a cell, then reconcile.
                            </div>
                            <div style={{"marginTop": "0.4rem"}}>
                                <b>TRUTH:</b> . open &nbsp;&middot;&nbsp; : rough (cost 2) &nbsp;&middot;&nbsp; ~ very rough (cost 3) &nbsp;&middot;&nbsp; # obstacle &nbsp;&middot;&nbsp; ! hazard &nbsp;&middot;&nbsp; * science &nbsp;&middot;&nbsp; R rover
                            </div>
                            <div>
                                <b>BELIEF:</b> B base &nbsp;&middot;&nbsp; T target &nbsp;&middot;&nbsp; ? unexplored &nbsp;&middot;&nbsp; ~ uncertain (frontier) &nbsp;&middot;&nbsp; . known passable &nbsp;&middot;&nbsp; # known obstacle &nbsp;&middot;&nbsp; * known science &nbsp;&middot;&nbsp; R rover
                            </div>
                            <div style={{"marginTop": "0.4rem", "color": "#f59e0b"}}>
                                THE DEMO: drag to tick 5. The rover's stale corridor prior claims (6,0) is clear. It observes the obstacle,
                                emits ROUTE INVALIDATED, updates its map, and replans around it - new evidence changing the decision.
                            </div>
                        </div>

                        <div
                            style={{
                                "marginTop": "1rem",
                                "padding": "0.75rem 1rem",
                                "borderRadius": "8px",
                                "backgroundColor": "#1e293b",
                                "fontSize": "0.85rem",
                                "display": "flex",
                                "gap": "1.5rem",
                                "flexWrap": "wrap"
                            }}
                        >
                            <span>{f"action: {frames[idx].action}"}</span>
                            <span>{f"energy: {frames[idx].energy}"}</span>
                            <span>{f"science: {frames[idx].science}"}</span>
                            <span>{f"status: {frames[idx].status}"}</span>
                            {[
                                <span style={{"color": "#f59e0b", "fontWeight": "700"}}>REPLANNED</span>
                                for _ in [0]
                                if frames[idx].replanned
                            ]}
                        </div>

                        <p style={{"fontSize": "0.85rem", "color": "#cbd5e1", "margin": "0.75rem 0"}}>
                            {frames[idx].rationale}
                        </p>

                        <div style={{"display": "flex", "gap": "2rem", "flexWrap": "wrap", "alignItems": "flex-start"}}>
                            <div style={{"flex": "1 1 480px"}}>
                                <div style={{"fontWeight": "700", "fontSize": "0.85rem", "marginBottom": "0.4rem", "color": "#cbd5e1"}}>
                                    CANDIDATE ACTIONS (score decomposition)
                                </div>
                                <table style={{"borderCollapse": "collapse", "fontSize": "0.78rem", "width": "100%"}}>
                                    <thead>
                                        <tr style={{"color": "#94a3b8", "textAlign": "left"}}>
                                            <th style={{"padding": "0.25rem 0.5rem"}}>action</th>
                                            <th style={{"padding": "0.25rem 0.5rem"}}>score</th>
                                            <th style={{"padding": "0.25rem 0.5rem"}}>prog</th>
                                            <th style={{"padding": "0.25rem 0.5rem"}}>sci</th>
                                            <th style={{"padding": "0.25rem 0.5rem"}}>info</th>
                                            <th style={{"padding": "0.25rem 0.5rem"}}>cost</th>
                                            <th style={{"padding": "0.25rem 0.5rem"}}>haz</th>
                                            <th style={{"padding": "0.25rem 0.5rem"}}>safe</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {[
                                            <tr key={f"r{ri}"} style={{"borderTop": "1px solid #334155"}}>
                                                {[
                                                    <td key={f"r{ri}c{ci}"} style={{"padding": "0.25rem 0.5rem"}}>{cell}</td>
                                                    for (ci, cell) in enumerate(row.split("|"))
                                                ]}
                                            </tr>
                                            for (ri, row) in enumerate(frames[idx].candidates_str.split("\n"))
                                        ]}
                                    </tbody>
                                </table>
                            </div>

                            <div style={{"flex": "1 1 320px"}}>
                                <div style={{"fontWeight": "700", "fontSize": "0.85rem", "marginBottom": "0.4rem", "color": "#cbd5e1"}}>
                                    EVENT LOG
                                </div>
                                <div style={{"fontSize": "0.78rem", "color": "#cbd5e1"}}>
                                    {[
                                        <div key={f"e{i}"} style={{"padding": "0.15rem 0"}}>{f"- {ev}"}</div>
                                        for (i, ev) in enumerate(frames[idx].events_str.split("\n"))
                                    ]}
                                </div>
                            </div>
                        </div>
                    </div>
                    for _ in [0]
                    if len(frames) > 0
                ]}

                {[
                    <div style={{"padding": "2rem", "color": "#64748b", "textAlign": "center"}}>
                        Press Run to explore the world.
                    </div>
                    for _ in [0]
                    if len(frames) == 0
                ]}
            </div>
        </div>;
}

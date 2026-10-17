"""A colored grid of map cells for the ASTRAL UI."""

def cell_color(ch: str) -> str {
    if ch == "#" { return "#2b2b3a"; }
    if ch == "*" { return "#f6c945"; }
    if ch == "!" { return "#c0392b"; }
    if ch == "~" { return "#c9a36a"; }
    if ch == ":" { return "#e3d2b0"; }
    if ch == "?" { return "#4a4a5a"; }
    if ch == "R" { return "#3b82f6"; }
    if ch == "B" { return "#22c55e"; }
    if ch == "T" { return "#a855f7"; }
    return "#e9ecef";
}

def cell_text_color(ch: str) -> str {
    if ch == "#" or ch == "?" or ch == "R" or ch == "B" or ch == "T" {
        return "#ffffff";
    }
    return "#1a1a2e";
}

def:pub MapGrid(rows: list[str], title: str) -> JsxElement {
    return
        <div style={{"flex": "0 0 auto"}}>
            <div style={{"fontSize": "0.8rem", "fontWeight": "700", "marginBottom": "0.35rem", "color": "#cbd5e1"}}>{title}</div>
            <div
                style={{
                    "display": "grid",
                    "gridTemplateColumns": "repeat(10, 22px)",
                    "gap": "2px"
                }}
            >
                {[
                    <div
                        key={str(ri) + "-" + str(ci)}
                        style={{
                            "width": "22px",
                            "height": "22px",
                            "display": "flex",
                            "alignItems": "center",
                            "justifyContent": "center",
                            "fontSize": "12px",
                            "borderRadius": "3px",
                            "transition": "background-color 0.25s ease, color 0.25s ease",
                            "backgroundColor": cell_color(ch),
                            "color": cell_text_color(ch)
                        }}
                    >
                        {ch}
                    </div>
                    for (ri, row) in enumerate(rows)
                    for (ci, ch) in enumerate(row.split(""))
                ]}
            </div>
        </div>;
}

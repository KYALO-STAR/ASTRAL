"""Implementations for the ASTRAL frontend component."""

impl app.runSim -> None {
    running = True;
    frames = await run_sim(int(seed_str), 120);
    idx = 0;
    running = False;
    playing = True;
}

impl app.next -> None {
    playing = False;
    if idx < len(frames) - 1 {
        idx = idx + 1;
    }
}

impl app.prev -> None {
    playing = False;
    if idx > 0 {
        idx = idx - 1;
    }
}

impl app.togglePlay -> None {
    if len(frames) == 0 {
        return;
    }
    if playing {
        playing = False;
    } else {
        if idx >= len(frames) - 1 {
            idx = 0;
        }
        playing = True;
    }
}

impl app.restart -> None {
    if len(frames) > 0 {
        idx = 0;
        playing = True;
    }
}

impl app.jumpReplan -> None {
    playing = False;
    found = False;
    for (i, f) in enumerate(frames) {
        if f.replanned and not found {
            idx = i;
            found = True;
        }
    }
}

"""astral - Entry Point.

Combines server-side endpoints with the client-side UI.
"""

import from endpoints { Frame, run_sim }

# Client-side UI
cl {
    import from .frontend { app as ClientApp }

    def:pub app -> JsxElement {
        return <ClientApp/>;
    }
}

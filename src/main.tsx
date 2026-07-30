import { createRoot } from "react-dom/client";
import App from "./App.tsx";
import "./index.css";
import "./v2/tokens.css";
import { installDiagnostics } from "./lib/diagnostics";
import { initGlobalTheme } from "./v2/theme";

installDiagnostics();
initGlobalTheme();

createRoot(document.getElementById("root")!).render(<App />);

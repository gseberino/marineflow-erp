import { createRoot } from "react-dom/client";
import App from "./App.tsx";
import "./index.css";
import { installDiagnostics } from "./lib/diagnostics";

installDiagnostics();

createRoot(document.getElementById("root")!).render(<App />);

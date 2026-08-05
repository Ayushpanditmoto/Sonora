import type { Config } from "tailwindcss";
export default { content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"], theme: { extend: { colors: { background: "#080808", surface: "#121212", muted: "#a7a7a7", brand: "#1ed760" }, boxShadow: { glow: "0 0 42px rgb(30 215 96 / .16)" } } }, plugins: [] } satisfies Config;

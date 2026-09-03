import type { Config } from "tailwindcss";

// Tokens mirror apps/studio-mockups. The mockups are the spec; the values live in
// app/globals.css as CSS variables so the night/day switch is one data attribute.
const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        bg: "var(--bg)",
        panel: "var(--panel)",
        panel2: "var(--panel2)",
        line: "var(--line)",
        txt: "var(--txt)",
        dim: "var(--dim)",
        accent: "var(--accent)",
        cred: "var(--cred)",
        ok: "var(--green)",
        bad: "var(--red)",
        warn: "var(--amber)",
        info: "var(--blue)",
      },
      fontFamily: {
        sans: ["var(--font-sans)"],
        mono: ["var(--font-mono)"],
        disp: ["var(--font-disp)"],
      },
    },
  },
  plugins: [],
};
export default config;

/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './src/**/*.{js,ts,jsx,tsx,mdx}',
    './src/app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        ink: "#1C1917",
        "ink-soft": "#78716C",
        cream: "#FAF8F4",
        card: "#FFFFFF",
        mist: "#EDE7DC",
        accent: "#1D6FE8",
        live: "#059669",
      },
      fontFamily: {
        display: ["var(--font-display)", "Georgia", "serif"],
        body: ["DM Sans", "ui-sans-serif", "system-ui", "sans-serif"],
      },
    },
  },
  plugins: [],
}

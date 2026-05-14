module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/**/*.heex",
    "../lib/**/*.ex"
  ],
  plugins: [require("daisyui")],
  daisyui: {
    themes: [
      {
        mytheme: {
          primary: "#D5DF2E",
          secondary: "#143F72",
          accent: "#22c55e",
          neutral: "#1f2937"
        },
      },
    ],
  },
}
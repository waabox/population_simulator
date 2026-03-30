const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/population_simulator_web/**/*.*ex",
    "../lib/population_simulator_web/**/*.heex"
  ],
  theme: {
    extend: {},
  },
  plugins: []
}

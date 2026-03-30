import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

let Hooks = {}

Hooks.Chart = {
  mounted() {
    this.chart = null
    this.renderChart()
  },
  updated() {
    this.renderChart()
  },
  renderChart() {
    const config = JSON.parse(this.el.dataset.chart)
    if (this.chart) {
      this.chart.destroy()
    }
    import("https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js").then(module => {
      const Chart = window.Chart
      const ctx = this.el.getContext("2d")
      this.chart = new Chart(ctx, config)
    })
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

liveSocket.connect()
window.liveSocket = liveSocket

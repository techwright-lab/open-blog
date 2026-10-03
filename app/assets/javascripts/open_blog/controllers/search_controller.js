import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results"]
  static values = { url: String }

  connect() { this.sequence = (this.sequence || 0) + 1 }

  disconnect() {
    this.sequence++
    clearTimeout(this.timer)
    this.request?.abort()
  }

  search() {
    clearTimeout(this.timer)
    this.request?.abort()
    const sequence = ++this.sequence
    const query = this.inputTarget.value.trim()
    this.resultsTarget.replaceChildren()
    this.resultsTarget.hidden = true
    if (Array.from(query).length < 2 || Array.from(query).length > 100) return
    this.timer = setTimeout(() => this.suggest(query, sequence), 200)
  }

  async suggest(query, sequence) {
    this.request = new AbortController()
    try {
      const url = new URL(this.urlValue, window.location.href)
      url.searchParams.set("q", query)
      const response = await fetch(url, { signal: this.request.signal, headers: { Accept: "application/json" } })
      if (!response.ok) return
      const results = await response.json()
      if (sequence !== this.sequence || !Array.isArray(results)) return
      const items = results.map(result => {
        const item = document.createElement("li")
        const link = document.createElement("a")
        link.href = result.url
        link.textContent = result.title
        item.append(link)
        return item
      })
      this.resultsTarget.replaceChildren(...items)
      this.resultsTarget.hidden = items.length === 0
    } catch (_) {
      // The ordinary GET form remains available when suggestions cannot load.
    }
  }
}

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["label"]
  static values = { systemLabel: String, lightLabel: String, darkLabel: String }

  connect() {
    this.mode = "system"
    try {
      const stored = localStorage.getItem("open-blog-theme")
      if (stored === "light" || stored === "dark") this.mode = stored
    } catch (_) {}
    this.media = window.matchMedia("(prefers-color-scheme: dark)")
    this.onMediaChange = () => this.apply()
    this.onStorage = (event) => {
      if (event.key !== "open-blog-theme" && event.key !== null) return
      this.mode = ["light", "dark"].includes(event.newValue) ? event.newValue : "system"
      this.apply()
    }
    this.media.addEventListener("change", this.onMediaChange)
    window.addEventListener("storage", this.onStorage)
    this.apply()
    this.element.hidden = false
  }

  disconnect() {
    this.media?.removeEventListener("change", this.onMediaChange)
    window.removeEventListener("storage", this.onStorage)
    this.element.hidden = true
  }

  cycle() {
    this.mode = { system: "light", light: "dark", dark: "system" }[this.mode]
    try {
      if (this.mode === "system") localStorage.removeItem("open-blog-theme")
      else localStorage.setItem("open-blog-theme", this.mode)
    } catch (_) {}
    this.apply()
  }

  apply() {
    const root = document.documentElement
    if (this.mode === "system") delete root.dataset.theme
    else root.dataset.theme = this.mode
    const label = this[`${this.mode}LabelValue`]
    if (this.hasLabelTarget) this.labelTarget.textContent = label
    this.element.setAttribute("aria-label", label)
    const surface = getComputedStyle(root).getPropertyValue("--ob-surface").trim()
    if (surface) document.querySelectorAll('meta[name="theme-color"]').forEach(meta => meta.content = surface)
  }
}

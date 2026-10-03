import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["progress"]
  static values = { contentSelector: { type: String, default: "[data-open-blog-content]" } }

  connect() {
    this.content = document.querySelector(this.contentSelectorValue)
    if (!this.content || !this.hasProgressTarget) return
    this.schedule = () => {
      if (!this.frame) this.frame = requestAnimationFrame(() => { this.frame = null; this.update() })
    }
    window.addEventListener("scroll", this.schedule, { passive: true })
    window.addEventListener("resize", this.schedule)
    this.observer = new ResizeObserver(this.schedule)
    this.observer.observe(this.content)
    this.update()
    this.element.hidden = false
  }

  disconnect() {
    window.removeEventListener("scroll", this.schedule)
    window.removeEventListener("resize", this.schedule)
    this.observer?.disconnect()
    cancelAnimationFrame(this.frame)
    this.frame = null
    this.element.hidden = true
  }

  update() {
    const rect = this.content.getBoundingClientRect()
    const distance = rect.height - window.innerHeight
    const progress = distance <= 0 ? (rect.bottom <= window.innerHeight ? 1 : 0) : Math.max(0, Math.min(1, -rect.top / distance))
    this.progressTarget.style.width = `${progress * 100}%`
  }
}

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.links = [...this.element.querySelectorAll('a[href^="#"]')]
    this.headings = this.links.map(link => document.getElementById(decodeURIComponent(link.hash.slice(1))))
    this.schedule = () => {
      if (!this.frame) this.frame = requestAnimationFrame(() => { this.frame = null; this.update() })
    }
    window.addEventListener("scroll", this.schedule, { passive: true })
    window.addEventListener("resize", this.schedule)
    this.update()
  }

  disconnect() {
    window.removeEventListener("scroll", this.schedule)
    window.removeEventListener("resize", this.schedule)
    cancelAnimationFrame(this.frame)
    this.frame = null
    this.links.forEach(link => link.removeAttribute("aria-current"))
  }

  update() {
    let active = this.headings.findIndex(heading => heading)
    this.headings.forEach((heading, index) => {
      if (heading && heading.getBoundingClientRect().top <= 120) active = index
    })
    this.links.forEach((link, index) => {
      if (index === active) link.setAttribute("aria-current", "location")
      else link.removeAttribute("aria-current")
    })
  }
}

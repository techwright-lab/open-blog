import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["code", "button"]
  static values = { copiedLabel: String, errorLabel: String }

  connect() {
    this.connected = true
    this.label = this.buttonTarget.textContent
    this.accessibleLabel = this.buttonTarget.getAttribute("aria-label")
    this.buttonTarget.hidden = !navigator.clipboard?.writeText
  }

  disconnect() {
    this.connected = false
    clearTimeout(this.resetTimer)
    this.restore()
    this.buttonTarget.hidden = true
  }

  async copy() {
    let label
    try {
      await navigator.clipboard.writeText(this.codeTarget.textContent)
      label = this.copiedLabelValue
    } catch (_) {
      label = this.errorLabelValue
    }
    if (!this.connected) return
    clearTimeout(this.resetTimer)
    this.buttonTarget.textContent = label
    this.buttonTarget.setAttribute("aria-label", label)
    this.resetTimer = setTimeout(() => this.restore(), 2000)
  }

  restore() {
    this.buttonTarget.textContent = this.label
    this.buttonTarget.setAttribute("aria-label", this.accessibleLabel)
  }
}

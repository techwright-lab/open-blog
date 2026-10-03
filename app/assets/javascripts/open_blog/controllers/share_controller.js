import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["device", "copy", "status"]
  static values = { url: String, title: String, copiedLabel: String, copyLabel: String, errorLabel: String }

  connect() {
    this.connected = true
    if (this.hasDeviceTarget) this.deviceTarget.hidden = typeof navigator.share !== "function"
    if (this.hasCopyTarget) this.copyTarget.hidden = !navigator.clipboard?.writeText
  }

  disconnect() {
    this.connected = false
    clearTimeout(this.resetTimer)
    if (this.hasDeviceTarget) this.deviceTarget.hidden = true
    if (this.hasCopyTarget) {
      this.copyTarget.hidden = true
    }
    if (this.hasStatusTarget) this.statusTarget.textContent = ""
  }

  async share() {
    try {
      await navigator.share({ title: this.titleValue, url: this.urlValue })
    } catch (error) {
      if (error.name !== "AbortError") this.announce(this.errorLabelValue)
    }
  }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.urlValue)
      this.announce(this.copiedLabelValue)
    } catch (_) {
      this.announce(this.errorLabelValue)
    }
  }

  announce(label) {
    if (!this.connected) return
    clearTimeout(this.resetTimer)
    if (this.hasStatusTarget) this.statusTarget.textContent = label
    this.resetTimer = setTimeout(() => {
      if (this.hasStatusTarget) this.statusTarget.textContent = ""
    }, 2000)
  }
}

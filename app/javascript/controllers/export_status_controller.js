import { Controller } from "@hotwired/stimulus"

// Reloads the Downloads list every few seconds while a file is being prepared.
export default class extends Controller {
  static values = { running: Boolean, url: String }

  connect() {
    if (this.runningValue) this.timer = window.setTimeout(() => this.reload(), 4000)
  }

  disconnect() {
    window.clearTimeout(this.timer)
  }

  reload() {
    const frame = this.element.closest("turbo-frame")
    if (!frame) return

    const target = new URL(this.urlValue, window.location.href).href
    if (frame.src && new URL(frame.src, window.location.href).href === target) {
      frame.reload()
    } else {
      frame.src = this.urlValue
    }
  }
}

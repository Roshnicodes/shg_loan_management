import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "button"]

  toggle() {
    const show = this.inputTarget.type === "password"
    this.inputTarget.type = show ? "text" : "password"
    this.buttonTarget.classList.toggle("is-visible", show)
    this.buttonTarget.setAttribute("aria-label", show ? "Hide password" : "Show password")
    this.buttonTarget.setAttribute("title", show ? "Hide password" : "Show password")
  }
}

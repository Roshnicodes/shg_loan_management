import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "image"]

  open() {
    if (this.hasImageTarget && !this.imageTarget.src) {
      this.imageTarget.src = this.imageTarget.dataset.src
    }

    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }
}

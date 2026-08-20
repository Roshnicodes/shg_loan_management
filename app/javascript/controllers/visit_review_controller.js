import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "image"]

  connect() {
    this.rotation = 0
    this.applyRotation()
  }

  open() {
    if (this.hasImageTarget && !this.imageTarget.src) {
      this.imageTarget.src = this.imageTarget.dataset.src
    }

    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  rotateLeft() {
    this.rotation -= 90
    this.applyRotation()
  }

  rotateRight() {
    this.rotation += 90
    this.applyRotation()
  }

  resetRotation() {
    this.rotation = 0
    this.applyRotation()
  }

  applyRotation() {
    if (!this.hasImageTarget) return

    const normalizedRotation = ((this.rotation % 360) + 360) % 360
    this.imageTarget.style.setProperty("--visit-photo-rotation", `${normalizedRotation}deg`)
  }
}

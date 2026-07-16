import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "table", "count", "empty"]

  connect() {
    this.rows = Array.from(this.tableTarget.querySelectorAll("tbody tr"))
    this.update()
  }

  update() {
    const query = this.inputTarget.value.trim().toLowerCase()
    let visible = 0

    this.rows.forEach((row) => {
      const matches = row.textContent.toLowerCase().includes(query)
      row.hidden = !matches
      if (matches) visible += 1
    })

    if (this.hasCountTarget) {
      this.countTarget.textContent = `${visible} shown`
    }

    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = visible !== 0
    }
  }

  clear() {
    this.inputTarget.value = ""
    this.update()
    this.inputTarget.focus()
  }
}

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "toggle", "menu", "options", "selected"]
  static values = { placeholder: String }

  connect() {
    this.onDocumentClick = (event) => {
      if (!this.element.contains(event.target)) this.close()
    }
    document.addEventListener("click", this.onDocumentClick)
    this.render()
  }

  disconnect() {
    document.removeEventListener("click", this.onDocumentClick)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    const opening = this.menuTarget.hidden
    this.menuTarget.hidden = !opening
    this.toggleTarget.classList.toggle("open", opening)
  }

  close() {
    if (!this.hasMenuTarget) return

    this.menuTarget.hidden = true
    this.toggleTarget.classList.remove("open")
  }

  selectChanged() {
    this.render()
  }

  refresh() {
    this.render()
  }

  toggleOption(event) {
    event.preventDefault()
    event.stopPropagation()

    const option = Array.from(this.selectTarget.options).find((item) => item.value === event.currentTarget.dataset.value)
    if (!option) return

    option.selected = !option.selected
    this.selectTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  removeSelection(event) {
    event.preventDefault()
    event.stopPropagation()

    const option = Array.from(this.selectTarget.options).find((item) => item.value === event.currentTarget.dataset.value)
    if (!option) return

    option.selected = false
    this.selectTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  render() {
    this.renderOptions()
    this.renderSelected()
    this.updateToggle()
  }

  renderOptions() {
    this.optionsTarget.innerHTML = ""
    const options = Array.from(this.selectTarget.options).filter((option) => option.value !== "")

    if (options.length === 0) {
      const empty = document.createElement("div")
      empty.className = "multi-select-empty"
      empty.textContent = "No options"
      this.optionsTarget.appendChild(empty)
      return
    }

    options.forEach((option) => {
      const item = document.createElement("button")
      item.type = "button"
      item.className = "multi-select-option"
      item.dataset.value = option.value
      item.setAttribute("aria-checked", option.selected ? "true" : "false")
      item.addEventListener("click", (event) => this.toggleOption(event))

      const check = document.createElement("span")
      check.className = "multi-select-check"
      check.setAttribute("aria-hidden", "true")

      const text = document.createElement("span")
      text.textContent = option.textContent

      item.append(check, text)
      this.optionsTarget.appendChild(item)
    })
  }

  renderSelected() {
    this.selectedTarget.innerHTML = ""
    const selected = this.selectedOptions()

    if (selected.length === 0) {
      const empty = document.createElement("span")
      empty.className = "selected-options-empty"
      empty.textContent = "No selection"
      this.selectedTarget.appendChild(empty)
      return
    }

    selected.forEach((option) => {
      const chip = document.createElement("button")
      chip.type = "button"
      chip.className = "selected-option-chip"
      chip.dataset.value = option.value
      chip.textContent = option.textContent
      chip.setAttribute("aria-label", `Remove ${option.textContent}`)
      chip.addEventListener("click", (event) => this.removeSelection(event))
      this.selectedTarget.appendChild(chip)
    })
  }

  updateToggle() {
    const selected = this.selectedOptions()
    if (selected.length === 0) {
      this.toggleTarget.textContent = this.placeholderValue || "All"
    } else if (selected.length === 1) {
      this.toggleTarget.textContent = selected[0].textContent
    } else {
      this.toggleTarget.textContent = `${selected.length} selected`
    }
  }

  selectedOptions() {
    return Array.from(this.selectTarget.selectedOptions).filter((option) => option.value !== "")
  }
}

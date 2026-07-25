import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.classList.add("searchable-select-native")
    this.element.tabIndex = -1

    this.wrapper = document.createElement("div")
    this.wrapper.className = "searchable-select"

    this.input = document.createElement("input")
    this.input.type = "text"
    this.input.className = "searchable-select-input"
    this.input.placeholder = this.promptText()
    this.input.autocomplete = "off"

    this.menu = document.createElement("div")
    this.menu.className = "searchable-select-menu"
    this.menu.hidden = true

    this.wrapper.append(this.input, this.menu)
    this.element.after(this.wrapper)

    this.onInput = () => this.renderOptions()
    this.onFocus = () => this.open()
    this.onKeydown = (event) => this.handleKeydown(event)
    this.onSelectChange = () => this.syncInput()
    this.onRefresh = () => this.refresh()
    this.onInvalid = () => this.input.focus()
    this.onDocumentClick = (event) => {
      if (!this.wrapper.contains(event.target)) this.close()
    }

    this.input.addEventListener("input", this.onInput)
    this.input.addEventListener("focus", this.onFocus)
    this.input.addEventListener("keydown", this.onKeydown)
    this.element.addEventListener("change", this.onSelectChange)
    this.element.addEventListener("searchable-select:refresh", this.onRefresh)
    this.element.addEventListener("invalid", this.onInvalid)
    document.addEventListener("click", this.onDocumentClick)

    this.syncState()
    this.syncInput()
  }

  disconnect() {
    document.removeEventListener("click", this.onDocumentClick)
    this.input?.removeEventListener("input", this.onInput)
    this.input?.removeEventListener("focus", this.onFocus)
    this.input?.removeEventListener("keydown", this.onKeydown)
    this.element.removeEventListener("change", this.onSelectChange)
    this.element.removeEventListener("searchable-select:refresh", this.onRefresh)
    this.element.removeEventListener("invalid", this.onInvalid)
    this.wrapper?.remove()
    this.element.classList.remove("searchable-select-native")
    this.element.removeAttribute("tabindex")
  }

  open() {
    this.renderOptions()
    this.menu.hidden = false
  }

  close() {
    if (this.menu) this.menu.hidden = true
    this.syncInput()
  }

  refresh() {
    this.syncState()
    this.syncInput()
    if (!this.menu.hidden) this.renderOptions()
  }

  syncState() {
    this.input.disabled = this.element.disabled
  }

  syncInput() {
    const selected = this.element.selectedOptions[0]
    this.input.value = selected?.value ? selected.textContent.trim() : ""
  }

  renderOptions() {
    const query = this.input.value.trim().toLowerCase()
    const options = Array.from(this.element.options).filter((option) => {
      return (option.value === "" && query === "") || option.textContent.toLowerCase().includes(query)
    })

    this.menu.innerHTML = ""

    if (options.length === 0) {
      const empty = document.createElement("div")
      empty.className = "searchable-select-empty"
      empty.textContent = "No results"
      this.menu.appendChild(empty)
      return
    }

    options.forEach((option) => {
      const item = document.createElement("button")
      item.type = "button"
      item.className = "searchable-select-option"
      item.textContent = option.textContent
      item.dataset.value = option.value
      item.setAttribute("aria-selected", option.value === this.element.value ? "true" : "false")
      item.addEventListener("mousedown", (event) => event.preventDefault())
      item.addEventListener("click", () => this.choose(option.value))
      this.menu.appendChild(item)
    })
  }

  choose(value) {
    this.element.value = value
    this.element.dispatchEvent(new Event("change", { bubbles: true }))
    this.close()
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      this.close()
      return
    }

    if (event.key !== "Enter") return

    const firstOption = this.menu.querySelector(".searchable-select-option")
    if (!this.menu.hidden && firstOption) {
      event.preventDefault()
      this.choose(firstOption.dataset.value)
    }
  }

  promptText() {
    const prompt = Array.from(this.element.options).find((option) => option.value === "")
    return prompt?.textContent.trim() || "Search..."
  }
}

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "role", "state", "district", "block", "village",
    "stateField", "districtField", "blockField", "villageField", "password",
    "districtSelected", "blockSelected", "villageSelected",
    "districtOptions", "blockOptions", "villageOptions",
    "districtToggle", "blockToggle", "villageToggle",
    "districtMenu", "blockMenu", "villageMenu",
    "districtSelectAll"
  ]

  connect() {
    this.districtOptions = this.cloneOptions(this.districtTarget)
    this.blockOptions = this.cloneOptions(this.blockTarget)
    this.villageOptions = this.cloneOptions(this.villageTarget)
    this.closeMenus()
    this.refresh()
  }

  roleChanged() {
    this.applyRoleVisibility()
  }

  stateChanged() {
    this.clear(this.districtTarget)
    this.clear(this.blockTarget)
    this.clear(this.villageTarget)
    this.refresh()
  }

  districtChanged() {
    this.clear(this.blockTarget)
    this.clear(this.villageTarget)
    this.refresh()
  }

  blockChanged() {
    this.clear(this.villageTarget)
    this.refresh()
  }

  selectAll(event) {
    const target = this[`${event.params.select}Target`]
    Array.from(target.options).forEach((option) => {
      option.selected = option.value !== ""
    })
    target.dispatchEvent(new Event("change", { bubbles: true }))
    this.closeMenus()
  }

  togglePassword(event) {
    const button = event.currentTarget
    const input = button.closest(".password-field")?.querySelector("input")
    if (!input) return

    const show = input.type === "password"
    input.type = show ? "text" : "password"
    button.textContent = show ? "Hide" : "Show"
    button.setAttribute("aria-label", show ? "Hide password" : "Show password")
  }

  toggleDropdown(event) {
    const name = event.params.select
    const menu = this[`${name}MenuTarget`]
    const isOpen = !menu.hidden

    this.closeMenus()
    menu.hidden = isOpen
    this[`${name}ToggleTarget`].classList.toggle("open", !isOpen)
  }

  refresh() {
    this.filterSelect(this.districtTarget, this.districtOptions, "stateId", this.selectedValues(this.stateTarget), false)
    this.filterSelect(this.blockTarget, this.blockOptions, "districtId", this.selectedValues(this.districtTarget), false)
    this.filterSelect(this.villageTarget, this.villageOptions, "blockId", this.selectedValues(this.blockTarget), false)
    this.applyRoleVisibility()
    this.renderDropdownOptions()
    this.renderSelectedSummaries()
  }

  applyRoleVisibility() {
    const role = this.selectedRole()
    const adminRole = ["ADMIN", "ASSIST_ADMIN", "ASSISTANT_ADMIN"].includes(role)
    const districtRole = ["DIST_COORDINATOR", "DISTRICT_COORDINATOR"].includes(role)
    const crpRole = role === "CRP"

    this.stateFieldTarget.hidden = false
    this.districtFieldTarget.hidden = !role || adminRole
    this.blockFieldTarget.hidden = !role || adminRole
    this.villageFieldTarget.hidden = !role || adminRole || districtRole
    this.districtSelectAllTarget.hidden = true

    if (adminRole) {
      this.clear(this.districtTarget)
      this.clear(this.blockTarget)
      this.clear(this.villageTarget)
    } else if (districtRole) {
      this.clear(this.villageTarget)
      this.keepSingleSelection(this.districtTarget)
    } else if (crpRole) {
      this.keepSingleSelection(this.districtTarget)
    } else if (role) {
      this.villageFieldTarget.hidden = false
    }

    this.renderSelectedSummaries()
  }

  filterSelect(select, originalOptions, parentKey, parentValues, allowAll = true) {
    const selectedValues = this.selectedValues(select)
    select.innerHTML = ""

    if (!allowAll && parentValues.length === 0) {
      return
    }

    originalOptions.forEach((option) => {
      if (parentValues.length === 0 || parentValues.includes(option.dataset[parentKey])) {
        const clone = option.cloneNode(true)
        clone.selected = selectedValues.includes(clone.value)
        select.appendChild(clone)
      }
    })
  }

  selectedRole() {
    return this.roleTarget.selectedOptions[0]?.dataset.role || ""
  }

  renderSelectedSummaries() {
    this.renderSelectedSummary(this.districtTarget, this.districtSelectedTarget, "district")
    this.renderSelectedSummary(this.blockTarget, this.blockSelectedTarget, "block")
    this.renderSelectedSummary(this.villageTarget, this.villageSelectedTarget, "village")
    this.updateToggleText(this.districtTarget, this.districtToggleTarget, "districts")
    this.updateToggleText(this.blockTarget, this.blockToggleTarget, "blocks")
    this.updateToggleText(this.villageTarget, this.villageToggleTarget, "villages")
  }

  renderDropdownOptions() {
    this.renderDropdownOptionList(this.districtTarget, this.districtOptionsTarget, "district")
    this.renderDropdownOptionList(this.blockTarget, this.blockOptionsTarget, "block")
    this.renderDropdownOptionList(this.villageTarget, this.villageOptionsTarget, "village")
  }

  renderDropdownOptionList(select, container, name) {
    const selectedValues = this.selectedValues(select)
    container.innerHTML = ""

    if (select.options.length === 0) {
      const empty = document.createElement("div")
      empty.className = "multi-select-empty"
      empty.textContent = this.emptyMessage(name)
      container.appendChild(empty)
      return
    }

    Array.from(select.options).forEach((option) => {
      if (option.value === "") return

      const item = document.createElement("label")
      item.className = "multi-select-option"

      const checkbox = document.createElement("input")
      checkbox.type = name === "district" ? "radio" : "checkbox"
      checkbox.name = `user_mapping_${name}`
      checkbox.checked = selectedValues.includes(option.value)
      checkbox.dataset.select = name
      checkbox.dataset.value = option.value
      checkbox.addEventListener("change", () => this.setSelection(checkbox.dataset.select, checkbox.dataset.value, checkbox.checked))

      const text = document.createElement("span")
      text.textContent = option.textContent

      item.appendChild(checkbox)
      item.appendChild(text)
      container.appendChild(item)
    })
  }

  emptyMessage(name) {
    if (name === "district") return "Please select state first"
    if (name === "block") return "Please select district first"
    return "Please select block first"
  }

  setSelection(selectName, value, selected) {
    const select = this[`${selectName}Target`]
    if (selectName === "district" && selected) {
      this.clear(select)
    }
    const option = Array.from(select.options).find((item) => item.value === value)
    if (option) option.selected = selected
    select.dispatchEvent(new Event("change", { bubbles: true }))
    this.renderDropdownOptions()
    this.renderSelectedSummaries()
    this.closeMenus()
  }

  updateToggleText(select, toggle, label) {
    const selectedOptions = Array.from(select.selectedOptions).filter((option) => option.value !== "")
    if (selectedOptions.length === 0) {
      toggle.textContent = `Select ${label}`
    } else if (selectedOptions.length === 1) {
      toggle.textContent = selectedOptions[0].textContent
    } else {
      toggle.textContent = `${selectedOptions.length} ${label} selected`
    }
  }

  renderSelectedSummary(select, container, name) {
    const selectedOptions = Array.from(select.selectedOptions).filter((option) => option.value !== "")
    container.innerHTML = ""

    if (selectedOptions.length === 0) {
      const empty = document.createElement("span")
      empty.className = "selected-options-empty"
      empty.textContent = "No selection"
      container.appendChild(empty)
      return
    }

    selectedOptions.forEach((option) => {
      const chip = document.createElement("button")
      chip.type = "button"
      chip.className = "selected-option-chip"
      chip.dataset.value = option.value
      chip.dataset.select = name
      chip.textContent = option.textContent
      chip.setAttribute("aria-label", `Remove ${option.textContent}`)
      chip.addEventListener("click", () => this.removeSelection(chip.dataset.select, chip.dataset.value))
      container.appendChild(chip)
    })
  }

  removeSelection(selectName, value) {
    this.setSelection(selectName, value, false)
  }

  selectedValues(select) {
    return Array.from(select.selectedOptions).map((option) => option.value).filter(Boolean)
  }

  clear(select) {
    Array.from(select.options).forEach((option) => {
      option.selected = false
    })
  }

  keepSingleSelection(select) {
    const selected = this.selectedValues(select)
    if (selected.length <= 1) return

    Array.from(select.options).forEach((option) => {
      option.selected = option.value === selected[0]
    })
  }

  cloneOptions(select) {
    return Array.from(select.options).map((option) => option.cloneNode(true))
  }

  closeMenus() {
    this.districtMenuTarget.hidden = true
    this.blockMenuTarget.hidden = true
    this.villageMenuTarget.hidden = true
    this.districtToggleTarget.classList.remove("open")
    this.blockToggleTarget.classList.remove("open")
    this.villageToggleTarget.classList.remove("open")
  }
}

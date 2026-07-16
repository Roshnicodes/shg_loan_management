import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["village", "shg", "member"]

  connect() {
    this.shgOptions = this.cloneOptions(this.shgTarget)
    this.memberOptions = this.cloneOptions(this.memberTarget)
    this.filterAll()
  }

  villageChanged() {
    this.shgTarget.value = ""
    this.memberTarget.value = ""
    this.filterAll()
  }

  shgChanged() {
    this.memberTarget.value = ""
    this.filterAll()
  }

  filterAll() {
    this.filterSelect(this.shgTarget, this.shgOptions, "villageId", this.villageTarget.value)
    this.filterSelect(this.memberTarget, this.memberOptions, "shgId", this.shgTarget.value)
  }

  cloneOptions(select) {
    return Array.from(select.options).map((option) => option.cloneNode(true))
  }

  filterSelect(select, originalOptions, parentKey, parentValue) {
    const selectedValue = select.value
    select.innerHTML = ""

    originalOptions.forEach((option) => {
      if (option.value === "" || (parentValue && option.dataset[parentKey] === parentValue)) {
        select.appendChild(option.cloneNode(true))
      }
    })

    if (Array.from(select.options).some((option) => option.value === selectedValue)) {
      select.value = selectedValue
    }
  }
}

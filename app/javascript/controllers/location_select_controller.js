import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["state", "district", "block", "village"]

  connect() {
    this.districtOptions = this.cloneOptions(this.districtTarget)
    this.blockOptions = this.cloneOptions(this.blockTarget)
    this.villageOptions = this.cloneOptions(this.villageTarget)
    this.filterAll()
  }

  filterAll() {
    this.filterSelect(this.districtTarget, this.districtOptions, "stateId", this.stateTarget.value)
    this.filterSelect(this.blockTarget, this.blockOptions, "districtId", this.districtTarget.value)
    this.filterSelect(this.villageTarget, this.villageOptions, "blockId", this.blockTarget.value)
  }

  stateChanged() {
    this.districtTarget.value = ""
    this.blockTarget.value = ""
    this.villageTarget.value = ""
    this.filterAll()
  }

  districtChanged() {
    this.blockTarget.value = ""
    this.villageTarget.value = ""
    this.filterAll()
  }

  blockChanged() {
    this.villageTarget.value = ""
    this.filterAll()
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

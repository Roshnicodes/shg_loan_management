import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["state", "district", "block", "village", "crp", "dc"]

  connect() {
    this.districtOptions = this.cloneOptions(this.districtTarget)
    this.blockOptions = this.cloneOptions(this.blockTarget)
    this.villageOptions = this.cloneOptions(this.villageTarget)
    this.crpOptions = this.hasCrpTarget ? this.cloneOptions(this.crpTarget) : []
    this.dcOptions = this.hasDcTarget ? this.cloneOptions(this.dcTarget) : []
    this.filterAll()
  }

  filterAll() {
    this.filterSelect(this.districtTarget, this.districtOptions, "stateId", this.stateTarget.value)
    this.filterSelect(this.blockTarget, this.blockOptions, "districtId", this.districtTarget.value)
    this.filterSelect(this.villageTarget, this.villageOptions, "blockId", this.blockTarget.value)
    if (this.hasCrpTarget) this.filterUserSelect(this.crpTarget, this.crpOptions)
    if (this.hasDcTarget) this.filterUserSelect(this.dcTarget, this.dcOptions)
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
    if (!select.options) return []

    return Array.from(select.options).map((option) => option.cloneNode(true))
  }

  filterSelect(select, originalOptions, parentKey, parentValue) {
    if (!select.options) return

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

  filterUserSelect(select, originalOptions) {
    if (!select) return

    const selectedValue = select.value
    select.innerHTML = ""

    originalOptions.forEach((option) => {
      if (option.value === "" || this.optionMatchesLocation(option)) {
        select.appendChild(option.cloneNode(true))
      }
    })

    if (Array.from(select.options).some((option) => option.value === selectedValue)) {
      select.value = selectedValue
    }
  }

  optionMatchesLocation(option) {
    return this.matchesIds(option.dataset.stateIds, this.stateTarget.value) &&
      this.matchesIds(option.dataset.districtIds, this.districtTarget.value) &&
      this.matchesIds(option.dataset.blockIds, this.blockTarget.value) &&
      this.matchesIds(option.dataset.villageIds, this.villageTarget.value)
  }

  matchesIds(ids, selectedId) {
    if (!selectedId) return true
    return (ids || "").split(" ").includes(selectedId)
  }
}

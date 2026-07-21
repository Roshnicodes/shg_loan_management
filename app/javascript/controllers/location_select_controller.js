import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["state", "district", "block", "village", "crp", "dc"]

  connect() {
    this.districtOptions = this.hasDistrictTarget ? this.cloneOptions(this.districtTarget) : []
    this.blockOptions = this.hasBlockTarget ? this.cloneOptions(this.blockTarget) : []
    this.villageOptions = this.hasVillageTarget ? this.cloneOptions(this.villageTarget) : []
    this.crpOptions = this.hasCrpTarget ? this.cloneOptions(this.crpTarget) : []
    this.dcOptions = this.hasDcTarget ? this.cloneOptions(this.dcTarget) : []
    this.filterAll()
  }

  filterAll() {
    if (this.hasDistrictTarget && this.hasStateTarget) {
      this.filterSelect(this.districtTarget, this.districtOptions, "stateId", this.stateTarget.value)
    }

    if (this.hasBlockTarget) {
      if (this.hasDistrictTarget) {
        this.filterSelect(this.blockTarget, this.blockOptions, "districtId", this.districtTarget.value)
      } else {
        this.restoreSelect(this.blockTarget, this.blockOptions)
      }
    }

    if (this.hasVillageTarget && this.hasBlockTarget) {
      this.filterSelect(this.villageTarget, this.villageOptions, "blockId", this.blockTarget.value)
    }

    if (this.hasCrpTarget) this.filterUserSelect(this.crpTarget, this.crpOptions)
    if (this.hasDcTarget) this.filterUserSelect(this.dcTarget, this.dcOptions)
  }

  stateChanged() {
    if (this.hasDistrictTarget) this.districtTarget.value = ""
    if (this.hasBlockTarget) this.blockTarget.value = ""
    if (this.hasVillageTarget) this.villageTarget.value = ""
    this.filterAll()
  }

  districtChanged() {
    if (this.hasBlockTarget) this.blockTarget.value = ""
    if (this.hasVillageTarget) this.villageTarget.value = ""
    this.filterAll()
  }

  blockChanged() {
    if (this.hasVillageTarget) this.villageTarget.value = ""
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

  restoreSelect(select, originalOptions) {
    if (!select.options) return

    const selectedValue = select.value
    select.innerHTML = ""
    originalOptions.forEach((option) => select.appendChild(option.cloneNode(true)))

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
    const stateId = this.hasStateTarget ? this.stateTarget.value : ""
    const districtId = this.hasDistrictTarget ? this.districtTarget.value : ""
    const blockId = this.hasBlockTarget ? this.blockTarget.value : ""
    const villageId = this.hasVillageTarget ? this.villageTarget.value : ""

    return this.matchesIds(option.dataset.stateIds, stateId) &&
      this.matchesIds(option.dataset.districtIds, districtId) &&
      this.matchesIds(option.dataset.blockIds, blockId) &&
      this.matchesIds(option.dataset.villageIds, villageId)
  }

  matchesIds(ids, selectedId) {
    if (!selectedId) return true
    return (ids || "").split(" ").includes(selectedId)
  }
}

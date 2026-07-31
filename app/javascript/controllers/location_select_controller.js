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
      if (option.value === "" || !parentValue || option.dataset[parentKey] === parentValue) {
        select.appendChild(option.cloneNode(true))
      }
    })

    if (Array.from(select.options).some((option) => option.value === selectedValue)) {
      select.value = selectedValue
    } else {
      select.value = ""
    }

    this.refreshSearchableSelect(select)
  }

  restoreSelect(select, originalOptions) {
    if (!select.options) return

    const selectedValue = select.value
    select.innerHTML = ""
    originalOptions.forEach((option) => select.appendChild(option.cloneNode(true)))

    if (Array.from(select.options).some((option) => option.value === selectedValue)) {
      select.value = selectedValue
    } else {
      select.value = ""
    }

    this.refreshSearchableSelect(select)
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

    this.refreshSearchableSelect(select)
  }

  optionMatchesLocation(option) {
    const selected = this.selectedLocation()
    const stateIds = this.optionIdSet(option.dataset.stateIds)
    const districtIds = this.optionIdSet(option.dataset.districtIds)
    const blockIds = this.optionIdSet(option.dataset.blockIds)
    const villageIds = this.optionIdSet(option.dataset.villageIds)

    if (selected.villageId) {
      return stateIds.has(selected.stateId) ||
        districtIds.has(selected.districtId) ||
        blockIds.has(selected.blockId) ||
        villageIds.has(selected.villageId)
    }

    if (selected.blockId) {
      return stateIds.has(selected.stateId) ||
        districtIds.has(selected.districtId) ||
        blockIds.has(selected.blockId)
    }

    if (selected.districtId) {
      return stateIds.has(selected.stateId) ||
        districtIds.has(selected.districtId)
    }

    if (selected.stateId) return stateIds.has(selected.stateId)
    return true
  }

  selectedLocation() {
    const districtOption = this.selectedOption(this.hasDistrictTarget ? this.districtTarget : null)
    const blockOption = this.selectedOption(this.hasBlockTarget ? this.blockTarget : null)
    const villageOption = this.selectedOption(this.hasVillageTarget ? this.villageTarget : null)

    return {
      stateId: (this.hasStateTarget && this.stateTarget.value) || districtOption?.dataset.stateId || blockOption?.dataset.stateId || villageOption?.dataset.stateId || "",
      districtId: (this.hasDistrictTarget && this.districtTarget.value) || blockOption?.dataset.districtId || villageOption?.dataset.districtId || "",
      blockId: (this.hasBlockTarget && this.blockTarget.value) || villageOption?.dataset.blockId || "",
      villageId: this.hasVillageTarget ? this.villageTarget.value : ""
    }
  }

  selectedOption(select) {
    if (!select || !select.value) return null
    return select.selectedOptions[0]
  }

  optionIdSet(ids) {
    return new Set((ids || "").split(" ").filter(Boolean))
  }

  refreshSearchableSelect(select) {
    select.dispatchEvent(new CustomEvent("searchable-select:refresh"))
  }
}

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["state", "district", "block", "village", "shg", "member", "loan", "crp", "dc"]
  static values = { autoSubmit: Boolean, remote: Boolean }

  connect() {
    this.districtOptions = this.hasDistrictTarget ? this.cloneOptions(this.districtTarget) : []
    this.blockOptions = this.hasBlockTarget ? this.cloneOptions(this.blockTarget) : []
    this.villageOptions = this.hasVillageTarget ? this.cloneOptions(this.villageTarget) : []
    this.shgOptions = this.hasShgTarget ? this.cloneOptions(this.shgTarget) : []
    this.memberOptions = this.hasMemberTarget ? this.cloneOptions(this.memberTarget) : []
    this.loanOptions = this.hasLoanTarget ? this.cloneOptions(this.loanTarget) : []
    this.crpOptions = this.hasCrpTarget ? this.cloneOptions(this.crpTarget) : []
    this.dcOptions = this.hasDcTarget ? this.cloneOptions(this.dcTarget) : []
    this.filterAll()
    if (this.remoteValue) this.refreshRemoteOptions()
  }

  filterAll() {
    if (this.hasDistrictTarget && this.hasStateTarget) {
      this.filterSelect(this.districtTarget, this.districtOptions, "stateId", this.stateTarget.value)
    }

    if (this.hasBlockTarget) {
      if (this.hasDistrictTarget) {
        this.filterSelect(this.blockTarget, this.blockOptions, "districtId", this.districtTarget.value)
      }
    }

    if (this.hasVillageTarget && this.hasBlockTarget) {
      this.filterSelect(this.villageTarget, this.villageOptions, "blockId", this.blockTarget.value)
    }

    if (this.hasCrpTarget) this.filterUserSelect(this.crpTarget, this.crpOptions)
    if (this.hasDcTarget) this.filterUserSelect(this.dcTarget, this.dcOptions)

    if (this.hasShgTarget) this.filterShgSelect()
    if (this.hasMemberTarget) this.filterMemberSelect()
    if (this.hasLoanTarget) this.filterLoanSelect()
  }

  stateChanged() {
    if (this.hasDistrictTarget) this.districtTarget.value = ""
    if (this.hasBlockTarget) this.blockTarget.value = ""
    if (this.hasVillageTarget) this.villageTarget.value = ""
    if (this.hasShgTarget) this.shgTarget.value = ""
    if (this.hasMemberTarget) this.memberTarget.value = ""
    if (this.hasLoanTarget) this.loanTarget.value = ""
    this.filterAll()
    this.submitForm()
  }

  districtChanged() {
    if (this.hasBlockTarget) this.blockTarget.value = ""
    if (this.hasVillageTarget) this.villageTarget.value = ""
    if (this.hasShgTarget) this.shgTarget.value = ""
    if (this.hasMemberTarget) this.memberTarget.value = ""
    if (this.hasLoanTarget) this.loanTarget.value = ""
    this.filterAll()
    this.submitForm()
  }

  async blockChanged() {
    if (this.hasVillageTarget) this.villageTarget.value = ""
    if (this.hasShgTarget) this.shgTarget.value = ""
    if (this.hasMemberTarget) this.memberTarget.value = ""
    if (this.hasLoanTarget) this.loanTarget.value = ""
    if (this.remoteValue) {
      this.clearRemoteChildren()
      if (this.hasBlockTarget && this.blockTarget.value) {
        await this.loadRemoteVillages()
      }
      return
    }
    this.filterAfterBlock()
    this.submitForm()
  }

  async villageChanged() {
    if (this.hasShgTarget) this.shgTarget.value = ""
    if (this.hasMemberTarget) this.memberTarget.value = ""
    if (this.hasLoanTarget) this.loanTarget.value = ""
    if (this.remoteValue) {
      this.clearSelect(this.shgTarget, "Select SHG")
      if (this.hasMemberTarget) this.clearSelect(this.memberTarget, "Select member")
      if (this.hasVillageTarget && this.villageTarget.value) await this.loadRemoteShgs()
      return
    }
    this.filterAfterVillage()
    this.submitForm()
  }

  userChanged() {
    if (this.hasShgTarget) this.shgTarget.value = ""
    if (this.hasMemberTarget) this.memberTarget.value = ""
    if (this.hasLoanTarget) this.loanTarget.value = ""
    this.filterAll()
    this.submitForm()
  }

  shgChanged() {
    if (this.hasMemberTarget) this.memberTarget.value = ""
    if (this.hasLoanTarget) this.loanTarget.value = ""
    if (this.remoteValue) {
      if (this.hasMemberTarget) this.clearSelect(this.memberTarget, "Select member")
      if (this.hasMemberTarget && this.shgTarget.value) this.loadRemoteMembers()
      return
    }
    this.filterAfterShg()
    this.submitForm()
  }

  memberChanged() {
    if (this.hasLoanTarget) this.loanTarget.value = ""
    this.filterAfterMember()
    this.submitForm()
  }

  filterChanged() {
    this.filterAll()
  }

  filterAfterBlock() {
    if (this.hasVillageTarget && this.hasBlockTarget) {
      this.filterSelect(this.villageTarget, this.villageOptions, "blockId", this.blockTarget.value)
    }
    this.filterDependentLocationOptions()
  }

  filterAfterVillage() {
    this.filterDependentLocationOptions()
  }

  filterAfterShg() {
    if (this.hasMemberTarget) this.filterMemberSelect()
    if (this.hasLoanTarget) this.filterLoanSelect()
  }

  filterAfterMember() {
    if (this.hasLoanTarget) this.filterLoanSelect()
  }

  filterDependentLocationOptions() {
    if (this.hasCrpTarget) this.filterUserSelect(this.crpTarget, this.crpOptions)
    if (this.hasDcTarget) this.filterUserSelect(this.dcTarget, this.dcOptions)
    if (this.hasShgTarget) this.filterShgSelect()
    if (this.hasMemberTarget) this.filterMemberSelect()
    if (this.hasLoanTarget) this.filterLoanSelect()
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
      if (option.value === "" || !parentValue || this.dataValue(option, parentKey) === parentValue) {
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

  filterShgSelect() {
    if (!this.hasShgTarget) return

    this.filterSelectByPredicate(this.shgTarget, this.shgOptions, (option) => (
      this.optionMatchesSelectedLocation(option) && this.optionMatchesSelectedUser(option)
    ))
  }

  filterMemberSelect() {
    if (!this.hasMemberTarget) return

    this.filterSelectByPredicate(this.memberTarget, this.memberOptions, (option) => (
      this.optionMatchesSelectedLocation(option) &&
        this.optionMatchesSelectedUser(option) &&
        (!this.hasShgTarget || !this.shgTarget.value || this.dataValue(option, "shgId") === this.shgTarget.value)
    ))
  }

  filterLoanSelect() {
    if (!this.hasLoanTarget) return

    this.filterSelectByPredicate(this.loanTarget, this.loanOptions, (option) => (
      this.optionMatchesSelectedLocation(option) &&
        this.optionMatchesSelectedUser(option) &&
        (!this.hasShgTarget || !this.shgTarget.value || this.dataValue(option, "shgId") === this.shgTarget.value) &&
        (!this.hasMemberTarget || !this.memberTarget.value || this.dataValue(option, "memberId") === this.memberTarget.value)
    ))
  }

  filterSelectByPredicate(select, originalOptions, predicate) {
    if (!select.options) return

    const selectedValue = select.value
    select.innerHTML = ""

    originalOptions.forEach((option) => {
      if (option.value === "" || predicate(option)) {
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
    } else {
      select.value = ""
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
      stateId: (this.hasStateTarget && this.stateTarget.value) || this.dataValue(districtOption, "stateId") || this.dataValue(blockOption, "stateId") || this.dataValue(villageOption, "stateId") || "",
      districtId: (this.hasDistrictTarget && this.districtTarget.value) || this.dataValue(blockOption, "districtId") || this.dataValue(villageOption, "districtId") || "",
      blockId: (this.hasBlockTarget && this.blockTarget.value) || this.dataValue(villageOption, "blockId") || "",
      villageId: this.hasVillageTarget ? this.villageTarget.value : ""
    }
  }

  selectedOption(select) {
    if (!select || !select.value) return null
    return select.selectedOptions[0]
  }

  optionMatchesSelectedLocation(option) {
    const selected = this.selectedLocation()

    if (selected.villageId) return this.dataValue(option, "villageId") === selected.villageId
    if (selected.blockId) return this.dataValue(option, "blockId") === selected.blockId
    if (selected.districtId) return this.dataValue(option, "districtId") === selected.districtId
    if (selected.stateId) return this.dataValue(option, "stateId") === selected.stateId
    return true
  }

  optionMatchesSelectedUser(option) {
    if (!this.hasCrpTarget || !this.crpTarget.value) return true

    return this.optionIdSet(this.dataValue(option, "userIds")).has(this.crpTarget.value)
  }

  optionIdSet(ids) {
    return new Set((ids || "").split(" ").filter(Boolean))
  }

  dataValue(option, key) {
    if (!option) return ""

    const datasetValue = option.dataset[key]
    if (datasetValue !== undefined) return datasetValue

    const dashedKey = key.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`)
    return option.getAttribute(`data-${dashedKey}`) || ""
  }

  async refreshRemoteOptions() {
    if (!this.hasBlockTarget || !this.blockTarget.value) {
      this.clearRemoteChildren()
      return
    }

    await this.loadRemoteVillages()
    if (!this.hasVillageTarget || this.villageTarget.value) await this.loadRemoteShgs()
    if (this.hasMemberTarget && this.hasShgTarget && this.shgTarget.value) await this.loadRemoteMembers()
  }

  clearRemoteChildren() {
    if (this.hasVillageTarget) this.clearSelect(this.villageTarget, "Select village")
    if (this.hasShgTarget) this.clearSelect(this.shgTarget, "Select SHG")
    if (this.hasMemberTarget) this.clearSelect(this.memberTarget, "Select member")
  }

  async loadRemoteVillages() {
    if (!this.hasVillageTarget) return

    const options = await this.fetchRemoteOptions("/location_options/villages", { block_id: this.blockTarget.value })
    this.replaceRemoteOptions(this.villageTarget, options, "Select village")
  }

  async loadRemoteShgs() {
    if (!this.hasShgTarget) return
    if (this.hasVillageTarget && !this.villageTarget.value) {
      this.clearSelect(this.shgTarget, "Select SHG")
      return
    }

    const options = await this.fetchRemoteOptions("/location_options/shgs", {
      block_id: this.hasBlockTarget ? this.blockTarget.value : "",
      village_id: this.hasVillageTarget ? this.villageTarget.value : ""
    })
    this.replaceRemoteOptions(this.shgTarget, options, "Select SHG")
  }

  async loadRemoteMembers() {
    if (!this.hasMemberTarget) return

    const options = await this.fetchRemoteOptions("/location_options/members", {
      block_id: this.hasBlockTarget ? this.blockTarget.value : "",
      village_id: this.hasVillageTarget ? this.villageTarget.value : "",
      shg_id: this.hasShgTarget ? this.shgTarget.value : ""
    })
    this.replaceRemoteOptions(this.memberTarget, options, "Select member")
  }

  async fetchRemoteOptions(path, params) {
    const query = new URLSearchParams()
    Object.entries(params).forEach(([key, value]) => {
      if (value) query.set(key, value)
    })

    const response = await fetch(`${path}?${query.toString()}`, { headers: { Accept: "application/json" } })
    if (!response.ok) return []

    return response.json()
  }

  replaceRemoteOptions(select, options, prompt) {
    const selectedValue = select.value
    select.innerHTML = ""
    select.appendChild(new Option(prompt, ""))

    options.forEach((option) => {
      const element = new Option(option.text, option.id)
      Object.entries(option).forEach(([key, value]) => {
        if (key !== "id" && key !== "text" && value !== null && value !== undefined) {
          element.dataset[this.camelize(key)] = value
        }
      })
      select.appendChild(element)
    })

    select.value = Array.from(select.options).some((option) => option.value === selectedValue) ? selectedValue : ""
    this.refreshSearchableSelect(select)
  }

  clearSelect(select, prompt) {
    if (!select) return

    select.innerHTML = ""
    select.appendChild(new Option(prompt, ""))
    select.value = ""
    this.refreshSearchableSelect(select)
  }

  camelize(value) {
    return value.replace(/_([a-z])/g, (_, letter) => letter.toUpperCase())
  }

  refreshSearchableSelect(select) {
    select.dispatchEvent(new CustomEvent("searchable-select:refresh"))
  }

  submitForm() {
    if (!this.autoSubmitValue || this.submitting) return

    this.submitting = true
    window.requestAnimationFrame(() => {
      const params = new URLSearchParams(new FormData(this.element))
      params.delete("commit")
      params.delete("q")
      params.delete("page")
      params.set("refresh_filters", "1")
      window.location.href = `${this.element.action}?${params.toString()}`
    })
  }
}

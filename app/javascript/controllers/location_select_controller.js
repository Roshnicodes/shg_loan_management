import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["state", "district", "block", "village", "shg", "member", "loan", "crp", "dc"]
  static values = { autoSubmit: Boolean, remote: Boolean, remoteShgs: Boolean, includeInactiveShgs: Boolean, strict: Boolean, filterRemote: Boolean }

  connect() {
    this.stateOptions = this.hasStateTarget ? this.cloneOptions(this.stateTarget) : []
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
    this.scheduleRestoredValueFilter()
  }

  scheduleRestoredValueFilter() {
    ;[0, 150, 500].forEach((delay) => {
      window.setTimeout(() => this.filterAll(), delay)
    })
  }

  filterAll() {
    if (this.filterRemoteValue && this.hasStateTarget) this.restoreSelect(this.stateTarget, this.stateOptions)

    if (this.hasDistrictTarget && this.hasStateTarget) {
      this.filterSelect(this.districtTarget, this.districtOptions, "stateId", this.selectedValues(this.stateTarget))
    }

    if (this.hasBlockTarget) {
      if (this.hasDistrictTarget) {
        this.filterSelect(this.blockTarget, this.blockOptions, "districtId", this.selectedValues(this.districtTarget))
      } else if (this.hasStateTarget) {
        this.filterSelect(this.blockTarget, this.blockOptions, "stateId", this.selectedValues(this.stateTarget))
      }
    }

    if (this.hasVillageTarget && this.hasBlockTarget) {
      this.filterSelect(this.villageTarget, this.villageOptions, "blockId", this.selectedValues(this.blockTarget))
    }

    if (this.hasCrpTarget) this.filterUserSelect(this.crpTarget, this.crpOptions)
    if (this.hasDcTarget) this.filterUserSelect(this.dcTarget, this.dcOptions)

    if (this.hasShgTarget) this.filterShgSelect()
    if (this.hasMemberTarget) this.filterMemberSelect()
    if (this.hasLoanTarget) this.filterLoanSelect()
  }

  async stateChanged() {
    if (this.hasDistrictTarget) this.clearValue(this.districtTarget)
    if (this.hasBlockTarget) this.clearValue(this.blockTarget)
    if (this.hasVillageTarget) this.clearValue(this.villageTarget)
    if (this.hasShgTarget) this.clearValue(this.shgTarget)
    if (this.hasMemberTarget) this.clearValue(this.memberTarget)
    if (this.hasLoanTarget) this.clearValue(this.loanTarget)
    if (this.filterRemoteValue) await this.refreshFilterOptions()
    this.filterAll()
    this.submitForm()
  }

  async districtChanged() {
    if (this.hasBlockTarget) this.clearValue(this.blockTarget)
    if (this.hasVillageTarget) this.clearValue(this.villageTarget)
    if (this.hasShgTarget) this.clearValue(this.shgTarget)
    if (this.hasMemberTarget) this.clearValue(this.memberTarget)
    if (this.hasLoanTarget) this.clearValue(this.loanTarget)
    if (this.filterRemoteValue) await this.refreshFilterOptions()
    this.filterAll()
    this.submitForm()
  }

  async blockChanged() {
    if (this.hasVillageTarget) this.clearValue(this.villageTarget)
    if (this.hasShgTarget) this.clearValue(this.shgTarget)
    if (this.hasMemberTarget) this.clearValue(this.memberTarget)
    if (this.hasLoanTarget) this.clearValue(this.loanTarget)
    if (this.remoteValue) {
      this.clearRemoteChildren()
      if (this.hasBlockTarget && this.blockTarget.value) {
        await this.loadRemoteVillages()
      }
      return
    }
    if (this.filterRemoteValue) await this.refreshFilterOptions()
    this.filterAfterBlock()
    this.submitForm()
  }

  async villageChanged() {
    if (this.hasShgTarget) this.clearValue(this.shgTarget)
    if (this.hasMemberTarget) this.clearValue(this.memberTarget)
    if (this.hasLoanTarget) this.clearValue(this.loanTarget)
    if (this.remoteValue) {
      if (this.hasShgTarget) this.clearSelect(this.shgTarget, "Select SHG")
      if (this.hasMemberTarget) this.clearSelect(this.memberTarget, "Select member")
      if (this.hasVillageTarget && this.selectedValues(this.villageTarget).length > 0) await this.loadRemoteShgs()
      return
    }
    if (this.filterRemoteValue) {
      await this.refreshFilterOptions()
      this.filterAfterVillage()
      this.submitForm()
      return
    }
    if (this.remoteShgsValue) {
      if (this.hasShgTarget) this.clearSelect(this.shgTarget, "Select SHG")
      if (this.hasVillageTarget && this.selectedValues(this.villageTarget).length > 0) {
        await this.loadRemoteShgs()
        this.filterRemoteShgDependents()
      } else {
        this.filterAfterVillage()
      }
      return
    }
    this.filterAfterVillage()
    this.submitForm()
  }

  async userChanged() {
    if (this.hasShgTarget) this.clearValue(this.shgTarget)
    if (this.hasMemberTarget) this.clearValue(this.memberTarget)
    if (this.hasLoanTarget) this.clearValue(this.loanTarget)
    if (this.filterRemoteValue) await this.refreshFilterOptions()
    this.filterAll()
    this.submitForm()
  }

  async shgChanged() {
    if (this.hasMemberTarget) this.clearValue(this.memberTarget)
    if (this.hasLoanTarget) this.clearValue(this.loanTarget)
    if (this.remoteValue) {
      if (this.hasMemberTarget) this.clearSelect(this.memberTarget, "Select member")
      if (this.hasMemberTarget && this.shgTarget.value) this.loadRemoteMembers()
      return
    }
    if (this.filterRemoteValue) {
      await this.refreshFilterOptions()
      this.filterAll()
      this.submitForm()
      return
    }
    this.filterAfterShg()
    this.submitForm()
  }

  memberChanged() {
    if (this.hasLoanTarget) this.clearValue(this.loanTarget)
    this.filterAfterMember()
    this.submitForm()
  }

  filterChanged() {
    this.filterAll()
  }

  filterAfterBlock() {
    if (this.hasVillageTarget && this.hasBlockTarget) {
      this.filterSelect(this.villageTarget, this.villageOptions, "blockId", this.selectedValues(this.blockTarget))
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

  filterRemoteShgDependents() {
    if (this.hasCrpTarget) this.filterUserSelect(this.crpTarget, this.crpOptions)
    if (this.hasDcTarget) this.filterUserSelect(this.dcTarget, this.dcOptions)
    if (this.hasMemberTarget) this.filterMemberSelect()
    if (this.hasLoanTarget) this.filterLoanSelect()
  }

  cloneOptions(select) {
    if (!select.options) return []

    return Array.from(select.options).map((option) => option.cloneNode(true))
  }

  filterSelect(select, originalOptions, parentKey, parentValues) {
    if (!select.options) return

    const selectedValues = this.selectedValues(select)
    const parentValueList = Array.isArray(parentValues) ? parentValues : [parentValues].filter(Boolean)
    select.innerHTML = ""

    originalOptions.forEach((option) => {
      if (option.value === "" || (!this.strictValue && parentValueList.length === 0) || parentValueList.includes(this.dataValue(option, parentKey))) {
        select.appendChild(option.cloneNode(true))
      }
    })

    this.restoreSelectedValues(select, selectedValues)

    this.refreshSearchableSelect(select)
  }

  restoreSelect(select, originalOptions) {
    if (!select.options) return

    const selectedValues = this.selectedValues(select)
    select.innerHTML = ""
    originalOptions.forEach((option) => select.appendChild(option.cloneNode(true)))

    this.restoreSelectedValues(select, selectedValues)

    this.refreshSearchableSelect(select)
  }

  filterShgSelect() {
    if (!this.hasShgTarget) return
    if (this.strictValue && this.hasVillageTarget && this.selectedValues(this.villageTarget).length === 0) {
      this.filterSelectByPredicate(this.shgTarget, this.shgOptions, () => false)
      return
    }

    this.filterSelectByPredicate(this.shgTarget, this.shgOptions, (option) => (
      this.optionMatchesSelectedLocation(option) && this.optionMatchesSelectedUser(option)
    ))
  }

  filterMemberSelect() {
    if (!this.hasMemberTarget) return
    if (this.strictValue && this.hasShgTarget && this.selectedValues(this.shgTarget).length === 0) {
      this.filterSelectByPredicate(this.memberTarget, this.memberOptions, () => false)
      return
    }

    this.filterSelectByPredicate(this.memberTarget, this.memberOptions, (option) => (
      this.optionMatchesSelectedLocation(option) &&
        this.optionMatchesSelectedUser(option) &&
        (!this.hasShgTarget || this.selectedValues(this.shgTarget).length === 0 || this.selectedValues(this.shgTarget).includes(this.dataValue(option, "shgId")))
    ))
  }

  filterLoanSelect() {
    if (!this.hasLoanTarget) return
    if (this.strictValue && this.hasMemberTarget && this.selectedValues(this.memberTarget).length === 0) {
      this.filterSelectByPredicate(this.loanTarget, this.loanOptions, () => false)
      return
    }

    this.filterSelectByPredicate(this.loanTarget, this.loanOptions, (option) => (
      this.optionMatchesSelectedLocation(option) &&
        this.optionMatchesSelectedUser(option) &&
        (!this.hasShgTarget || this.selectedValues(this.shgTarget).length === 0 || this.selectedValues(this.shgTarget).includes(this.dataValue(option, "shgId"))) &&
        (!this.hasMemberTarget || this.selectedValues(this.memberTarget).length === 0 || this.selectedValues(this.memberTarget).includes(this.dataValue(option, "memberId")))
    ))
  }

  filterSelectByPredicate(select, originalOptions, predicate) {
    if (!select.options) return

    const selectedValues = this.selectedValues(select)
    select.innerHTML = ""

    originalOptions.forEach((option) => {
      if (option.value === "" || predicate(option)) {
        select.appendChild(option.cloneNode(true))
      }
    })

    this.restoreSelectedValues(select, selectedValues)

    this.refreshSearchableSelect(select)
  }

  filterUserSelect(select, originalOptions) {
    if (!select) return

    const selectedValues = this.selectedValues(select)
    select.innerHTML = ""

    // A chosen user stays chosen even when the location filters narrow the list.
    originalOptions.forEach((option) => {
      if (option.value === "" || (this.filterRemoteValue && selectedValues.includes(option.value)) || this.optionMatchesLocation(option)) {
        select.appendChild(option.cloneNode(true))
      }
    })

    this.restoreSelectedValues(select, selectedValues)

    this.refreshSearchableSelect(select)
  }

  optionMatchesLocation(option) {
    const selected = this.selectedLocation()
    const stateIds = this.optionIdSet(option.dataset.stateIds)
    const districtIds = this.optionIdSet(option.dataset.districtIds)
    const blockIds = this.optionIdSet(option.dataset.blockIds)
    const villageIds = this.optionIdSet(option.dataset.villageIds)

    if (selected.villageIds.length > 0) {
      return this.intersects(stateIds, selected.stateIds) ||
        this.intersects(districtIds, selected.districtIds) ||
        this.intersects(blockIds, selected.blockIds) ||
        this.intersects(villageIds, selected.villageIds)
    }

    if (selected.blockIds.length > 0) {
      return this.intersects(stateIds, selected.stateIds) ||
        this.intersects(districtIds, selected.districtIds) ||
        this.intersects(blockIds, selected.blockIds)
    }

    if (selected.districtIds.length > 0) {
      return this.intersects(stateIds, selected.stateIds) ||
        this.intersects(districtIds, selected.districtIds)
    }

    if (selected.stateIds.length > 0) return this.intersects(stateIds, selected.stateIds)
    return true
  }

  selectedLocation() {
    const districtOptions = this.selectedOptions(this.hasDistrictTarget ? this.districtTarget : null)
    const blockOptions = this.selectedOptions(this.hasBlockTarget ? this.blockTarget : null)
    const villageOptions = this.selectedOptions(this.hasVillageTarget ? this.villageTarget : null)

    return {
      stateIds: this.uniqueValues([
        ...this.selectedValues(this.hasStateTarget ? this.stateTarget : null),
        ...this.dataValues(districtOptions, "stateId"),
        ...this.dataValues(blockOptions, "stateId"),
        ...this.dataValues(villageOptions, "stateId")
      ]),
      districtIds: this.uniqueValues([
        ...this.selectedValues(this.hasDistrictTarget ? this.districtTarget : null),
        ...this.dataValues(blockOptions, "districtId"),
        ...this.dataValues(villageOptions, "districtId")
      ]),
      blockIds: this.uniqueValues([
        ...this.selectedValues(this.hasBlockTarget ? this.blockTarget : null),
        ...this.dataValues(villageOptions, "blockId")
      ]),
      villageIds: this.selectedValues(this.hasVillageTarget ? this.villageTarget : null)
    }
  }

  selectedOptions(select) {
    if (!select) return []
    return Array.from(select.selectedOptions).filter((option) => option.value !== "")
  }

  optionMatchesSelectedLocation(option) {
    const selected = this.selectedLocation()

    if (selected.villageIds.length > 0) return selected.villageIds.includes(this.dataValue(option, "villageId"))
    if (selected.blockIds.length > 0) return selected.blockIds.includes(this.dataValue(option, "blockId"))
    if (selected.districtIds.length > 0) return selected.districtIds.includes(this.dataValue(option, "districtId"))
    if (selected.stateIds.length > 0) return selected.stateIds.includes(this.dataValue(option, "stateId"))
    return true
  }

  optionMatchesSelectedUser(option) {
    const selectedUserIds = this.selectedValues(this.hasCrpTarget ? this.crpTarget : null)
    if (selectedUserIds.length === 0) return true
    // Options without user data (index-page filters) are narrowed by the server instead.
    if (!option.hasAttribute("data-user-ids")) return true

    return this.intersects(this.optionIdSet(this.dataValue(option, "userIds")), selectedUserIds)
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

  selectedValues(select) {
    if (!select) return []
    if (!select.selectedOptions) return [select.value].filter(Boolean)

    return Array.from(select.selectedOptions || []).map((option) => option.value).filter(Boolean)
  }

  restoreSelectedValues(select, selectedValues) {
    const availableValues = new Set(Array.from(select.options).map((option) => option.value))
    if (select.multiple) {
      Array.from(select.options).forEach((option) => {
        option.selected = selectedValues.includes(option.value) && availableValues.has(option.value)
      })
    } else {
      const selectedValue = selectedValues.find((value) => availableValues.has(value))
      select.value = selectedValue || ""
    }
  }

  clearValue(select) {
    if (!select) return

    if (select.multiple) {
      Array.from(select.options || []).forEach((option) => {
        option.selected = false
      })
    } else {
      select.value = ""
    }
    this.refreshSearchableSelect(select)
  }

  dataValues(options, key) {
    return options.map((option) => this.dataValue(option, key)).filter(Boolean)
  }

  uniqueValues(values) {
    return Array.from(new Set(values.filter(Boolean)))
  }

  intersects(setOrValues, values) {
    const set = setOrValues instanceof Set ? setOrValues : new Set(setOrValues)
    return values.some((value) => set.has(value))
  }

  async refreshRemoteOptions() {
    if (!this.hasBlockTarget || !this.blockTarget.value) {
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
    if (!options) return
    if (options.length === 0 && this.localOptionExists(this.villageOptions, (option) => (
      this.selectedValues(this.blockTarget).includes(this.dataValue(option, "blockId"))
    ))) {
      this.filterAfterBlock()
      return
    }

    this.replaceRemoteOptions(this.villageTarget, options, "Select village")
  }

  async loadRemoteShgs() {
    if (!this.hasShgTarget) return
    const villageIds = this.hasVillageTarget ? this.selectedValues(this.villageTarget) : []
    if (this.hasVillageTarget && villageIds.length === 0) {
      this.clearSelect(this.shgTarget, "Select SHG")
      return
    }

    const options = await this.fetchRemoteOptions("/location_options/shgs", {
      block_id: this.hasBlockTarget ? this.selectedValues(this.blockTarget) : [],
      village_id: villageIds,
      include_inactive: this.includeInactiveShgsValue ? "1" : ""
    })
    if (!options) return
    if (options.length === 0 && this.localOptionExists(this.shgOptions, (option) => (
      this.optionMatchesSelectedLocation(option)
    ))) {
      this.filterShgSelect()
      return
    }

    this.replaceRemoteOptions(this.shgTarget, options, "Select SHG")
  }

  async loadRemoteMembers() {
    if (!this.hasMemberTarget) return

    const options = await this.fetchRemoteOptions("/location_options/members", {
      block_id: this.hasBlockTarget ? this.blockTarget.value : "",
      village_id: this.hasVillageTarget ? this.villageTarget.value : "",
      shg_id: this.hasShgTarget ? this.shgTarget.value : ""
    })
    if (!options) return
    if (options.length === 0 && this.localOptionExists(this.memberOptions, (option) => (
      this.optionMatchesSelectedLocation(option) &&
        this.selectedValues(this.shgTarget).includes(this.dataValue(option, "shgId"))
    ))) {
      this.filterMemberSelect()
      return
    }

    this.replaceRemoteOptions(this.memberTarget, options, "Select member")
  }

  // Reloads the District/Block/Village/SHG option lists for the current location
  // selection, so child filters work before the form is applied.
  async refreshFilterOptions() {
    const requestId = (this.filterRequestId || 0) + 1
    this.filterRequestId = requestId

    const data = await this.fetchRemoteOptions("/location_options/filters", {
      state_id: this.selectedValues(this.hasStateTarget ? this.stateTarget : null),
      district_id: this.selectedValues(this.hasDistrictTarget ? this.districtTarget : null),
      block_id: this.selectedValues(this.hasBlockTarget ? this.blockTarget : null),
      village_id: this.selectedValues(this.hasVillageTarget ? this.villageTarget : null),
      crp_id: this.selectedValues(this.hasCrpTarget ? this.crpTarget : null),
      shg_id: this.selectedValues(this.hasShgTarget ? this.shgTarget : null)
    })
    if (!data || requestId !== this.filterRequestId) return

    if (this.hasStateTarget && data.states) this.stateOptions = this.buildOptions(data.states)
    if (this.hasDistrictTarget && data.districts) this.districtOptions = this.buildOptions(data.districts)
    if (this.hasBlockTarget && data.blocks) this.blockOptions = this.buildOptions(data.blocks)
    if (this.hasVillageTarget && data.villages) this.villageOptions = this.buildOptions(data.villages)
    if (this.hasShgTarget && data.shgs) this.shgOptions = this.buildOptions(data.shgs)
  }

  buildOptions(options) {
    return options.map((option) => {
      const element = new Option(option.text, option.id)
      Object.entries(option).forEach(([key, value]) => {
        if (key !== "id" && key !== "text" && value !== null && value !== undefined) {
          element.dataset[this.camelize(key)] = value
        }
      })
      return element
    })
  }

  localOptionExists(options, predicate) {
    return options.some((option) => option.value !== "" && predicate(option))
  }

  async fetchRemoteOptions(path, params) {
    try {
      const query = new URLSearchParams()
      Object.entries(params).forEach(([key, value]) => {
        if (Array.isArray(value)) {
          value.filter(Boolean).forEach((item) => query.append(`${key}[]`, item))
        } else if (value) {
          query.set(key, value)
        }
      })

      const response = await fetch(`${path}?${query.toString()}`, { headers: { Accept: "application/json" } })
      if (!response.ok) return null

      return response.json()
    } catch (_error) {
      return null
    }
  }

  replaceRemoteOptions(select, options, prompt) {
    const selectedValues = this.selectedValues(select)
    select.innerHTML = ""
    select.appendChild(new Option(prompt, ""))
    this.buildOptions(options).forEach((element) => select.appendChild(element))

    this.restoreSelectedValues(select, selectedValues)
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

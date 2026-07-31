import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["block", "village", "shg", "member", "product"]

  connect() {
    this.villageOptions = this.cloneOptions(this.villageTarget)
    this.shgOptions = this.cloneOptions(this.shgTarget)
    this.memberOptions = this.cloneOptions(this.memberTarget)
    this.filterAll()
  }

  blockChanged() {
    this.villageTarget.value = ""
    this.shgTarget.value = ""
    this.memberTarget.value = ""
    this.clearProduct()
    this.filterAll()
  }

  villageChanged() {
    this.syncBlockFromVillage()
    this.shgTarget.value = ""
    this.memberTarget.value = ""
    this.clearProduct()
    this.filterAll()
  }

  shgChanged() {
    this.memberTarget.value = ""
    this.clearProduct()
    this.filterAll()
  }

  memberChanged() {
    this.mapProductFromMember(true)
    this.filterAll()
  }

  filterAll() {
    if (!this.filterSelect(this.villageTarget, this.villageOptions, "blockId", this.blockTarget.value)) {
      this.shgTarget.value = ""
      this.memberTarget.value = ""
      this.clearProduct()
    }

    if (!this.filterShgs()) {
      this.memberTarget.value = ""
      this.clearProduct()
    }

    if (!this.filterSelect(this.memberTarget, this.memberOptions, "shgId", this.shgTarget.value)) {
      this.clearProduct()
    }

    this.mapProductFromMember()
    this.updateDependentStates()
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
      this.refreshSearchableSelect(select)
      return true
    } else {
      select.value = ""
      this.refreshSearchableSelect(select)
      return false
    }
  }

  filterShgs() {
    const selectedValue = this.shgTarget.value
    const villageId = this.villageTarget.value

    this.shgTarget.innerHTML = ""
    this.shgOptions.forEach((option) => {
      if (
        option.value === "" ||
        (villageId && option.dataset.villageId === villageId)
      ) {
        this.shgTarget.appendChild(option.cloneNode(true))
      }
    })

    if (Array.from(this.shgTarget.options).some((option) => option.value === selectedValue)) {
      this.shgTarget.value = selectedValue
      this.refreshSearchableSelect(this.shgTarget)
      return true
    } else {
      this.shgTarget.value = ""
      this.refreshSearchableSelect(this.shgTarget)
      return false
    }
  }

  syncBlockFromVillage() {
    if (!this.villageTarget.value) return

    const selectedVillage = this.villageTarget.selectedOptions[0]
    const blockId = selectedVillage?.dataset.blockId
    if (blockId && this.blockTarget.value !== blockId) {
      this.blockTarget.value = blockId
      this.refreshSearchableSelect(this.blockTarget)
    }
  }

  mapProductFromMember(force = false) {
    if (!this.hasProductTarget) return
    if (!this.memberTarget.value) {
      this.clearProduct()
      return
    }
    if (!force && this.productTarget.value) return

    const productId = this.memberTarget.selectedOptions[0]?.dataset.productId
    if (productId && Array.from(this.productTarget.options).some((option) => option.value === productId)) {
      this.productTarget.value = productId
      this.productTarget.dispatchEvent(new Event("change", { bubbles: true }))
      this.refreshSearchableSelect(this.productTarget)
    } else if (force) {
      this.clearProduct()
    }
  }

  clearProduct() {
    if (!this.hasProductTarget) return

    this.productTarget.value = ""
    this.productTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.refreshSearchableSelect(this.productTarget)
  }

  updateDependentStates() {
    this.villageTarget.disabled = !this.blockTarget.value
    this.shgTarget.disabled = !this.villageTarget.value
    this.memberTarget.disabled = !this.shgTarget.value

    this.refreshSearchableSelect(this.villageTarget)
    this.refreshSearchableSelect(this.shgTarget)
    this.refreshSearchableSelect(this.memberTarget)
  }

  refreshSearchableSelect(select) {
    select.dispatchEvent(new CustomEvent("searchable-select:refresh"))
  }
}

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
    this.filterAll()
  }

  villageChanged() {
    this.syncBlockFromVillage()
    this.shgTarget.value = ""
    this.memberTarget.value = ""
    this.filterAll()
  }

  shgChanged() {
    this.memberTarget.value = ""
    this.filterAll()
  }

  memberChanged() {
    this.mapProductFromMember(true)
    this.filterAll()
  }

  filterAll() {
    this.filterSelect(this.villageTarget, this.villageOptions, "blockId", this.blockTarget.value)
    this.filterShgs()
    this.filterSelect(this.memberTarget, this.memberOptions, "shgId", this.shgTarget.value)
    this.mapProductFromMember()
  }

  cloneOptions(select) {
    return Array.from(select.options).map((option) => option.cloneNode(true))
  }

  filterSelect(select, originalOptions, parentKey, parentValue) {
    const selectedValue = select.value
    select.innerHTML = ""

    originalOptions.forEach((option) => {
      if (option.value === "" || !parentValue || option.dataset[parentKey] === parentValue) {
        select.appendChild(option.cloneNode(true))
      }
    })

    if (Array.from(select.options).some((option) => option.value === selectedValue)) {
      select.value = selectedValue
    }

    this.refreshSearchableSelect(select)
  }

  filterShgs() {
    const selectedValue = this.shgTarget.value
    const blockId = this.blockTarget.value
    const villageId = this.villageTarget.value

    this.shgTarget.innerHTML = ""
    this.shgOptions.forEach((option) => {
      if (
        option.value === "" ||
        ((blockId === "" || option.dataset.blockId === blockId) &&
          (villageId === "" || option.dataset.villageId === villageId))
      ) {
        this.shgTarget.appendChild(option.cloneNode(true))
      }
    })

    if (Array.from(this.shgTarget.options).some((option) => option.value === selectedValue)) {
      this.shgTarget.value = selectedValue
    }

    this.refreshSearchableSelect(this.shgTarget)
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
    if (!this.hasProductTarget || !this.memberTarget.value) return
    if (!force && this.productTarget.value) return

    const productId = this.memberTarget.selectedOptions[0]?.dataset.productId
    if (productId && Array.from(this.productTarget.options).some((option) => option.value === productId)) {
      this.productTarget.value = productId
      this.refreshSearchableSelect(this.productTarget)
    }
  }

  refreshSearchableSelect(select) {
    select.dispatchEvent(new CustomEvent("searchable-select:refresh"))
  }
}

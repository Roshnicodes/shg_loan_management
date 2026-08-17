import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "block", "village", "shg", "member", "group", "gender", "dob", "address",
    "distributionDate", "termType", "term", "principal", "interestPercent",
    "principalOut", "interestOut", "totalOut", "paidOut", "remainingOut",
    "emiOut", "scheduleLabel", "scheduleOut"
  ]

  static values = {
    paid: Number
  }

  connect() {
    this.villageOptions = this.hasVillageTarget ? this.cloneOptions(this.villageTarget) : []
    this.shgOptions = this.cloneOptions(this.shgTarget)
    this.memberOptions = Array.from(this.memberTarget.options).map((option) => option.cloneNode(true))
    this.filterLocation()
    this.refreshRemoteOptions()
    this.update()
    this.calculate()
  }

  blockChanged() {
    if (this.hasVillageTarget) this.villageTarget.value = ""
    this.shgTarget.value = ""
    this.memberTarget.value = ""
    this.clearSelect(this.villageTarget, "Select village")
    this.clearSelect(this.shgTarget, "Select SHG")
    this.clearSelect(this.memberTarget, "Select member")
    if (this.hasBlockTarget && this.blockTarget.value) {
      this.loadRemoteVillages()
      this.loadRemoteShgs()
    }
    this.update()
  }

  villageChanged() {
    this.shgTarget.value = ""
    this.memberTarget.value = ""
    this.clearSelect(this.shgTarget, "Select SHG")
    this.clearSelect(this.memberTarget, "Select member")
    if (this.hasVillageTarget && this.villageTarget.value) this.loadRemoteShgs()
    this.update()
  }

  shgChanged() {
    this.memberTarget.value = ""
    this.clearSelect(this.memberTarget, "Select member")
    if (this.shgTarget.value) this.loadRemoteMembers()
    this.update()
  }

  memberChanged() {
    this.update()
  }

  filterLocation() {
    this.filterVillages()
    this.filterShgs()
    this.filterMembers()
  }

  filterChildrenFrom(parent) {
    if (parent === "block") this.filterVillages()
    this.filterShgs()
    this.filterMembers()
  }

  filterVillages() {
    if (!this.hasVillageTarget) return

    const selectedBlockId = this.hasBlockTarget ? this.blockTarget.value : ""
    this.replaceOptions(this.villageTarget, this.villageOptions, (option) => (
      !selectedBlockId || this.dataValue(option, "blockId") === selectedBlockId
    ))
  }

  filterShgs() {
    const selectedBlockId = this.hasBlockTarget ? this.blockTarget.value : ""
    const selectedVillageId = this.hasVillageTarget ? this.villageTarget.value : ""

    this.replaceOptions(this.shgTarget, this.shgOptions, (option) => {
      const matchesBlock = !selectedBlockId || this.dataValue(option, "blockId") === selectedBlockId
      const matchesVillage = !selectedVillageId || this.dataValue(option, "villageId") === selectedVillageId
      return matchesBlock && matchesVillage
    })
  }

  filterMembers() {
    const selectedBlockId = this.hasBlockTarget ? this.blockTarget.value : ""
    const selectedVillageId = this.hasVillageTarget ? this.villageTarget.value : ""
    const selectedShgId = this.shgTarget.value

    this.replaceOptions(this.memberTarget, this.memberOptions, (option) => {
      const matchesBlock = !selectedBlockId || this.dataValue(option, "blockId") === selectedBlockId
      const matchesVillage = !selectedVillageId || this.dataValue(option, "villageId") === selectedVillageId
      const matchesShg = !selectedShgId || this.dataValue(option, "shgId") === selectedShgId
      return matchesBlock && matchesVillage && matchesShg
    })
  }

  dataValue(option, key) {
    if (!option) return ""

    const datasetValue = option.dataset[key]
    if (datasetValue !== undefined) return datasetValue

    const dashedKey = key.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`)
    return option.getAttribute(`data-${dashedKey}`) || ""
  }

  cloneOptions(select) {
    return Array.from(select.options).map((option) => option.cloneNode(true))
  }

  replaceOptions(select, originalOptions, predicate) {
    const selectedValue = select.value
    select.innerHTML = ""

    originalOptions.forEach((option) => {
      if (option.value === "" || predicate(option)) select.appendChild(option.cloneNode(true))
    })

    if (Array.from(select.options).some((option) => option.value === selectedValue)) {
      select.value = selectedValue
    } else {
      select.value = ""
    }

    select.dispatchEvent(new CustomEvent("searchable-select:refresh"))
  }

  refreshRemoteOptions() {
    if (!this.hasBlockTarget || !this.blockTarget.value) {
      if (this.hasVillageTarget) this.clearSelect(this.villageTarget, "Select village")
      this.clearSelect(this.shgTarget, "Select SHG")
      this.clearSelect(this.memberTarget, "Select member")
      return
    }

    this.loadRemoteVillages()
    this.loadRemoteShgs()
    if (this.shgTarget.value) this.loadRemoteMembers()
  }

  async loadRemoteVillages() {
    if (!this.hasVillageTarget) return

    const options = await this.fetchRemoteOptions("/location_options/villages", { block_id: this.blockTarget.value })
    this.replaceRemoteOptions(this.villageTarget, options, "Select village")
  }

  async loadRemoteShgs() {
    const options = await this.fetchRemoteOptions("/location_options/shgs", {
      block_id: this.hasBlockTarget ? this.blockTarget.value : "",
      village_id: this.hasVillageTarget ? this.villageTarget.value : ""
    })
    this.replaceRemoteOptions(this.shgTarget, options, "Select SHG")
  }

  async loadRemoteMembers() {
    const options = await this.fetchRemoteOptions("/location_options/members", {
      block_id: this.hasBlockTarget ? this.blockTarget.value : "",
      village_id: this.hasVillageTarget ? this.villageTarget.value : "",
      shg_id: this.shgTarget.value
    })
    this.replaceRemoteOptions(this.memberTarget, options, "Select member")
    this.update()
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
    select.dispatchEvent(new CustomEvent("searchable-select:refresh"))
  }

  clearSelect(select, prompt) {
    if (!select) return

    select.innerHTML = ""
    select.appendChild(new Option(prompt, ""))
    select.value = ""
    select.dispatchEvent(new CustomEvent("searchable-select:refresh"))
  }

  camelize(value) {
    return value.replace(/_([a-z])/g, (_, letter) => letter.toUpperCase())
  }

  update() {
    const option = this.memberTarget.selectedOptions[0]
    const data = option?.dataset || {}

    this.groupTarget.value = data.group || ""
    this.genderTarget.value = data.gender || ""
    this.dobTarget.value = data.dob || ""
    this.addressTarget.value = data.address || ""
  }

  calculate() {
    const principal = this.numberValue(this.principalTarget?.value)
    const interestPercent = this.numberValue(this.interestPercentTarget?.value)
    const term = Math.max(parseInt(this.termTarget?.value || "0", 10), 0)
    const paid = this.paidValue || 0
    const termType = this.termTypeTarget?.value || "Monthly"
    const schedule = this.reducingBalanceSchedule(principal, interestPercent, term, termType)
    const interestAmount = schedule.reduce((sum, emi) => sum + emi.interestAmount, 0)
    const totalPayable = schedule.reduce((sum, emi) => sum + emi.dueAmount, 0)
    const remaining = Math.max(totalPayable - paid, 0)
    const emiAmount = term > 0 && schedule.length > 0 ? schedule[0].dueAmount : 0
    const principalEmi = term > 0 ? principal / term : 0

    this.principalOutTarget.textContent = this.currency(principal)
    this.interestOutTarget.textContent = `${this.currency(interestAmount)} (${this.percent(interestPercent)} per installment reducing)`
    this.totalOutTarget.textContent = this.currency(totalPayable)
    this.paidOutTarget.textContent = this.currency(paid)
    this.remainingOutTarget.textContent = this.currency(remaining)
    this.emiOutTarget.textContent = `${this.currency(emiAmount)} first EMI, principal ${this.currency(principalEmi)}`

    this.scheduleLabelTarget.textContent = `${termType || "Monthly"} EMI`
    this.scheduleOutTarget.textContent = this.scheduleText(term, termType, emiAmount, totalPayable)
  }

  reducingBalanceSchedule(principal, annualInterestPercent, term, termType) {
    if (principal <= 0 || term <= 0) return []

    const rate = annualInterestPercent / 100
    const principalEmi = principal / term
    let outstanding = principal

    return Array.from({ length: term }, (_, index) => {
      const interestAmount = outstanding * rate
      const principalAmount = index === term - 1 ? outstanding : Math.min(principalEmi, outstanding)
      const dueAmount = principalAmount + interestAmount
      outstanding = Math.max(outstanding - principalAmount, 0)

      return {
        principalAmount: this.roundMoney(principalAmount),
        interestAmount: this.roundMoney(interestAmount),
        dueAmount: this.roundMoney(dueAmount)
      }
    })
  }

  scheduleText(term, termType, emiAmount, totalPayable) {
    if (term <= 0 || totalPayable <= 0) {
      return "Enter principal amount, interest percent and loan term to see EMI details."
    }

    const interval = this.intervalMonths(termType)
    const firstDueDate = this.firstDueDate(interval)
    const dueText = firstDueDate ? ` First EMI due date: ${firstDueDate}.` : ""

    return `${term} reducing balance installment(s) will be generated. Principal is fixed every installment and interest is calculated on opening balance. First EMI will be around ${this.currency(emiAmount)}.${dueText}`
  }

  firstDueDate(interval) {
    if (!this.hasDistributionDateTarget || !this.distributionDateTarget.value) return null

    const date = new Date(`${this.distributionDateTarget.value}T00:00:00`)
    date.setMonth(date.getMonth() + interval)
    return date.toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" })
  }

  intervalMonths(termType) {
    if (termType === "Quarterly") return 3
    if (termType === "Half Yearly") return 6
    if (termType === "Yearly") return 12
    return 1
  }

  installmentsPerYear(termType) {
    return 12 / this.intervalMonths(termType)
  }

  roundMoney(value) {
    return Math.round((this.numberValue(value) + Number.EPSILON) * 100) / 100
  }

  numberValue(value) {
    const number = Number.parseFloat(value)
    return Number.isFinite(number) ? number : 0
  }

  percent(value) {
    return `${this.numberValue(value).toFixed(2)}%`
  }

  currency(value) {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
      maximumFractionDigits: 2
    }).format(this.numberValue(value))
  }
}

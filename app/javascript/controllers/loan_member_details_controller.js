import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "shg", "member", "group", "gender", "dob", "address",
    "distributionDate", "termType", "term", "principal", "interestPercent",
    "principalOut", "interestOut", "totalOut", "paidOut", "remainingOut",
    "emiOut", "scheduleLabel", "scheduleOut"
  ]

  static values = {
    paid: Number
  }

  connect() {
    this.memberOptions = Array.from(this.memberTarget.options).map((option) => option.cloneNode(true))
    this.filterMembers()
    this.update()
    this.calculate()
  }

  shgChanged() {
    this.filterMembers()
    this.update()
  }

  filterMembers() {
    const selectedShgId = this.shgTarget.value
    const selectedMemberId = this.memberTarget.value
    const prompt = this.memberOptions.find((option) => option.value === "")?.cloneNode(true)
    const matchingOptions = this.memberOptions
      .filter((option) => option.value !== "" && (!selectedShgId || option.dataset.shgId === selectedShgId))
      .map((option) => option.cloneNode(true))

    this.memberTarget.replaceChildren(...[prompt, ...matchingOptions].filter(Boolean))

    if (matchingOptions.some((option) => option.value === selectedMemberId)) {
      this.memberTarget.value = selectedMemberId
    } else {
      this.memberTarget.value = ""
    }
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

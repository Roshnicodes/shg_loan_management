// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

function enhanceSearchableSelects() {
  document.querySelectorAll(".searchable-select").forEach((wrapper) => wrapper.remove())
  document.querySelectorAll(".searchable-select-menu").forEach((menu) => menu.remove())
  document.querySelectorAll(".searchable-select-native").forEach((select) => {
    select.classList.remove("searchable-select-native")
    select.removeAttribute("tabindex")
  })
}

const cascadeTargetSelectors = {
  block: '[data-location-select-target="block"], [data-loan-member-details-target="block"], [data-visit-select-target="block"]',
  village: '[data-location-select-target="village"], [data-loan-member-details-target="village"], [data-visit-select-target="village"]',
  shg: '[data-location-select-target="shg"], [data-loan-member-details-target="shg"], [data-visit-select-target="shg"]',
  member: '[data-location-select-target="member"], [data-loan-member-details-target="member"], [data-visit-select-target="member"]',
  loan: '[data-location-select-target="loan"]'
}

function cascadeFormFor(element) {
  return element.closest('form[data-controller*="location-select"], form[data-controller*="loan-member-details"], form[data-controller*="visit-select"]')
}

function cascadeTargets(form) {
  return Object.fromEntries(Object.entries(cascadeTargetSelectors).map(([name, selector]) => [name, form.querySelector(selector)]))
}

function cascadeOriginalOptions(select) {
  if (!select) return []
  if (!select._cascadeOriginalOptions) select._cascadeOriginalOptions = Array.from(select.options).map((option) => option.cloneNode(true))
  return select._cascadeOriginalOptions
}

function primeCascadeOriginalOptions(form) {
  Object.values(cascadeTargets(form)).forEach(cascadeOriginalOptions)
}

function dataValue(option, key) {
  if (!option) return ""

  const datasetValue = option.dataset[key]
  if (datasetValue !== undefined) return datasetValue

  const dashedKey = key.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`)
  return option.getAttribute(`data-${dashedKey}`) || ""
}

function replaceCascadeOptions(select, predicate) {
  if (!select) return

  const selectedValue = select.value
  select.innerHTML = ""

  cascadeOriginalOptions(select).forEach((option) => {
    if (option.value === "" || predicate(option)) select.appendChild(option.cloneNode(true))
  })

  select.value = Array.from(select.options).some((option) => option.value === selectedValue) ? selectedValue : ""
  select.dispatchEvent(new CustomEvent("searchable-select:refresh"))
}

function optionMatchesCascade(option, selected) {
  const villageId = dataValue(option, "villageId")
  const blockId = dataValue(option, "blockId")

  if (selected.villageId) return villageId === selected.villageId
  if (selected.blockId) return blockId === selected.blockId
  return true
}

function filterCascadeForm(form) {
  primeCascadeOriginalOptions(form)

  const targets = cascadeTargets(form)
  const selected = {
    blockId: targets.block?.value || dataValue(targets.village?.selectedOptions[0], "blockId"),
    villageId: targets.village?.value || "",
    shgId: targets.shg?.value || "",
    memberId: targets.member?.value || ""
  }

  replaceCascadeOptions(targets.village, (option) => !selected.blockId || dataValue(option, "blockId") === selected.blockId)
  replaceCascadeOptions(targets.shg, (option) => optionMatchesCascade(option, selected))
  replaceCascadeOptions(targets.member, (option) => (
    optionMatchesCascade(option, selected) &&
      (!selected.shgId || dataValue(option, "shgId") === selected.shgId)
  ))
  replaceCascadeOptions(targets.loan, (option) => (
    optionMatchesCascade(option, selected) &&
      (!selected.shgId || dataValue(option, "shgId") === selected.shgId) &&
      (!selected.memberId || dataValue(option, "memberId") === selected.memberId)
  ))
}

function clearCascadeChildren(target, form) {
  const targets = cascadeTargets(form)

  if (target === targets.block) {
    if (targets.village) targets.village.value = ""
    if (targets.shg) targets.shg.value = ""
    if (targets.member) targets.member.value = ""
    if (targets.loan) targets.loan.value = ""
  } else if (target === targets.village) {
    if (targets.shg) targets.shg.value = ""
    if (targets.member) targets.member.value = ""
    if (targets.loan) targets.loan.value = ""
  } else if (target === targets.shg) {
    if (targets.member) targets.member.value = ""
    if (targets.loan) targets.loan.value = ""
  } else if (target === targets.member) {
    if (targets.loan) targets.loan.value = ""
  }
}

function refreshCascadeForms() {
  document.querySelectorAll('form[data-controller*="location-select"], form[data-controller*="loan-member-details"], form[data-controller*="visit-select"]').forEach((form) => {
    primeCascadeOriginalOptions(form)
    filterCascadeForm(form)
  })
}

function bulkCheckboxes(formId) {
  return Array.from(document.querySelectorAll(`input[type="checkbox"][name="ids[]"][form="${formId}"]`))
    .filter((checkbox) => !checkbox.disabled)
}

function refreshBulkSelectAll(master) {
  const checkboxes = bulkCheckboxes(master.dataset.bulkSelectForm)
  const checked = checkboxes.filter((checkbox) => checkbox.checked).length

  master.disabled = checkboxes.length === 0
  master.checked = checkboxes.length > 0 && checked === checkboxes.length
  master.indeterminate = checked > 0 && checked < checkboxes.length
}

document.addEventListener("turbo:load", () => {
  enhanceSearchableSelects()
  refreshCascadeForms()
  document.querySelectorAll("[data-bulk-select-all]").forEach(refreshBulkSelectAll)
  document.querySelectorAll("[data-auto-hide-ms]").forEach((element) => {
    const delay = Number.parseInt(element.dataset.autoHideMs, 10)
    if (Number.isFinite(delay) && delay > 0) {
      window.setTimeout(() => element.setAttribute("hidden", ""), delay)
    }
  })
  closeMobileMenu()
})

document.addEventListener("turbo:frame-load", () => {
  enhanceSearchableSelects()
  refreshCascadeForms()
})

document.addEventListener("change", (event) => {
  const target = event.target
  const cascadeForm = cascadeFormFor(target)

  if (cascadeForm) {
    clearCascadeChildren(target, cascadeForm)
    filterCascadeForm(cascadeForm)
  }

  if (target.matches("[data-bulk-select-all]")) {
    bulkCheckboxes(target.dataset.bulkSelectForm).forEach((checkbox) => {
      checkbox.checked = target.checked
    })
    refreshBulkSelectAll(target)
    return
  }

  if (target.matches('input[type="checkbox"][name="ids[]"][form]')) {
    const master = document.querySelector(`[data-bulk-select-all][data-bulk-select-form="${target.getAttribute("form")}"]`)
    if (master) refreshBulkSelectAll(master)
  }
})

function closeMobileMenu() {
  document.body.classList.remove("mobile-menu-open")
  document.querySelectorAll("[data-mobile-menu-toggle]").forEach((button) => {
    button.setAttribute("aria-expanded", "false")
  })
  document.querySelectorAll(".mobile-menu-drawer").forEach((drawer) => {
    drawer.setAttribute("aria-hidden", "true")
  })
}

function openMobileMenu() {
  document.body.classList.add("mobile-menu-open")
  document.querySelectorAll("[data-mobile-menu-toggle]").forEach((button) => {
    button.setAttribute("aria-expanded", "true")
  })
  document.querySelectorAll(".mobile-menu-drawer").forEach((drawer) => {
    drawer.setAttribute("aria-hidden", "false")
  })
}

document.addEventListener("click", (event) => {
  if (event.target.closest("[data-mobile-menu-toggle]")) {
    if (document.body.classList.contains("mobile-menu-open")) {
      closeMobileMenu()
    } else {
      openMobileMenu()
    }
    return
  }

  if (event.target.closest("[data-mobile-menu-close]") || event.target.closest(".mobile-menu-nav a")) {
    closeMobileMenu()
  }
})

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") closeMobileMenu()
})

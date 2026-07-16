// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

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
  document.querySelectorAll("[data-bulk-select-all]").forEach(refreshBulkSelectAll)
})

document.addEventListener("change", (event) => {
  const target = event.target

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

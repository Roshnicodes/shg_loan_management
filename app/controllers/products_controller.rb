class ProductsController < AdminRecordsController
  self.record_class = Product
  self.record_title = "Product"
  self.record_fields = [
    { name: :name, label: "Product Name" },
    { name: :active, label: "Active", type: :checkbox }
  ]
end

class Product {
  final int id;
  final String sku;
  final String name;

  Product({required this.id, required this.sku, required this.name});

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] ?? 0,
      sku: json['sku'] ?? 'UNKNOWN',
      name: json['name'] ?? 'No Name',
    );
  }
}

class ScannedItem {
  final String barcode;
  final Product product;
  int quantity;

  ScannedItem({
    required this.barcode,
    required this.product,
    this.quantity = 1,
  });
}
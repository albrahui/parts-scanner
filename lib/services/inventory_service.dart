import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/product_model.dart';
import '../utils/barcode_utils.dart';

class InventoryService {
  // In the future, change this method to call your API
  Future<List<Product>> fetchCatalog() async {
    try {
      // Simulate network delay if needed
      // await Future.delayed(Duration(milliseconds: 500));

      final String response = await rootBundle.loadString('assets/products.json');
      final data = await json.decode(response);

      return (data['data'] as List)
          .map((item) => Product.fromJson(item))
          .toList();
    } catch (e) {
      // Handle error or return empty list
      print("Error loading catalog: $e");
      return [];
    }
  }

  // Helper to find matches in the loaded catalog
  List<Product> findMatches(String barcode, List<Product> catalog) {
    String cleanCode = BarcodeUtils.cleanGhostCharacters(barcode);

    return catalog.where((p) {
      return BarcodeUtils.isMatch(p.sku, cleanCode);
    }).toList();
  }
}
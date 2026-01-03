import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'models/product_model.dart';
import 'services/inventory_service.dart';
import 'services/export_service.dart';
import 'utils/barcode_utils.dart';

void main() {
  runApp(
    const MaterialApp(home: WarehouseHome(), debugShowCheckedModeBanner: false),
  );
}

class WarehouseHome extends StatefulWidget {
  const WarehouseHome({super.key});

  @override
  State<WarehouseHome> createState() => _WarehouseHomeState();
}

class _WarehouseHomeState extends State<WarehouseHome> {
  // Services
  final InventoryService _inventoryService = InventoryService();
  final ExportService _exportService = ExportService();

  // State
  List<Product> _catalog = [];
  final List<ScannedItem> _sessionItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initCatalog();
  }

  Future<void> _initCatalog() async {
    final products = await _inventoryService.fetchCatalog();
    setState(() {
      _catalog = products;
      _isLoading = false;
    });
  }

  // --- CORE LOGIC ---
  void _onBarcodeScanned(String rawCode) async {
    String cleanDisplayCode = BarcodeUtils.cleanGhostCharacters(rawCode).trim();

    // Use Service to find matches
    List<Product> candidates = _inventoryService.findMatches(rawCode, _catalog);

    Product? selectedProduct;

    if (candidates.isEmpty) {
      selectedProduct = await _showLinkDialog(cleanDisplayCode);
    } else if (candidates.length == 1) {
      selectedProduct = candidates.first;
    } else {
      selectedProduct = await _showVariantDialog(cleanDisplayCode, candidates);
    }

    if (selectedProduct != null) {
      int? qty = await _askQuantity(selectedProduct);
      if (qty != null && qty > 0) {
        _addToCart(cleanDisplayCode, selectedProduct, qty);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Added $qty x ${selectedProduct.name}"),
            backgroundColor: Colors.green,
            duration: const Duration(milliseconds: 500),
          ),
        );
      }
    }
  }

  void _addToCart(String barcode, Product product, int qty) {
    setState(() {
      try {
        final existingItem = _sessionItems.firstWhere(
          (item) => item.product.id == product.id,
        );
        existingItem.quantity += qty;
      } catch (e) {
        _sessionItems.add(
          ScannedItem(barcode: barcode, product: product, quantity: qty),
        );
      }
    });
  }

  // --- UI ACTIONS ---
  void _clearAll() {
    _showConfirmDialog("حذف الكل", "حذف جميع الارقام?", () {
      setState(() => _sessionItems.clear());
    });
  }

  void _deleteItem(ScannedItem item) {
    _showConfirmDialog("حذف الصنف؟", "Delete ${item.product.name}?", () {
      setState(() => _sessionItems.remove(item));
    });
  }

  void _editQuantity(ScannedItem item) async {
    int? qty = await _askQuantity(item.product, initialQty: item.quantity);
    if (qty != null) setState(() => item.quantity = qty);
  }

  // --- UI BUILD ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "المخزن",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        centerTitle: true,
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _clearAll,
          ),
          IconButton(
            icon: const Icon(Icons.save_alt),
            onPressed: () =>
                _exportService.saveToDownloads(context, _sessionItems),
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _exportService.shareCsv(context, _sessionItems),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.blueGrey[800],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "المنتجات: ${_sessionItems.length}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        "الكمية: ${_sessionItems.fold(0, (sum, item) => sum + item.quantity)}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _sessionItems.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _sessionItems.length,
                          itemBuilder: (ctx, index) {
                            final item =
                                _sessionItems[_sessionItems.length - 1 - index];
                            return _buildItemCard(item);
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: SizedBox(
        height: 70,
        width: 70,
        child: FloatingActionButton(
          backgroundColor: Colors.blue[800],
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ScannerView(onDetect: _onBarcodeScanned),
            ),
          ),
          child: const Icon(Icons.qr_code_scanner, size: 36),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // --- WIDGET HELPERS ---

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_2, size: 100, color: Colors.grey[300]),
          const SizedBox(height: 20),
          Text(
            "جاهز للبدء",
            style: TextStyle(color: Colors.grey[500], fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(ScannedItem item) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Colors.blueGrey[700],
          child: Text(
            "${item.quantity}",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          item.product.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.product.sku,
              style: TextStyle(
                color: Colors.blue[800],
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              "مسح الان: ${item.barcode}",
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
        trailing: const Icon(Icons.edit, size: 20, color: Colors.grey),
        onTap: () => _editQuantity(item),
        onLongPress: () => _deleteItem(item),
      ),
    );
  }

  // --- DIALOGS (Kept in main for Context access) ---

  void _showConfirmDialog(
    String title,
    String content,
    VoidCallback onConfirm,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("الغاء"),
          ),
          TextButton(
            onPressed: () {
              onConfirm();
              Navigator.pop(ctx);
            },
            child: const Text("تأكيد", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<int?> _askQuantity(Product product, {int initialQty = 1}) async {
    int currentQty = initialQty;
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start, // Aligns text to the left
                children: [
                  const Center(
                    child: Text(
                      "اضافة الرقم",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Text(
                    product.sku,
                    style: TextStyle(color: Colors.grey[700], fontSize: 14),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("اختار الكمية المطلوبة"),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: () => currentQty > 1
                            ? setState(() => currentQty--)
                            : null,
                        icon: const Icon(
                          Icons.remove_circle,
                          size: 32,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(width: 15),
                      Text(
                        "$currentQty",
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 15),
                      IconButton(
                        onPressed: () => setState(() => currentQty++),
                        icon: const Icon(
                          Icons.add_circle,
                          size: 32,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text("الغاء"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, currentQty),
                  child: const Text("تاكيد"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Note: Variant and Link dialogs would also be here, simplified similarly.
  // For brevity, I'll include the Link Dialog logic inline or you can keep it as is.
  Future<Product?> _showLinkDialog(String code) async {
    // Re-use logic: Filter catalog locally
    return showDialog<Product>(
      context: context,
      builder: (ctx) {
        List<Product> suggestions = _inventoryService.findMatches(
          code,
          _catalog,
        ); // Use service for suggestions logic too? Or keep it specific.
        // Actually, the Service findMatches is strict. For "Manual Search" we want fuzzy search.
        // Let's keep manual search logic here or add 'fuzzySearch' to service.
        List<Product> initialList = suggestions.isNotEmpty
            ? suggestions
            : List.from(_catalog);

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text("الرابط: $code"),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    if (suggestions.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.green.shade100,
                        width: double.infinity,
                        child: Text(
                          "✓ Found ${suggestions.length}",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.green.shade800),
                        ),
                      ),
                    TextField(
                      decoration: const InputDecoration(
                        hintText: "بحث...",
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (val) {
                        setState(() {
                          // Fuzzy search logic
                          initialList = _catalog
                              .where(
                                (p) =>
                                    p.name.toLowerCase().contains(
                                      val.toLowerCase(),
                                    ) ||
                                    p.sku.toLowerCase().contains(
                                      val.toLowerCase(),
                                    ),
                              )
                              .toList();
                        });
                      },
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: initialList.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (ctx, index) {
                          final p = initialList[index];
                          return ListTile(
                            title: Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              p.sku,
                              style: const TextStyle(color: Colors.blue),
                            ),
                            onTap: () => Navigator.pop(ctx, p),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text("تراجع"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<Product?> _showVariantDialog(
    String code,
    List<Product> candidates,
  ) async {
    return showDialog<Product>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Center(child: Text("رقم متكرر")),

        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.separated(
            itemCount: candidates.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (ctx, i) => ListTile(
              tileColor: Colors.blue.shade50,
              title: Text(
                candidates[i].name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                candidates[i].sku,
                style: const TextStyle(color: Colors.blue),
              ),
              onTap: () => Navigator.pop(ctx, candidates[i]),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text("تراجع"),
          ),
        ],
      ),
    );
  }
}

class ScannerView extends StatelessWidget {
  final Function(String) onDetect;
  const ScannerView({super.key, required this.onDetect});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              for (final barcode in capture.barcodes) {
                if (barcode.rawValue != null) {
                  Navigator.pop(context);
                  onDetect(barcode.rawValue!);
                  break;
                }
              }
            },
          ),
          ColorFiltered(
            colorFilter: const ColorFilter.mode(
              Colors.black54,
              BlendMode.srcOut,
            ),
            child: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.transparent,
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
                Center(
                  child: Container(
                    height: 250,
                    width: 350,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 50,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "Align barcode in box",
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart'; // <--- IMPORT THIS

void main() {
  runApp(
    const MaterialApp(home: WarehouseHome(), debugShowCheckedModeBanner: false),
  );
}

// --- DATA MODELS ---
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

// --- MAIN SCREEN ---
class WarehouseHome extends StatefulWidget {
  const WarehouseHome({super.key});

  @override
  State<WarehouseHome> createState() => _WarehouseHomeState();
}

class _WarehouseHomeState extends State<WarehouseHome> {
  List<Product> _catalog = [];
  final List<ScannedItem> _sessionItems = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    try {
      final String response = await rootBundle.loadString(
        'assets/products.json',
      );
      final data = await json.decode(response);
      setState(() {
        _catalog = (data['data'] as List)
            .map((item) => Product.fromJson(item))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading catalog: $e");
    }
  }

  // --- LOGIC: CLEANING ---
  String normalizeScannedCode(String rawCode) {
    String clean = rawCode.replaceAll(" ", "").toUpperCase();
    if (clean.startsWith("A")) {
      return clean.substring(1);
    }
    return clean;
  }

  String getPureSku(String originalSku) {
    String clean = originalSku.replaceAll(" ", "").toUpperCase();
    if (clean.contains("/")) {
      clean = clean.split("/")[0];
    }
    if (clean.startsWith("VW")) {
      clean = clean.substring(2);
    } else if (clean.startsWith("RNG")) {
      clean = clean.substring(3);
    }
    return clean;
  }

  // --- LOGIC: SCANNING ---
  void _onBarcodeScanned(String rawCode) async {
    String cleanRaw = rawCode.replaceAll("]C1", "").replaceAll("]C", "");
    String logicKey = normalizeScannedCode(cleanRaw);
    String displayCode = cleanRaw.trim();

    List<Product> candidates = _catalog.where((p) {
      String dbSkuClean = getPureSku(p.sku);
      bool dbContainsScan = dbSkuClean.contains(logicKey);
      bool scanContainsDb =
          logicKey.contains(dbSkuClean) && dbSkuClean.length > 3;
      return dbContainsScan || scanContainsDb;
    }).toList();

    Product? selectedProduct;

    if (candidates.isEmpty) {
      selectedProduct = await _showLinkDialog(displayCode);
    } else if (candidates.length == 1) {
      selectedProduct = candidates.first;
    } else {
      selectedProduct = await _showVariantDialog(displayCode, candidates);
    }

    if (selectedProduct != null) {
      int? qty = await _askQuantity(selectedProduct);
      if (qty != null && qty > 0) {
        _addToCart(displayCode, selectedProduct, qty);
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

  // --- LOGIC: DELETE & CLEAR ---
  void _deleteItem(ScannedItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Remove Item?"),
        content: Text("Delete ${item.product.name}?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _sessionItems.remove(item);
              });
              Navigator.pop(ctx);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _clearAll() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clear All?"),
        content: const Text("This will delete all scanned items."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _sessionItems.clear();
              });
              Navigator.pop(ctx);
            },
            child: const Text("Clear All", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // --- LOGIC: CSV GENERATION ---
  // Helper to generate CSV string
  String _generateCsvString() {
    List<List<dynamic>> rows = [];
    rows.add(["Barcode", "SKU", "Name", "Quantity"]);

    for (var item in _sessionItems) {
      rows.add([
        item.barcode,
        item.product.sku,
        item.product.name,
        item.quantity,
      ]);
    }

    String csvData = const ListToCsvConverter().convert(rows);
    return '\uFEFF$csvData'; // BOM for Arabic support
  }

  // OPTION 1: SHARE (Send to WhatsApp/Email)
  Future<void> _shareCsv() async {
    if (_sessionItems.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Nothing to export!")));
      return;
    }
    String csvData = _generateCsvString();
    final directory = await getTemporaryDirectory();
    final path =
        "${directory.path}/shipment_${DateTime.now().millisecondsSinceEpoch}.csv";
    final file = File(path);
    await file.writeAsString(csvData);
    await Share.shareXFiles([XFile(path)], text: 'New Shipment Scan');
  }

  // OPTION 2: SAVE TO DOWNLOADS (Direct file save)
  Future<void> _saveToDownloads() async {
    if (_sessionItems.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Nothing to save!")));
      return;
    }

    // 1. Request Permission
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }

    // Note: On Android 11+, storage permission might be restricted,
    // but writing to public Downloads usually works for own files.
    if (status.isGranted ||
        await Permission.manageExternalStorage.isGranted ||
        Platform.isAndroid) {
      try {
        String csvData = _generateCsvString();

        // 2. Get Downloads Path (Android Standard)
        String fileName =
            "shipment_${DateTime.now().millisecondsSinceEpoch}.csv";
        Directory downloadsDir = Directory('/storage/emulated/0/Download');

        // If directory doesn't exist (rare), fallback or try to create
        if (!await downloadsDir.exists()) {
          downloadsDir =
              await getExternalStorageDirectory() ??
              Directory('/storage/emulated/0/Download');
        }

        String savePath = "${downloadsDir.path}/$fileName";
        final file = File(savePath);

        // 3. Write File
        await file.writeAsString(csvData);

        // 4. Success Message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Saved to Downloads!\n$fileName"),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error saving: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Permission Denied"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // --- DIALOGS & UI ---

  Future<int?> _askQuantity(Product product, {int initialQty = 1}) async {
    int currentQty = initialQty;
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text("Add: ${product.sku}"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Quantity:"),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: () => currentQty > 1
                            ? setState(() => currentQty--)
                            : null,
                        icon: const Icon(Icons.remove_circle, size: 32),
                        color: Colors.red,
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
                        icon: const Icon(Icons.add_circle, size: 32),
                        color: Colors.green,
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, currentQty),
                  child: const Text("Confirm"),
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
        title: const Text("Multiple Matches"),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Select correct item:"),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.separated(
                  itemCount: candidates.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (ctx, index) {
                    final p = candidates[index];
                    return ListTile(
                      tileColor: Colors.blue.shade50,
                      title: Text(
                        p.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        p.sku,
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
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
            child: const Text("Cancel"),
          ),
        ],
      ),
    );
  }

  Future<Product?> _showLinkDialog(String code) async {
    return showDialog<Product>(
      context: context,
      builder: (ctx) {
        List<Product> suggestions = _catalog.where((p) {
          String dbSkuClean = getPureSku(p.sku);
          bool dbContainsScan = dbSkuClean.contains(code);
          bool scanContainsDb =
              code.contains(dbSkuClean) && dbSkuClean.length > 3;
          return dbContainsScan || scanContainsDb;
        }).toList();

        List<Product> initialList = suggestions.isNotEmpty
            ? suggestions
            : List.from(_catalog);

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text("Link: $code"),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    if (suggestions.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(8.0),
                        color: Colors.green.shade100,
                        width: double.infinity,
                        child: Text(
                          "✓ Found ${suggestions.length} matches",
                          style: TextStyle(color: Colors.green.shade800),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 10),
                    TextField(
                      decoration: const InputDecoration(
                        hintText: "Search...",
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        setState(() {
                          initialList = _catalog.where((p) {
                            return p.name.toLowerCase().contains(
                                  val.toLowerCase(),
                                ) ||
                                p.sku.toLowerCase().contains(
                                  val.toLowerCase(),
                                ) ||
                                getPureSku(p.sku).contains(val.toUpperCase());
                          }).toList();
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.separated(
                        itemCount: initialList.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (ctx, index) {
                          final p = initialList[index];
                          return ListTile(
                            tileColor: suggestions.contains(p)
                                ? Colors.green.shade50
                                : null,
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
                  child: const Text("Cancel"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _editQuantity(ScannedItem item) async {
    int? qty = await _askQuantity(item.product, initialQty: item.quantity);
    if (qty != null) {
      setState(() {
        item.quantity = qty;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          "INVENTORY",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        centerTitle: true,
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: "Clear All",
            onPressed: _clearAll,
          ),
          IconButton(
            icon: const Icon(Icons.save_alt),
            tooltip: "Save to Phone",
            onPressed: _saveToDownloads,
          ), // <--- SAVE BUTTON
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: "Share CSV",
            onPressed: _shareCsv,
          ), // <--- SHARE BUTTON
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.blueGrey[800],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Items: ${_sessionItems.length}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        "Total Qty: ${_sessionItems.fold(0, (sum, item) => sum + item.quantity)}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                // List
                Expanded(
                  child: _sessionItems.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.qr_code_2,
                                size: 100,
                                color: Colors.grey[300],
                              ),
                              const SizedBox(height: 20),
                              Text(
                                "Ready to scan",
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _sessionItems.length,
                          itemBuilder: (ctx, index) {
                            final item =
                                _sessionItems[_sessionItems.length - 1 - index];
                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
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
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      item.product.sku,
                                      style: TextStyle(
                                        color: Colors.blue[800],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      "Scan: ${item.barcode}",
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: const Icon(
                                  Icons.edit,
                                  size: 20,
                                  color: Colors.grey,
                                ),
                                onTap: () => _editQuantity(item),
                                onLongPress: () => _deleteItem(item),
                              ),
                            );
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
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
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

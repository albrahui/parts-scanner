import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import '../models/product_model.dart';

class ExportService {
  String _generateCsvString(List<ScannedItem> items) {
    List<List<dynamic>> rows = [];
    rows.add(["Barcode", "SKU", "Name", "Quantity"]);

    for (var item in items) {
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

  Future<void> shareCsv(BuildContext context, List<ScannedItem> items) async {
    if (items.isEmpty) {
      _showSnack(context, "Nothing to export!", isError: true);
      return;
    }

    String csvData = _generateCsvString(items);
    final directory = await getTemporaryDirectory();
    final path = "${directory.path}/shipment_${DateTime.now().millisecondsSinceEpoch}.csv";
    final file = File(path);
    await file.writeAsString(csvData);
    await Share.shareXFiles([XFile(path)], text: 'New Shipment Scan');
  }

  Future<void> saveToDownloads(BuildContext context, List<ScannedItem> items) async {
    if (items.isEmpty) {
      _showSnack(context, "Nothing to save!", isError: true);
      return;
    }

    // Request Permission
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }

    if (status.isGranted || await Permission.manageExternalStorage.isGranted || Platform.isAndroid) {
      try {
        String csvData = _generateCsvString(items);
        String fileName = "shipment_${DateTime.now().millisecondsSinceEpoch}.csv";

        Directory downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
           downloadsDir = await getExternalStorageDirectory() ?? Directory('/storage/emulated/0/Download');
        }

        final file = File("${downloadsDir.path}/$fileName");
        await file.writeAsString(csvData);

        _showSnack(context, "Saved to Downloads!\n$fileName", isError: false);
      } catch (e) {
        _showSnack(context, "Error saving: $e", isError: true);
      }
    } else {
      _showSnack(context, "Permission Denied", isError: true);
    }
  }

  void _showSnack(BuildContext context, String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }
}
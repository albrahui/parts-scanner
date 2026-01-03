Markdown

# 📦 Warehouse Scanner App

A robust, modular Flutter application designed for efficient inventory management. This app scans barcodes, matches them against a local product database (with smart logic for partial matches), tracks quantities, and exports shipment data to CSV.

## ✨ Features

* **⚡ Smart Barcode Scanning:**
    * Automatically cleans "ghost characters" (like `]C1` from GS1-128 codes).
    * Normalizes input (e.g., strips 'A' prefixes from Mercedes parts).
    * **Two-Way Matching:** Finds products even if the scanned barcode is longer than the SKU (e.g., extra suffix digits).
* **🧩 Conflict Resolution:**
    * Handles ambiguous cases where one barcode matches multiple products (e.g., Genuine vs. Aftermarket variants).
    * Prompts the user to select the correct item.
* **🛠️ Manual Linking:**
    * Allows searching by name or SKU if a barcode is not found.
    * "Fuzzy search" logic to find items quickly.
* **📝 Session Management:**
    * Edit quantities on the fly.
    * Delete items with a long press.
    * Clear all items with one tap.
* **📂 Export & Save:**
    * **Share CSV:** Send inventory lists via WhatsApp, Email, etc.
    * **Save to Phone:** Direct save to the Android `Downloads` folder.
    * **Arabic Support:** CSV files are encoded with BOM to ensure Arabic characters display correctly in Excel.

## 🚀 Getting Started

### Prerequisites

* [Flutter SDK](https://flutter.dev/docs/get-started/install) installed.
* An Android device or emulator for testing.

### Installation

1.  **Clone the repository:**
    ```bash
    git clone [https://github.com/albrahui/parts-scanner.git](https://github.com/parts-scanner/parts-scanner.git)
    cd warehouse-scanner
    ```

2.  **Install dependencies:**
    ```bash
    flutter pub get
    ```

3.  **Run the app:**
    ```bash
    flutter run
    ```

## 🏗️ Project Structure

The project follows a clean, modular architecture for scalability.

```text
lib/
├── main.dart                  # Entry point & UI logic
├── models/
│   └── product_model.dart     # Data models (Product, ScannedItem)
├── services/
│   ├── inventory_service.dart # Handles data fetching (JSON/API)
│   └── export_service.dart    # Handles CSV generation & File Saving
└── utils/
    └── barcode_utils.dart     # Logic for cleaning & matching strings
```


⚙️ How It Works
1. Data Source
The app currently loads products from a local JSON file: assets/products.json

Format:

```JSON
{
  "data": [
    {
      "id": 101,
      "sku": "651 094 01 04",
      "name": "Air Filter"
    }
  ]
}
```

2. Matching Logic (barcode_utils.dart)
The app uses a "Smart Match" algorithm:
Cleaning: Removes ]C1, ]C, and spaces.
Prefix Stripping: Removes common prefixes like VW, RNG, or A (Mercedes).
Suffix Handling: Ignores suffixes like /KN or /BO in the database to match the raw barcode on the box.
📱 Permissions (Android)
This app requires storage permissions to save CSV files directly to the device.
WRITE_EXTERNAL_STORAGE
READ_EXTERNAL_STORAGE
These are automatically handled by the permission_handler plugin within the app.

📦 Dependencies
flutter: SDK
mobile_scanner: Camera & Barcode detection
csv: generating spreadsheet files
path_provider: finding device directories
share_plus: sharing files
permission_handler: managing Android permissions


class BarcodeUtils {
  // Removes ghost characters from scanner hardware (e.g. ]C1)
  static String cleanGhostCharacters(String rawCode) {
    return rawCode.replaceAll("]C1", "").replaceAll("]C", "");
  }

  // Prepares the scanned code for logic (Removes 'A', spaces)
  static String normalizeScannedCode(String rawCode) {
    String clean = rawCode.replaceAll(" ", "").toUpperCase();
    if (clean.startsWith("A")) {
      return clean.substring(1);
    }
    return clean;
  }

  // Prepares the Database SKU for matching (Removes VW, RNG, Suffixes)
  static String getPureSku(String originalSku) {
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

  // The core matching algorithm
  static bool isMatch(String dbSku, String scannedCode) {
    String dbClean = getPureSku(dbSku);
    String scanClean = normalizeScannedCode(scannedCode);

    // Two-Way Match
    bool dbContainsScan = dbClean.contains(scanClean);
    bool scanContainsDb = scanClean.contains(dbClean) && dbClean.length > 3;

    return dbContainsScan || scanContainsDb;
  }
}
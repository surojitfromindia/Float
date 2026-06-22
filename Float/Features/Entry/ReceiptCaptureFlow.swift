import Foundation
import SwiftData
import SwiftUI
import UIKit
import Vision
import VisionKit

struct ReceiptCaptureFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \CategoryItem.sortOrder) private var allCategories: [CategoryItem]
    @Query(sort: \AccountItem.createdAt) private var allAccounts: [AccountItem]
    @Query(sort: \TransactionItem.timestamp, order: .reverse) private var allTransactions:
        [TransactionItem]

    @State private var showingScanner = false
    @State private var isReadingReceipt = false
    @State private var merchantName = ""
    @State private var transactionDate = Date()
    @State private var totalAmountText = ""
    @State private var rawText = ""
    @State private var pageImageData: [Data] = []
    @State private var reviewLines: [ReceiptReviewLine] = []
    @State private var message: String?

    private var categories: [CategoryItem] {
        filterActiveProfile(allCategories).filter { !$0.archived && !$0.isIncome }
    }

    private var accounts: [AccountItem] {
        filterActiveProfile(allAccounts).filter { !$0.archived }
    }

    private var transactions: [TransactionItem] {
        filterActiveProfile(allTransactions).filter(\.isPosted)
    }

    private var selectedLineCount: Int {
        reviewLines.filter(\.selected).count
    }

    private var totalAmountMinor: Int64 {
        MoneyParser.parseDisplayAmountMinor(
            from: totalAmountText,
            currencyCode: appState.selectedCurrencyCode
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isReadingReceipt {
                        readingCard
                    } else if reviewLines.isEmpty {
                        startCard
                    } else {
                        reviewContent
                    }
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .navigationTitle("Receipt Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !reviewLines.isEmpty {
                        Button("Save", action: saveReceipt)
                            .disabled(selectedLineCount == 0)
                    }
                }
            }
            .floatBackground()
            .sheet(isPresented: $showingScanner) {
                ReceiptDocumentScanner { images in
                    handleScannedImages(images)
                } onCancel: {
                    showingScanner = false
                }
                .ignoresSafeArea()
            }
            .onAppear {
                if reviewLines.isEmpty && ReceiptDocumentScanner.isSupported {
                    showingScanner = true
                }
            }
        }
    }

    private var startCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                FloatIconBadge(
                    icon: ReceiptDocumentScanner.isSupported
                        ? "doc.viewfinder.fill"
                        : "camera.fill",
                    tint: appState.themePalette.accent,
                    size: 42
                )
                Text("Scan receipt")
                    .font(.headline)
                Text(
                    ReceiptDocumentScanner.isSupported
                        ? "Capture a receipt, review extracted lines, then save selected expenses."
                        : "Receipt scanning is not available on this device."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Button("Open scanner") {
                    showingScanner = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(!ReceiptDocumentScanner.isSupported)

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Color(hex: "#B4613B"))
                }
            }
        }
    }

    private var readingCard: some View {
        GlassCard {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reading receipt")
                        .font(.headline)
                    Text("Text recognition is running on device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Review before saving", systemImage: "checklist")
                        .font(.headline)
                    TextField("Merchant", text: $merchantName)
                        .textFieldStyle(.roundedBorder)
                    DatePicker(
                        "Date",
                        selection: $transactionDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    TextField("Total amount", text: $totalAmountText)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                    Text(
                        AppLocalization.format(
                            "%lld selected",
                            Int64(selectedLineCount)
                        )
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }

            SectionHeader(title: "Receipt lines")

            ForEach($reviewLines) { $line in
                receiptLineCard(line: $line)
            }

            Button {
                appendManualLine()
            } label: {
                Label("Add line", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color(hex: "#B4613B"))
            }
        }
    }

    private func receiptLineCard(line: Binding<ReceiptReviewLine>) -> some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Import this line", isOn: line.selected)
                    .font(.subheadline.weight(.semibold))

                TextField("Item", text: line.title)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    TextField("Qty", text: line.quantityText.boundString)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 92)
                    TextField("Amount", text: line.amountText)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                }

                Picker("Category", selection: line.categoryID) {
                    Text("Default").tag(UUID?.none)
                    ForEach(categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }

                Picker("Account", selection: line.accountID) {
                    Text("Default").tag(UUID?.none)
                    ForEach(accounts) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }

                if line.wrappedValue.duplicateTransactionID != nil {
                    Label(
                        "Possible duplicate",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: "#B4613B"))
                }
            }
        }
        .opacity(line.wrappedValue.selected ? 1 : 0.62)
    }

    private func handleScannedImages(_ images: [UIImage]) {
        showingScanner = false
        guard !images.isEmpty else { return }
        isReadingReceipt = true
        message = nil

        Task {
            let recognizedLines = await Task.detached(priority: .userInitiated) {
                ReceiptOCRProcessor.recognizeLines(in: images)
            }.value
            let extraction = ReceiptTextExtractor.extract(
                lines: recognizedLines,
                currencyCode: appState.selectedCurrencyCode
            )

            await MainActor.run {
                merchantName = extraction.merchantName
                transactionDate = extraction.transactionDate
                totalAmountText = ReceiptAmountFormatter.displayText(
                    minorUnits: extraction.totalAmountMinor,
                    currencyCode: appState.selectedCurrencyCode
                )
                rawText = recognizedLines.joined(separator: "\n")
                pageImageData = images.compactMap {
                    $0.jpegData(compressionQuality: 0.78)
                }
                reviewLines = extraction.lineItems.enumerated().map { index, item in
                    ReceiptReviewLine(
                        title: item.title,
                        quantityText: item.quantityText,
                        amountText: ReceiptAmountFormatter.displayText(
                            minorUnits: item.amountMinor,
                            currencyCode: appState.selectedCurrencyCode
                        ),
                        categoryID: defaultCategoryID(for: item.title),
                        accountID: defaultAccountID(),
                        duplicateTransactionID: duplicateTransactionID(
                            amountMinor: item.amountMinor,
                            title: item.title
                        ),
                        sortOrder: index
                    )
                }
                if reviewLines.isEmpty, extraction.totalAmountMinor > 0 {
                    reviewLines = [
                        ReceiptReviewLine(
                            title: extraction.merchantName,
                            quantityText: nil,
                            amountText: ReceiptAmountFormatter.displayText(
                                minorUnits: extraction.totalAmountMinor,
                                currencyCode: appState.selectedCurrencyCode
                            ),
                            categoryID: defaultCategoryID(for: extraction.merchantName),
                            accountID: defaultAccountID(),
                            duplicateTransactionID: duplicateTransactionID(
                                amountMinor: extraction.totalAmountMinor,
                                title: extraction.merchantName
                            ),
                            sortOrder: 0
                        )
                    ]
                }
                isReadingReceipt = false
            }
        }
    }

    private func appendManualLine() {
        reviewLines.append(
            ReceiptReviewLine(
                title: merchantName.nilIfBlankForReceiptCapture ?? String(localized: "Receipt item"),
                quantityText: nil,
                amountText: "",
                categoryID: defaultCategoryID(for: merchantName),
                accountID: defaultAccountID(),
                duplicateTransactionID: nil,
                sortOrder: reviewLines.count
            )
        )
    }

    private func saveReceipt() {
        let category = DefaultCategoryResolver.resolve(
            isExpense: true,
            preferredID: appState.lastUsedCategoryID,
            categories: categories,
            modelContext: modelContext
        )
        let account = DefaultAccountResolver.resolve(
            preferredID: appState.lastUsedAccountID,
            accounts: accounts,
            modelContext: modelContext,
            currencyCode: appState.selectedCurrencyCode
        )
        let selectedDrafts = reviewLines
            .filter(\.selected)
            .compactMap { line -> ReceiptLineImportDraft? in
                let amountMinor = MoneyParser.parseDisplayAmountMinor(
                    from: line.amountText,
                    currencyCode: appState.selectedCurrencyCode
                )
                guard amountMinor > 0 else { return nil }
                let resolvedCategory = line.categoryID.flatMap(categoryByID) ?? category
                let resolvedAccount = line.accountID.flatMap(accountByID) ?? account
                return ReceiptLineImportDraft(
                    title: line.title.nilIfBlankForReceiptCapture ?? merchantName,
                    quantityText: line.quantityText?.nilIfBlankForReceiptCapture,
                    amountMinor: amountMinor,
                    category: resolvedCategory,
                    account: resolvedAccount,
                    duplicateTransactionID: duplicateTransactionID(
                        amountMinor: amountMinor,
                        title: line.title
                    )
                )
            }

        guard !selectedDrafts.isEmpty else {
            message = String(localized: "Select at least one valid receipt line.")
            return
        }

        do {
            _ = try ReceiptCaptureRepository(modelContext: modelContext)
                .createImportedReceipt(
                    from: ReceiptCaptureDraft(
                        merchantName: merchantName,
                        transactionDate: transactionDate,
                        totalAmountMinor: totalAmountMinor,
                        currencyCode: appState.selectedCurrencyCode,
                        rawText: rawText,
                        imageData: pageImageData,
                        lineItems: selectedDrafts
                    )
                )
            if let firstCategory = selectedDrafts.first?.category {
                appState.lastUsedCategoryID = firstCategory.id.uuidString
            }
            if let firstAccount = selectedDrafts.first?.account {
                appState.lastUsedAccountID = firstAccount.id.uuidString
            }
            Haptics.confirm()
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }

    private func defaultCategoryID(for title: String) -> UUID? {
        let lowered = title.lowercased()
        if let historical = transactions.first(where: { transaction in
            guard let note = transaction.note?.lowercased(),
                  let category = transaction.category,
                  !category.archived,
                  !category.isIncome
            else { return false }
            return lowered.contains(note) || note.contains(lowered)
        })?.category?.id {
            return historical
        }

        if let lastUsed = UUID(uuidString: appState.lastUsedCategoryID),
           categories.contains(where: { $0.id == lastUsed }) {
            return lastUsed
        }
        return categories.first?.id
    }

    private func defaultAccountID() -> UUID? {
        if let lastUsed = UUID(uuidString: appState.lastUsedAccountID),
           accounts.contains(where: { $0.id == lastUsed }) {
            return lastUsed
        }
        return accounts.first?.id
    }

    private func categoryByID(_ id: UUID) -> CategoryItem? {
        categories.first { $0.id == id }
    }

    private func accountByID(_ id: UUID) -> AccountItem? {
        accounts.first { $0.id == id }
    }

    private func duplicateTransactionID(amountMinor: Int64, title: String) -> UUID? {
        let calendar = Calendar.current
        return transactions.first { transaction in
            guard transaction.amountMinor == amountMinor else { return false }
            let days = abs(
                calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: transaction.timestamp),
                    to: calendar.startOfDay(for: transactionDate)
                ).day ?? 999
            )
            guard days <= 2 else { return false }
            let receiptTitle = title.normalizedReceiptSearchText
            let transactionText = [
                transaction.note,
                transaction.category?.name,
                transaction.account?.name,
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .normalizedReceiptSearchText
            guard !transactionText.isEmpty else { return true }
            return receiptTitle.isEmpty
                || transactionText.contains(receiptTitle)
                || receiptTitle.contains(transactionText)
                || merchantName.normalizedReceiptSearchText.contains(transactionText)
        }?.id
    }
}

private struct ReceiptReviewLine: Identifiable {
    let id = UUID()
    var title: String
    var quantityText: String?
    var amountText: String
    var selected = true
    var categoryID: UUID?
    var accountID: UUID?
    var duplicateTransactionID: UUID?
    var sortOrder: Int
}

private struct ReceiptExtractionResult {
    var merchantName: String
    var transactionDate: Date
    var totalAmountMinor: Int64
    var lineItems: [ReceiptExtractedLine]
}

private struct ReceiptExtractedLine {
    var title: String
    var quantityText: String?
    var amountMinor: Int64
}

private enum ReceiptOCRProcessor {
    nonisolated static func recognizeLines(in images: [UIImage]) -> [String] {
        images.flatMap { image in
            guard let cgImage = image.cgImage else { return [String]() }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.012
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: .up,
                options: [:]
            )
            do {
                try handler.perform([request])
                return (request.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            } catch {
                return []
            }
        }
    }
}

private enum ReceiptTextExtractor {
    static func extract(lines: [String], currencyCode: String) -> ReceiptExtractionResult {
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let merchant = merchantName(from: cleaned)
        let date = transactionDate(from: cleaned) ?? Date()
        let total = totalAmountMinor(from: cleaned, currencyCode: currencyCode)
        var items = lineItems(from: cleaned, currencyCode: currencyCode)
        if total > 0 {
            items = items.filter { $0.amountMinor <= total || items.count == 1 }
        }
        return ReceiptExtractionResult(
            merchantName: merchant,
            transactionDate: date,
            totalAmountMinor: total,
            lineItems: items
        )
    }

    private static func merchantName(from lines: [String]) -> String {
        let ignoredTokens = ["invoice", "receipt", "tax", "gst", "phone", "date", "time"]
        return lines.prefix(8).first { line in
            let lowered = line.lowercased()
            return line.count >= 3
                && line.rangeOfCharacter(from: .letters) != nil
                && !ignoredTokens.contains { lowered.contains($0) }
        } ?? String(localized: "Receipt")
    }

    private static func transactionDate(from lines: [String]) -> Date? {
        let text = lines.joined(separator: "\n")
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = detector.firstMatch(in: text, range: range),
               let date = match.date {
                return date
            }
        }
        return nil
    }

    private static func totalAmountMinor(from lines: [String], currencyCode: String) -> Int64 {
        let priorityTokens = [
            "grand total",
            "amount paid",
            "balance due",
            "total",
            "paid",
        ]
        for token in priorityTokens {
            if let amount = lines.reversed().compactMap({ line -> Int64? in
                guard line.lowercased().contains(token) else { return nil }
                return trailingAmountMinor(in: line, currencyCode: currencyCode)
            }).first, amount > 0 {
                return amount
            }
        }
        return lines.compactMap {
            trailingAmountMinor(in: $0, currencyCode: currencyCode)
        }.max() ?? 0
    }

    private static func lineItems(from lines: [String], currencyCode: String) -> [ReceiptExtractedLine] {
        var results: [ReceiptExtractedLine] = []
        var seen = Set<String>()
        for line in lines {
            guard !isSummaryLine(line),
                  let amount = trailingAmountMinor(in: line, currencyCode: currencyCode),
                  amount > 0
            else { continue }

            let title = titleBeforeTrailingAmount(in: line)
            guard title.count >= 2, title.rangeOfCharacter(from: .letters) != nil else { continue }
            let key = "\(title.normalizedReceiptSearchText)|\(amount)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            results.append(
                ReceiptExtractedLine(
                    title: title,
                    quantityText: quantityText(in: line),
                    amountMinor: amount
                )
            )
        }
        return Array(results.prefix(30))
    }

    private static func isSummaryLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        let ignored = [
            "total",
            "subtotal",
            "sub total",
            "tax",
            "gst",
            "vat",
            "change",
            "cash",
            "card",
            "visa",
            "mastercard",
            "balance",
            "round",
        ]
        return ignored.contains { lowered.contains($0) }
    }

    private static func trailingAmountMinor(in line: String, currencyCode: String) -> Int64? {
        let pattern = #"(?<!\d)(?:[$₹€£¥]?\s*)?(\d{1,3}(?:[,\s]\d{3})*(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges > 1
        else { return nil }
        let amountText = nsLine.substring(with: match.range(at: 1))
        let minor = MoneyParser.parseDisplayAmountMinor(
            from: amountText,
            currencyCode: currencyCode
        )
        return minor > 0 ? minor : nil
    }

    private static func titleBeforeTrailingAmount(in line: String) -> String {
        let pattern = #"(?<!\d)(?:[$₹€£¥]?\s*)?(\d{1,3}(?:[,\s]\d{3})*(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return line }
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: range) else { return line }
        return nsLine.substring(to: match.range.location)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -:\t"))
    }

    private static func quantityText(in line: String) -> String? {
        let pattern = #"(?i)(?:qty|quantity)?\s*(\d+(?:[.,]\d+)?)\s*(?:x|@|pcs|pc|ea|each)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges > 1
        else { return nil }
        return nsLine.substring(with: match.range(at: 1))
    }
}

private enum ReceiptAmountFormatter {
    static func displayText(minorUnits: Int64, currencyCode: String) -> String {
        let fractionDigits = MoneyFormatter.fractionDigits(for: currencyCode)
        let divisor = Decimal(pow(10.0, Double(fractionDigits)))
        let value = Decimal(minorUnits) / divisor
        return NSDecimalNumber(decimal: value).stringValue
    }
}

private struct ReceiptDocumentScanner: UIViewControllerRepresentable {
    static var isSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }

    let onComplete: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onComplete: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onComplete: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onComplete = onComplete
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            controller.dismiss(animated: true) {
                self.onComplete(images)
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true) {
                self.onCancel()
            }
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            controller.dismiss(animated: true) {
                self.onCancel()
            }
        }
    }
}

private extension Binding where Value == String? {
    var boundString: Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? "" },
            set: { wrappedValue = $0.nilIfBlankForReceiptCapture }
        )
    }
}

private extension String {
    var nilIfBlankForReceiptCapture: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedReceiptSearchText: String {
        String(lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
        )
            .split(separator: " ")
            .joined(separator: " ")
    }
}

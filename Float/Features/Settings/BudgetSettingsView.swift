import SwiftData
import SwiftUI

struct BudgetSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query private var allGoals: [GoalItem]
    @Query private var allRecurringRules: [RecurringRuleItem]
    @Query private var allBudgets: [BudgetPeriodItem]
    @Query(sort: \BudgetCycleItem.startDate, order: .reverse) private var allCycles: [BudgetCycleItem]
    @Query(sort: \CategoryItem.sortOrder) private var allCategories: [CategoryItem]
    @Query private var allCategoryBudgets: [CategoryBudgetItem]

    @State private var cadence: BudgetCadence = .monthly
    @State private var startDayOfMonth = 1
    @State private var startDayOfWeek = Calendar.current.firstWeekday
    @State private var expectedIncomeText = ""
    @State private var categoryBudgetTexts: [UUID: String] = [:]
    @State private var editingCategory: CategoryItem?
    @State private var message = ""
    @State private var periodTransactions: [TransactionItem] = []
    @State private var periodTransactionLoadFailed = false

    private var goals: [GoalItem] { filterActiveProfile(allGoals) }
    private var recurringRules: [RecurringRuleItem] { filterActiveProfile(allRecurringRules) }
    private var budgets: [BudgetPeriodItem] { filterActiveProfile(allBudgets) }
    private var cycles: [BudgetCycleItem] { filterActiveProfile(allCycles) }
    private var categories: [CategoryItem] { filterActiveProfile(allCategories) }
    private var categoryBudgets: [CategoryBudgetItem] { filterActiveProfile(allCategoryBudgets) }

    private var activeBudget: BudgetPeriodItem? {
        budgets.first { $0.isActive } ?? budgets.first
    }

    private var previewResult: SafeToSpendResult {
        SafeToSpendUseCase.calculate(
            period: BudgetPeriodCalculator.currentPeriod(
                cadence: cadence,
                startDayOfMonth: cadence == .monthly ? startDayOfMonth : nil,
                startDayOfWeek: cadence == .weekly ? startDayOfWeek : nil
            ),
            expectedIncomeMinor: previewExpectedIncomeMinor,
            transactions: periodTransactions,
            goals: goals,
            recurringRules: recurringRules
        )
    }

    private var previewExpectedIncomeMinor: Int64 {
        BudgetAmountField.minorUnits(
            fromMajorAmount: expectedIncomeText,
            currencyCode: appState.selectedCurrencyCode
        )
    }

    private var expenseCategories: [CategoryItem] {
        categories.filter { !$0.isIncome && !$0.archived }
    }

    private var categoryBudgetTotalMinor: Int64 {
        expenseCategories.reduce(Int64(0)) { total, category in
            total + categoryBudgetMinor(for: category)
        }
    }

    private var previewPeriod: BudgetPeriod {
        BudgetPeriodCalculator.currentPeriod(
            cadence: cadence,
            startDayOfMonth: cadence == .monthly ? startDayOfMonth : nil,
            startDayOfWeek: cadence == .weekly ? startDayOfWeek : nil
        )
    }

    private var budgetedCategoryCount: Int {
        expenseCategories.filter { categoryBudgetMinor(for: $0) > 0 }.count
    }

    private var unbudgetedCategoryCount: Int {
        max(0, expenseCategories.count - budgetedCategoryCount)
    }

    private var periodTransactionLoadKey: BudgetSettingsTransactionLoadKey {
        BudgetSettingsTransactionLoadKey(
            periodStart: previewPeriod.start,
            periodEnd: previewPeriod.end
        )
    }

    private var currentCycle: BudgetCycleItem? {
        cycles.first(where: { $0.status == .open }) ?? cycles.first
    }

    private var currentCycleEffectiveBudgetMinor: Int64 {
        currentCycle?.categories.reduce(Int64(0)) { partial, item in
            partial + item.effectiveBudgetMinor
        } ?? 0
    }

    private var currentCycleRolloverMinor: Int64 {
        currentCycle?.categories.reduce(Int64(0)) { partial, item in
            partial + item.rolloverInMinor
        } ?? 0
    }

    var body: some View {
        Form {
            Section("Period") {
                Picker("Cadence", selection: $cadence) {
                    ForEach(BudgetCadence.allCases) { cadence in
                        Text(cadence.title).tag(cadence)
                    }
                }
                .pickerStyle(.segmented)

                if cadence == .monthly {
                    Stepper(
                        "Starts on day \(startDayOfMonth)",
                        value: $startDayOfMonth,
                        in: 1...28
                    )
                } else {
                    Picker("Starts on", selection: $startDayOfWeek) {
                        ForEach(Self.weekdayOptions, id: \.value) { option in
                            Text(option.name).tag(option.value)
                        }
                    }
                }
            }

            Section {
                HStack {
                    TextField("Amount", text: $expectedIncomeText)
                        .keyboardType(.decimalPad)
                    CurrencyAmountPreview(
                        minorUnits: previewExpectedIncomeMinor,
                        currencyCode: appState.selectedCurrencyCode
                    )
                }
            } header: {
                Text("Expected income")
            } footer: {
                Text(
                    "Enter the normal currency amount for one budget period. For example, enter 60000 for ₹60,000."
                )
            }

            Section {
                if periodTransactionLoadFailed {
                    Button("Reload transactions", action: loadPeriodTransactions)
                }
                budgetRow("Expected income", previewResult.expectedIncomeMinor)
                budgetRow("Category budgets", categoryBudgetTotalMinor)
                budgetRow("Recurring due", previewResult.recurringDueMinor)
                budgetRow("Goals remaining", previewResult.goalContributionMinor)
                budgetRow("Spent so far", previewResult.variableSpentMinor)
                budgetRow("You can spend", previewResult.safeToSpendMinor)
            } header: {
                Text("Home preview")
            } footer: {
                Text(
                    "Home uses expected income minus recurring expenses, unfinished goal targets, and expenses already recorded this period."
                )
            }

            Section {
                if let currentCycle {
                    detailRow("Cycle window", currentCycleDateRange(currentCycle))
                    detailRow("Closeout status", currentCycle.status.title)
                    budgetRow("Cycle total", currentCycleEffectiveBudgetMinor)
                    if currentCycleRolloverMinor != 0 {
                        budgetRow("Rollover in", currentCycleRolloverMinor)
                    }
                } else {
                    Text("Save a budget to create the first cycle.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Current cycle")
            }

            Section {
                if expenseCategories.isEmpty {
                    Text("Add expense categories before setting category budgets.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    budgetRow("Allocated", categoryBudgetTotalMinor)
                    HStack {
                        Text("Budgeted categories")
                        Spacer()
                        Text("\(budgetedCategoryCount)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Unbudgeted")
                        Spacer()
                        Text("\(unbudgetedCategoryCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Category budget summary")
            }

            Section {
                if expenseCategories.isEmpty {
                    Text("Add expense categories before setting category budgets.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(expenseCategories) { category in
                        categoryBudgetRow(category)
                    }
                }
            } header: {
                Text("Category budgets")
            } footer: {
                Text("Set an amount for each expense category in one budget period. Leave a category blank or enter 0 to remove its budget.")
            }

            if !message.isEmpty {
                Section {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Budget")
        .keyboardDismissControls()
        .scrollContentBackground(.hidden)
        .floatBackground()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
        .onAppear(perform: configure)
        .task(id: periodTransactionLoadKey) {
            loadPeriodTransactions()
        }
        .sheet(item: $editingCategory) { category in
            CategoryBudgetEditorSheet(
                category: category,
                initialAmountMinor: categoryBudgetMinor(for: category),
                initialRolloverPolicy: categoryBudgetPolicy(for: category),
                otherBudgetMinor: max(
                    0,
                    categoryBudgetTotalMinor - categoryBudgetMinor(for: category)
                ),
                expectedIncomeMinor: previewExpectedIncomeMinor,
                spentMinor: categorySpentMinor(for: category),
                currencyCode: appState.selectedCurrencyCode
            ) { amountMinor, rolloverPolicy in
                saveCategoryBudget(
                    category,
                    amountMinor: amountMinor,
                    rolloverPolicy: rolloverPolicy
                )
            }
        }
    }

    private static let weekdayOptions: [(name: String, value: Int)] = [
        ("Sunday", 1),
        ("Monday", 2),
        ("Tuesday", 3),
        ("Wednesday", 4),
        ("Thursday", 5),
        ("Friday", 6),
        ("Saturday", 7),
    ]

    private func budgetRow(_ title: String, _ amount: Int64) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(
                MoneyFormatter.string(
                    minorUnits: amount,
                    currencyCode: appState.selectedCurrencyCode
                )
            )
            .foregroundStyle(.secondary)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func categoryBudgetRow(_ category: CategoryItem) -> some View {
        let budgetMinor = categoryBudgetMinor(for: category)
        let spentMinor = categorySpentMinor(for: category)
        let remainingMinor = max(0, budgetMinor - spentMinor)
        let progress = budgetMinor == 0 ? 0 : Double(spentMinor) / Double(budgetMinor)

        return Button {
            editingCategory = category
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 12) {
                    Image(systemName: category.iconKey)
                        .font(.headline)
                        .foregroundStyle(Color(hex: category.colorHex))
                        .frame(width: 34, height: 34)
                        .background(Color(hex: category.colorHex).opacity(0.14), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(category.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(categoryBudgetDetail(
                            budgetMinor: budgetMinor,
                            spentMinor: spentMinor,
                            remainingMinor: remainingMinor
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        Text(categoryBudgetPolicyText(for: category))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(budgetMinor > 0 ? money(budgetMinor) : "Not set")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(budgetMinor > 0 ? .primary : .secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }

                if budgetMinor > 0 {
                    ProgressView(value: min(max(progress, 0), 1))
                        .tint(spentMinor > budgetMinor ? Color(hex: "#B4613B") : Color(hex: category.colorHex))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func categoryBudgetMinor(for category: CategoryItem) -> Int64 {
        BudgetAmountField.minorUnits(
            fromMajorAmount: categoryBudgetTexts[category.id, default: ""],
            currencyCode: appState.selectedCurrencyCode
        )
    }

    private func categoryBudgetPolicy(for category: CategoryItem) -> BudgetRolloverPolicy {
        categoryBudgets.first(where: { $0.category?.id == category.id })?.rolloverPolicy ?? .none
    }

    private func categorySpentMinor(for category: CategoryItem) -> Int64 {
        periodTransactions
            .filter {
                $0.isExpense
                    && $0.category?.id == category.id
                    && previewPeriod.contains($0.timestamp, calendar: .current)
            }
            .reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    private func categoryBudgetDetail(
        budgetMinor: Int64,
        spentMinor: Int64,
        remainingMinor: Int64
    ) -> String {
        guard budgetMinor > 0 else {
            return "Tap to add a category budget"
        }
        if spentMinor > budgetMinor {
            return "Spent \(money(spentMinor)) · over by \(money(spentMinor - budgetMinor))"
        }
        return "Spent \(money(spentMinor)) · \(money(remainingMinor)) left"
    }

    private func categoryBudgetPolicyText(for category: CategoryItem) -> String {
        AppLocalization.format(
            "Rollover: %@",
            categoryBudgetPolicy(for: category).title
        )
    }

    private func currentCycleDateRange(_ cycle: BudgetCycleItem) -> String {
        AppLocalization.format(
            "%@ - %@",
            cycle.startDate.formatted(date: .abbreviated, time: .omitted),
            cycle.endDate.formatted(date: .abbreviated, time: .omitted)
        )
    }

    private func money(_ amount: Int64) -> String {
        MoneyFormatter.string(
            minorUnits: amount,
            currencyCode: appState.selectedCurrencyCode
        )
    }

    private func configure() {
        guard let budget = activeBudget else {
            expectedIncomeText = ""
            configureCategoryBudgets()
            return
        }
        cadence = budget.cadence
        startDayOfMonth = budget.startDayOfMonth ?? 1
        startDayOfWeek = budget.startDayOfWeek ?? Calendar.current.firstWeekday
        expectedIncomeText = BudgetAmountField.majorAmountString(
            minorUnits: budget.expectedIncomeMinor,
            currencyCode: budget.currencyCode
        )
        configureCategoryBudgets()
    }

    private func configureCategoryBudgets() {
        var values: [UUID: String] = [:]
        for budget in categoryBudgets where budget.isActive {
            guard let category = budget.category else { continue }
            values[category.id] = BudgetAmountField.majorAmountString(
                minorUnits: budget.amountMinor,
                currencyCode: budget.currencyCode
            )
        }
        categoryBudgetTexts = values
    }

    private func loadPeriodTransactions() {
        let period = previewPeriod
        let start = period.start
        let end = Self.endOfDay(for: period.end, calendar: .current)

        do {
            let descriptor = FetchDescriptor<TransactionItem>(
                predicate: #Predicate<TransactionItem> { transaction in
                    transaction.timestamp >= start && transaction.timestamp <= end
                },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            periodTransactions = filterActiveProfile(try modelContext.fetch(descriptor))
            periodTransactionLoadFailed = false
        } catch {
            periodTransactions = []
            periodTransactionLoadFailed = true
        }
    }

    private static func endOfDay(for date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: start
        ) ?? date
    }

    private func save() {
        let budget = activeBudget ?? BudgetPeriodItem(
            currencyCode: appState.selectedCurrencyCode
        )
        if budget.modelContext == nil {
            modelContext.insert(budget)
        }
        for item in budgets where item.id != budget.id {
            item.isActive = false
        }
        budget.cadence = cadence
        budget.startDayOfMonth = cadence == .monthly ? startDayOfMonth : nil
        budget.startDayOfWeek = cadence == .weekly ? startDayOfWeek : nil
        budget.expectedIncomeMinor = previewExpectedIncomeMinor
        budget.currencyCode = appState.selectedCurrencyCode
        budget.isActive = true
        budget.updatedAt = Date()
        saveCategoryBudgets()
        BudgetCycleUseCase.syncCurrentCycle(
            modelContext: modelContext,
            profileID: ActiveProfileRegistry.profileID
        )
        try? modelContext.save()
        message = String(localized: "Budget saved.")
    }

    private func saveCategoryBudgets() {
        let repository = CategoryBudgetRepository(modelContext: modelContext)
        for category in expenseCategories {
            try? repository.save(
                category: category,
                amountMinor: categoryBudgetMinor(for: category),
                rolloverPolicy: categoryBudgetPolicy(for: category),
                currencyCode: appState.selectedCurrencyCode,
                existingBudgets: categoryBudgets
            )
        }
    }

    private func saveCategoryBudget(
        _ category: CategoryItem,
        amountMinor: Int64,
        rolloverPolicy: BudgetRolloverPolicy
    ) {
        categoryBudgetTexts[category.id] = amountMinor > 0
            ? BudgetAmountField.majorAmountString(
                minorUnits: amountMinor,
                currencyCode: appState.selectedCurrencyCode
            )
            : ""
        try? CategoryBudgetRepository(modelContext: modelContext).save(
            category: category,
            amountMinor: amountMinor,
            rolloverPolicy: rolloverPolicy,
            currencyCode: appState.selectedCurrencyCode,
            existingBudgets: categoryBudgets
        )
        BudgetCycleUseCase.syncCurrentCycle(
            modelContext: modelContext,
            profileID: ActiveProfileRegistry.profileID
        )
        message = amountMinor > 0
            ? AppLocalization.format("%@ budget saved.", category.name)
            : AppLocalization.format("%@ budget cleared.", category.name)
    }
}

private struct BudgetSettingsTransactionLoadKey: Hashable {
    let periodStart: Date
    let periodEnd: Date
}

private struct CategoryBudgetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let category: CategoryItem
    let initialAmountMinor: Int64
    let initialRolloverPolicy: BudgetRolloverPolicy
    let otherBudgetMinor: Int64
    let expectedIncomeMinor: Int64
    let spentMinor: Int64
    let currencyCode: String
    let onSave: (Int64, BudgetRolloverPolicy) -> Void

    @State private var amountText: String
    @State private var rolloverPolicy: BudgetRolloverPolicy

    init(
        category: CategoryItem,
        initialAmountMinor: Int64,
        initialRolloverPolicy: BudgetRolloverPolicy,
        otherBudgetMinor: Int64,
        expectedIncomeMinor: Int64,
        spentMinor: Int64,
        currencyCode: String,
        onSave: @escaping (Int64, BudgetRolloverPolicy) -> Void
    ) {
        self.category = category
        self.initialAmountMinor = initialAmountMinor
        self.initialRolloverPolicy = initialRolloverPolicy
        self.otherBudgetMinor = otherBudgetMinor
        self.expectedIncomeMinor = expectedIncomeMinor
        self.spentMinor = spentMinor
        self.currencyCode = currencyCode
        self.onSave = onSave
        _amountText = State(
            initialValue: initialAmountMinor > 0
                ? BudgetAmountField.majorAmountString(
                    minorUnits: initialAmountMinor,
                    currencyCode: currencyCode
                )
                : ""
        )
        _rolloverPolicy = State(initialValue: initialRolloverPolicy)
    }

    private var amountMinor: Int64 {
        BudgetAmountField.minorUnits(
            fromMajorAmount: amountText,
            currencyCode: currencyCode
        )
    }

    private var totalBudgetMinor: Int64 {
        otherBudgetMinor + amountMinor
    }

    private var share: Double {
        guard totalBudgetMinor > 0 else { return 0 }
        return Double(amountMinor) / Double(totalBudgetMinor)
    }

    private var incomeShare: Double {
        guard expectedIncomeMinor > 0 else { return 0 }
        return Double(amountMinor) / Double(expectedIncomeMinor)
    }

    private var spentProgress: Double {
        guard amountMinor > 0 else { return 0 }
        return Double(spentMinor) / Double(amountMinor)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: category.iconKey)
                            .font(.headline)
                            .foregroundStyle(Color(hex: category.colorHex))
                            .frame(width: 42, height: 42)
                            .background(
                                Color(hex: category.colorHex).opacity(0.14),
                                in: Circle()
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.name)
                                .font(.headline)
                            Text("Set a budget for one budget period.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    HStack {
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                        CurrencyAmountPreview(
                            minorUnits: amountMinor,
                            currencyCode: currencyCode
                        )
                    }
                } header: {
                    Text("Budget amount")
                } footer: {
                    Text("Enter the normal currency amount for this category.")
                }

                Section("Rollover policy") {
                    Picker("Rollover policy", selection: $rolloverPolicy) {
                        ForEach(BudgetRolloverPolicy.allCases) { policy in
                            Text(policy.title)
                                .tag(policy)
                        }
                    }
                }

                Section("Allocation share") {
                    AllocationShareGraph(
                        categoryName: category.name,
                        categoryColor: Color(hex: category.colorHex),
                        amountMinor: amountMinor,
                        totalBudgetMinor: totalBudgetMinor,
                        share: share,
                        title: "of category budgets",
                        totalTitle: "Category total",
                        emptyTitle: "No category budget total yet",
                        emptyMessage: "Set this amount or other category budgets to see its category allocation share.",
                        currencyCode: currencyCode
                    )
                    AllocationShareGraph(
                        categoryName: category.name,
                        categoryColor: Color(hex: category.colorHex),
                        amountMinor: amountMinor,
                        totalBudgetMinor: expectedIncomeMinor,
                        share: incomeShare,
                        title: "of expected income",
                        totalTitle: "Expected income",
                        emptyTitle: "Expected income is not set",
                        emptyMessage: "Set expected income on the Budget screen to compare this category against income.",
                        currencyCode: currencyCode
                    )
                }

                Section("This period") {
                    editorRow("Budget", amountMinor)
                    editorRow("Spent", spentMinor)
                    editorRow("Remaining", max(0, amountMinor - spentMinor))
                    if amountMinor > 0 {
                        ProgressView(value: min(max(spentProgress, 0), 1))
                            .tint(
                                spentMinor > amountMinor
                                    ? Color(hex: "#B4613B")
                                    : Color(hex: category.colorHex)
                            )
                    }
                }

                if initialAmountMinor > 0 {
                    Section {
                        Button("Clear budget", role: .destructive) {
                            onSave(0, rolloverPolicy)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Category Budget")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissControls()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(amountMinor, rolloverPolicy)
                        dismiss()
                    }
                }
            }
        }
    }

    private func editorRow(_ title: String, _ amount: Int64) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(MoneyFormatter.string(minorUnits: amount, currencyCode: currencyCode))
                .foregroundStyle(.secondary)
        }
    }
}

private struct AllocationShareGraph: View {
    let categoryName: String
    let categoryColor: Color
    let amountMinor: Int64
    let totalBudgetMinor: Int64
    let share: Double
    let title: String
    let totalTitle: String
    let emptyTitle: String
    let emptyMessage: String
    let currencyCode: String

    private var shareText: String {
        guard share > 0 else { return "0%" }
        let rounded = Int((min(max(share, 0), 1) * 100).rounded())
        return rounded == 0 ? "<1%" : "\(rounded)%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(shareText)
                        .font(.title2.weight(.bold))
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(
                    MoneyFormatter.string(
                        minorUnits: amountMinor,
                        currencyCode: currencyCode
                    )
                )
                .moneyStyle(size: 16, weight: .semibold)
            }

            if totalBudgetMinor > 0 {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                        if share > 0 {
                            Capsule()
                                .fill(categoryColor.gradient)
                                .frame(width: max(4, proxy.size.width * CGFloat(min(max(share, 0), 1))))
                        }
                    }
                }
                .frame(height: 14)

                HStack(spacing: 8) {
                    Circle()
                        .fill(categoryColor)
                        .frame(width: 8, height: 8)
                    Text(categoryName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(
                        "\(totalTitle) \(MoneyFormatter.string(minorUnits: totalBudgetMinor, currencyCode: currencyCode))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }
            } else {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

enum BudgetAmountField {
    static func minorUnits(fromMajorAmount text: String, currencyCode: String)
        -> Int64
    {
        let normalized = text.replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decimal = Decimal(string: normalized), decimal > 0 else {
            return 0
        }
        let scale = Decimal(
            pow(10.0, Double(MoneyFormatter.fractionDigits(for: currencyCode)))
        )
        let minorDecimal = decimal * scale
        return NSDecimalNumber(decimal: minorDecimal).rounding(
            accordingToBehavior: nil
        ).int64Value
    }

    static func majorAmountString(minorUnits: Int64, currencyCode: String)
        -> String
    {
        let fractionDigits = MoneyFormatter.fractionDigits(for: currencyCode)
        let divisor = Decimal(pow(10.0, Double(fractionDigits)))
        let major = Decimal(minorUnits) / divisor
        return NSDecimalNumber(decimal: major).stringValue
    }
}

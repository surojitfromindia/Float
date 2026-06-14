import Foundation
import SwiftData

enum DataIntegrityError: LocalizedError {
    case saveFailed
    case missingRequiredAccount
    case missingRequiredCategory

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            "Float could not save the latest changes."
        case .missingRequiredAccount:
            "Float could not find an account for this transaction."
        case .missingRequiredCategory:
            "Float could not find a category for this transaction."
        }
    }
}

enum DefaultAccountResolver {
    @MainActor
    static func resolve(
        preferredID: String?,
        accounts: [AccountItem],
        modelContext: ModelContext,
        currencyCode: String
    ) -> AccountItem {
        if let preferredID,
           let match = accounts.first(where: {
               !$0.archived && $0.id.uuidString == preferredID
           }) {
            return match
        }

        if let cash = accounts.first(where: {
            !$0.archived && $0.name.localizedCaseInsensitiveCompare("Cash") == .orderedSame
        }) {
            return cash
        }

        if let firstActive = accounts.first(where: { !$0.archived }) {
            return firstActive
        }

        let account = AccountItem(
            name: "Cash",
            type: .cash,
            currencyCode: currencyCode
        )
        modelContext.insert(account)
        return account
    }
}

enum DefaultCategoryResolver {
    @MainActor
    static func resolve(
        isExpense: Bool,
        preferredID: String?,
        categories: [CategoryItem],
        modelContext: ModelContext
    ) -> CategoryItem {
        let wantsIncome = !isExpense

        if let preferredID,
           let match = categories.first(where: {
               !$0.archived && $0.isIncome == wantsIncome && $0.id.uuidString == preferredID
           }) {
            return match
        }

        if isExpense,
           let other = categories.first(where: {
               !$0.archived && !$0.isIncome
                   && $0.name.localizedCaseInsensitiveCompare("Other") == .orderedSame
           }) {
            return other
        }

        if !isExpense,
           let salary = categories.first(where: {
               !$0.archived && $0.isIncome
                   && $0.name.localizedCaseInsensitiveCompare("Salary") == .orderedSame
           }) {
            return salary
        }

        if let firstActive = categories.first(where: {
            !$0.archived && $0.isIncome == wantsIncome
        }) {
            return firstActive
        }

        let fallback = fallbackCategory(isExpense: isExpense, sortOrder: categories.count)
        modelContext.insert(fallback)
        return fallback
    }

    private static func fallbackCategory(
        isExpense: Bool,
        sortOrder: Int
    ) -> CategoryItem {
        CategoryItem(
            name: isExpense ? "Other" : "Salary",
            iconKey: isExpense ? "square.grid.2x2.fill" : "banknote.fill",
            colorHex: isExpense ? "#5A6B6B" : "#57C98C",
            isIncome: !isExpense,
            sortOrder: sortOrder,
            isDefault: true
        )
    }
}

enum SeedDataService {
    @MainActor
    static func ensureSeedData(modelContext: ModelContext, currencyCode: String) {
        DataIntegrityService.repair(modelContext: modelContext, currencyCode: currencyCode)
    }

    @MainActor
    @discardableResult
    static func seedLargeTransactionHistory(
        modelContext: ModelContext,
        currencyCode: String
    ) throws -> SeededDataSummary {
        DataIntegrityService.repair(modelContext: modelContext, currencyCode: currencyCode)

        let categorySeed = SeedData.defaultCategories
        var categories = (try? modelContext.fetch(FetchDescriptor<CategoryItem>())) ?? []
        var accounts = (try? modelContext.fetch(FetchDescriptor<AccountItem>())) ?? []

        let cash = ensureAccount(
            named: "Cash",
            type: .cash,
            openingBalanceMinor: 18_000,
            currencyCode: currencyCode,
            accounts: &accounts,
            modelContext: modelContext
        )
        let checking = ensureAccount(
            named: "Checking",
            type: .bank,
            openingBalanceMinor: 210_000,
            currencyCode: currencyCode,
            accounts: &accounts,
            modelContext: modelContext
        )
        let savings = ensureAccount(
            named: "Savings",
            type: .bank,
            openingBalanceMinor: 640_000,
            currencyCode: currencyCode,
            accounts: &accounts,
            modelContext: modelContext
        )
        let card = ensureAccount(
            named: "Credit Card",
            type: .card,
            openingBalanceMinor: 0,
            currencyCode: currencyCode,
            accounts: &accounts,
            modelContext: modelContext
        )
        let wallet = ensureAccount(
            named: "Wallet",
            type: .wallet,
            openingBalanceMinor: 38_000,
            currencyCode: currencyCode,
            accounts: &accounts,
            modelContext: modelContext
        )

        for (index, item) in categorySeed.enumerated() {
            _ = ensureCategory(
                named: item.0,
                iconKey: item.1,
                colorHex: item.2,
                isIncome: item.3,
                sortOrder: index,
                categories: &categories,
                modelContext: modelContext
            )
        }

        let expensePlans = SeedExpensePlan.defaults.compactMap { plan in
            categories.first {
                !$0.archived
                    && !$0.isIncome
                    && $0.name.localizedCaseInsensitiveCompare(plan.categoryName) == .orderedSame
            }.map { (plan, $0) }
        }
        let salaryCategory = incomeCategory(named: "Salary", categories: categories)
        let freelanceCategory = incomeCategory(named: "Freelance", categories: categories)
        let bonusCategory = incomeCategory(named: "Bonus", categories: categories)
        let refundCategory = incomeCategory(named: "Refund", categories: categories)
        let spendingAccounts = [cash, checking, card, wallet]
        let transferAccounts = [checking, savings, wallet, cash]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .year, value: -2, to: today) ?? today
        let firstMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: startDate)
        ) ?? startDate
        var rng = SeededRandomNumberGenerator(seed: UInt64(today.timeIntervalSince1970))
        var insertedTransactions = 0
        var insertedTransfers = 0

        for monthOffset in 0..<24 {
            guard let monthDate = calendar.date(byAdding: .month, value: monthOffset, to: firstMonth) else {
                continue
            }

            let seedDays = randomSeedDays(
                in: monthDate,
                calendar: calendar,
                rng: &rng
            )

            for (dayIndex, day) in seedDays.enumerated() {
                guard let currentDate = calendar.date(bySetting: .day, value: day, of: monthDate) else {
                    continue
                }

                let dailyCount = 5 + Int.random(in: 0...1, using: &rng)

                for index in 0..<dailyCount {
                    if index == 0 {
                        let primaryTransaction = monthlyPrimaryTransaction(
                            monthOffset: monthOffset,
                            dayIndex: dayIndex,
                            currentDate: currentDate,
                            checking: checking,
                            savings: savings,
                            expensePlans: expensePlans,
                            salaryCategory: salaryCategory,
                            freelanceCategory: freelanceCategory,
                            bonusCategory: bonusCategory,
                            refundCategory: refundCategory,
                            rng: &rng
                        )
                        modelContext.insert(primaryTransaction)
                    } else {
                        guard let item = expensePlans.randomElement(using: &rng) else { continue }
                        let account = spendingAccounts.randomElement(using: &rng) ?? checking
                        let amount = item.0.randomAmount(using: &rng)
                        let timestamp = timestamp(
                            on: currentDate,
                            hour: min(item.0.hour + index, 23),
                            minute: Int.random(in: 0...54, using: &rng)
                        )
                        modelContext.insert(
                            TransactionItem(
                                amountMinor: amount,
                                isExpense: true,
                                timestamp: timestamp,
                                category: item.1,
                                account: account,
                                note: item.0.randomNote(using: &rng)
                            )
                        )
                    }
                    insertedTransactions += 1
                }

                if dayIndex == 1 && monthOffset % 3 == 0 {
                    let from = transferAccounts.randomElement(using: &rng) ?? checking
                    let to = transferAccounts.first { $0.id != from.id } ?? savings
                    modelContext.insert(
                        TransferItem(
                            amountMinor: 10_000 + Int64.random(in: 0...30_000, using: &rng),
                            fromAccount: from,
                            toAccount: to,
                            timestamp: timestamp(on: currentDate, hour: 18, minute: 30),
                            note: "Account transfer"
                        )
                    )
                    insertedTransfers += 1
                }
            }
        }

        try modelContext.save()
        return SeededDataSummary(
            transactionCount: insertedTransactions,
            transferCount: insertedTransfers
        )
    }

    @MainActor
    private static func ensureAccount(
        named name: String,
        type: AccountType,
        openingBalanceMinor: Int64,
        currencyCode: String,
        accounts: inout [AccountItem],
        modelContext: ModelContext
    ) -> AccountItem {
        if let account = accounts.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
                && $0.currencyCode == currencyCode
        }) {
            account.archived = false
            account.type = type
            account.updatedAt = Date()
            return account
        }

        let account = AccountItem(
            name: name,
            type: type,
            openingBalanceMinor: openingBalanceMinor,
            currencyCode: currencyCode
        )
        modelContext.insert(account)
        accounts.append(account)
        return account
    }

    @MainActor
    private static func ensureCategory(
        named name: String,
        iconKey: String,
        colorHex: String,
        isIncome: Bool,
        sortOrder: Int,
        categories: inout [CategoryItem],
        modelContext: ModelContext
    ) -> CategoryItem {
        if let category = categories.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
                && $0.isIncome == isIncome
        }) {
            category.archived = false
            category.updatedAt = Date()
            return category
        }

        let category = CategoryItem(
            name: name,
            iconKey: iconKey,
            colorHex: colorHex,
            isIncome: isIncome,
            sortOrder: sortOrder,
            isDefault: true
        )
        modelContext.insert(category)
        categories.append(category)
        return category
    }

    private static func incomeCategory(
        named name: String,
        categories: [CategoryItem]
    ) -> CategoryItem? {
        categories.first {
            !$0.archived
                && $0.isIncome
                && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    private static func randomSeedDays(
        in monthDate: Date,
        calendar: Calendar,
        rng: inout SeededRandomNumberGenerator
    ) -> [Int] {
        guard let dayRange = calendar.range(of: .day, in: .month, for: monthDate) else {
            return [1, 8, 15, 22]
        }

        var selected = Set<Int>()
        while selected.count < 4 {
            selected.insert(Int.random(in: dayRange, using: &rng))
        }

        return selected.sorted()
    }

    private static func monthlyPrimaryTransaction(
        monthOffset: Int,
        dayIndex: Int,
        currentDate: Date,
        checking: AccountItem,
        savings: AccountItem,
        expensePlans: [(SeedExpensePlan, CategoryItem)],
        salaryCategory: CategoryItem?,
        freelanceCategory: CategoryItem?,
        bonusCategory: CategoryItem?,
        refundCategory: CategoryItem?,
        rng: inout SeededRandomNumberGenerator
    ) -> TransactionItem {
        switch dayIndex {
        case 0:
            return TransactionItem(
                amountMinor: 420_000 + Int64.random(in: 0...85_000, using: &rng),
                isExpense: false,
                timestamp: timestamp(on: currentDate, hour: 9, minute: 15),
                category: salaryCategory,
                account: checking,
                note: "Monthly salary"
            )
        case 1 where monthOffset % 2 == 0:
            return TransactionItem(
                amountMinor: 55_000 + Int64.random(in: 0...35_000, using: &rng),
                isExpense: false,
                timestamp: timestamp(on: currentDate, hour: 14, minute: 10),
                category: freelanceCategory,
                account: checking,
                note: "Freelance project"
            )
        case 2 where monthOffset % 3 == 0:
            return TransactionItem(
                amountMinor: 25_000 + Int64.random(in: 0...75_000, using: &rng),
                isExpense: false,
                timestamp: timestamp(on: currentDate, hour: 10, minute: 35),
                category: bonusCategory,
                account: savings,
                note: "Bonus"
            )
        case 3 where monthOffset % 4 == 0:
            return TransactionItem(
                amountMinor: 1_500 + Int64.random(in: 0...12_000, using: &rng),
                isExpense: false,
                timestamp: timestamp(on: currentDate, hour: 16, minute: 5),
                category: refundCategory,
                account: checking,
                note: "Refund"
            )
        default:
            guard let item = expensePlans.randomElement(using: &rng) else {
                return TransactionItem(
                    amountMinor: 1_000,
                    isExpense: true,
                    timestamp: timestamp(on: currentDate, hour: 12, minute: 0),
                    category: nil,
                    account: checking,
                    note: "Expense"
                )
            }
            return TransactionItem(
                amountMinor: item.0.randomAmount(using: &rng),
                isExpense: true,
                timestamp: timestamp(
                    on: currentDate,
                    hour: item.0.hour,
                    minute: Int.random(in: 0...54, using: &rng)
                ),
                category: item.1,
                account: checking,
                note: item.0.randomNote(using: &rng)
            )
        }
    }

    private static func timestamp(on date: Date, hour: Int, minute: Int) -> Date {
        Calendar.current.date(
            bySettingHour: min(hour, 23),
            minute: min(max(minute, 0), 59),
            second: 0,
            of: date
        ) ?? date
    }
}

struct SeededDataSummary {
    let transactionCount: Int
    let transferCount: Int
}

private struct SeedExpensePlan {
    let categoryName: String
    let notes: [String]
    let minAmountMinor: Int64
    let maxAmountMinor: Int64
    let hour: Int

    func randomAmount(using rng: inout SeededRandomNumberGenerator) -> Int64 {
        Int64.random(in: minAmountMinor...maxAmountMinor, using: &rng)
    }

    func randomNote(using rng: inout SeededRandomNumberGenerator) -> String {
        notes.randomElement(using: &rng) ?? categoryName
    }

    static let defaults: [SeedExpensePlan] = [
        SeedExpensePlan(categoryName: "Food", notes: ["Breakfast", "Lunch", "Snacks", "Coffee"], minAmountMinor: 250, maxAmountMinor: 3_500, hour: 8),
        SeedExpensePlan(categoryName: "Transport", notes: ["Cab", "Metro", "Bus pass", "Parking"], minAmountMinor: 180, maxAmountMinor: 5_200, hour: 9),
        SeedExpensePlan(categoryName: "Bills", notes: ["Phone bill", "Water bill", "Service charge"], minAmountMinor: 1_200, maxAmountMinor: 18_000, hour: 11),
        SeedExpensePlan(categoryName: "Groceries", notes: ["Weekly groceries", "Fresh produce", "Household supplies"], minAmountMinor: 1_500, maxAmountMinor: 14_000, hour: 17),
        SeedExpensePlan(categoryName: "Shopping", notes: ["Clothes", "Accessories", "Online order"], minAmountMinor: 900, maxAmountMinor: 28_000, hour: 19),
        SeedExpensePlan(categoryName: "Health", notes: ["Pharmacy", "Doctor visit", "Vitamins"], minAmountMinor: 700, maxAmountMinor: 22_000, hour: 12),
        SeedExpensePlan(categoryName: "Entertainment", notes: ["Movie", "Streaming", "Games", "Concert"], minAmountMinor: 600, maxAmountMinor: 12_500, hour: 20),
        SeedExpensePlan(categoryName: "Rent", notes: ["Monthly rent"], minAmountMinor: 85_000, maxAmountMinor: 145_000, hour: 10),
        SeedExpensePlan(categoryName: "Utilities", notes: ["Electricity", "Gas", "Maintenance"], minAmountMinor: 2_500, maxAmountMinor: 24_000, hour: 13),
        SeedExpensePlan(categoryName: "Internet", notes: ["Broadband", "Mobile data"], minAmountMinor: 900, maxAmountMinor: 5_500, hour: 14),
        SeedExpensePlan(categoryName: "Fuel", notes: ["Fuel", "Charging", "Vehicle wash"], minAmountMinor: 1_000, maxAmountMinor: 9_000, hour: 16),
        SeedExpensePlan(categoryName: "Travel", notes: ["Hotel", "Train ticket", "Flight add-on"], minAmountMinor: 4_000, maxAmountMinor: 65_000, hour: 15),
        SeedExpensePlan(categoryName: "Education", notes: ["Course", "Books", "Workshop"], minAmountMinor: 1_500, maxAmountMinor: 40_000, hour: 18),
        SeedExpensePlan(categoryName: "Subscriptions", notes: ["Music plan", "Cloud storage", "App subscription"], minAmountMinor: 199, maxAmountMinor: 4_500, hour: 7),
        SeedExpensePlan(categoryName: "Dining", notes: ["Dinner", "Cafe", "Takeout"], minAmountMinor: 800, maxAmountMinor: 9_500, hour: 21),
        SeedExpensePlan(categoryName: "Fitness", notes: ["Gym", "Yoga class", "Sports gear"], minAmountMinor: 900, maxAmountMinor: 11_000, hour: 6),
        SeedExpensePlan(categoryName: "Maintenance", notes: ["Repairs", "Cleaning", "Tools"], minAmountMinor: 500, maxAmountMinor: 18_000, hour: 12),
        SeedExpensePlan(categoryName: "Insurance", notes: ["Health insurance", "Vehicle insurance"], minAmountMinor: 8_000, maxAmountMinor: 45_000, hour: 10),
        SeedExpensePlan(categoryName: "Gifts", notes: ["Birthday gift", "Donation", "Celebration"], minAmountMinor: 700, maxAmountMinor: 25_000, hour: 18),
        SeedExpensePlan(categoryName: "Other", notes: ["Miscellaneous", "Cash adjustment", "Small purchase"], minAmountMinor: 100, maxAmountMinor: 8_000, hour: 13),
    ]
}

private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

enum DataIntegrityService {
    private static let personCountsBackfilledKey = "personCountsBackfilledV1"

    @MainActor
    static func repair(modelContext: ModelContext, currencyCode: String) {
        let now = Date()
        let categories = (try? modelContext.fetch(FetchDescriptor<CategoryItem>())) ?? []
        ensureDefaultCategories(
            existingCategories: categories,
            modelContext: modelContext
        )

        let accounts = (try? modelContext.fetch(FetchDescriptor<AccountItem>())) ?? []
        _ = DefaultAccountResolver.resolve(
            preferredID: nil,
            accounts: accounts,
            modelContext: modelContext,
            currencyCode: currencyCode
        )

        let budgets = (try? modelContext.fetch(FetchDescriptor<BudgetPeriodItem>())) ?? []
        if budgets.isEmpty {
            modelContext.insert(BudgetPeriodItem(currencyCode: currencyCode))
        } else if budgets.allSatisfy({ !$0.isActive }), let first = budgets.first {
            first.isActive = true
            first.updatedAt = now
        }

        repairAmountsAndDates(modelContext: modelContext, now: now)
        let didBackfillPersonCounts = backfillPersonCountsIfNeeded(modelContext: modelContext)

        if (try? modelContext.save()) != nil, didBackfillPersonCounts {
            UserDefaults.standard.set(true, forKey: personCountsBackfilledKey)
        }
    }

    @MainActor
    private static func ensureDefaultCategories(
        existingCategories: [CategoryItem],
        modelContext: ModelContext
    ) {
        for (index, item) in SeedData.defaultCategories.enumerated() {
            let exists = existingCategories.contains {
                $0.name.localizedCaseInsensitiveCompare(item.0) == .orderedSame
                    && $0.isIncome == item.3
            }

            guard !exists else { continue }
            modelContext.insert(
                CategoryItem(
                    name: item.0,
                    iconKey: item.1,
                    colorHex: item.2,
                    isIncome: item.3,
                    sortOrder: index,
                    isDefault: true
                )
            )
        }
    }

    @MainActor
    private static func repairAmountsAndDates(modelContext: ModelContext, now: Date) {
        let transactions = (try? modelContext.fetch(FetchDescriptor<TransactionItem>())) ?? []
        for transaction in transactions {
            transaction.amountMinor = normalizedMoney(transaction.amountMinor)
            if transaction.updatedAt < transaction.createdAt {
                transaction.updatedAt = transaction.createdAt
            }
        }

        let templates =
            (try? modelContext.fetch(FetchDescriptor<TransactionTemplateItem>())) ?? []
        for template in templates {
            template.amountMinor = normalizedMoney(template.amountMinor)
            if template.updatedAt < template.createdAt {
                template.updatedAt = template.createdAt
            }
        }

        let recurringRules = (try? modelContext.fetch(FetchDescriptor<RecurringRuleItem>())) ?? []
        for rule in recurringRules {
            rule.amountMinor = normalizedMoney(rule.amountMinor)
            rule.intervalCount = max(1, rule.intervalCount)
            if rule.updatedAt < rule.createdAt {
                rule.updatedAt = rule.createdAt
            }
            if let endDate = rule.endDate, endDate < rule.nextRunDate {
                rule.active = false
                rule.updatedAt = now
            }
        }

        let goals = (try? modelContext.fetch(FetchDescriptor<GoalItem>())) ?? []
        for goal in goals {
            goal.targetMinor = normalizedMoney(goal.targetMinor)
            goal.savedMinor = normalizedMoney(goal.savedMinor)
            goal.achieved = goal.savedMinor >= goal.targetMinor && goal.targetMinor > 0
            if goal.updatedAt < goal.createdAt {
                goal.updatedAt = goal.createdAt
            }
        }

        let budgets = (try? modelContext.fetch(FetchDescriptor<BudgetPeriodItem>())) ?? []
        for budget in budgets {
            budget.expectedIncomeMinor = normalizedMoney(budget.expectedIncomeMinor)
            if budget.updatedAt < budget.createdAt {
                budget.updatedAt = budget.createdAt
            }
        }

        let categoryBudgets = (try? modelContext.fetch(FetchDescriptor<CategoryBudgetItem>())) ?? []
        for budget in categoryBudgets {
            budget.amountMinor = normalizedMoney(budget.amountMinor)
            if budget.updatedAt < budget.createdAt {
                budget.updatedAt = budget.createdAt
            }
        }
    }

    @MainActor
    private static func backfillPersonCountsIfNeeded(modelContext: ModelContext) -> Bool {
        guard !UserDefaults.standard.bool(forKey: personCountsBackfilledKey) else {
            return false
        }

        let people = (try? modelContext.fetch(FetchDescriptor<PersonItem>())) ?? []
        guard !people.isEmpty else { return true }

        let transactionTags = (try? modelContext.fetch(FetchDescriptor<TransactionPersonTagItem>())) ?? []
        let recurringTags = (try? modelContext.fetch(FetchDescriptor<RecurringRulePersonTagItem>())) ?? []

        var transactionCounts: [UUID: Int] = [:]
        for tag in transactionTags {
            guard let personID = tag.person?.id else { continue }
            transactionCounts[personID, default: 0] += 1
        }

        var recurringCounts: [UUID: Int] = [:]
        for tag in recurringTags {
            guard let personID = tag.person?.id else { continue }
            recurringCounts[personID, default: 0] += 1
        }

        for person in people {
            person.transactionCount = transactionCounts[person.id] ?? 0
            person.recurringRuleCount = recurringCounts[person.id] ?? 0
            person.updatedAt = max(person.updatedAt, person.createdAt)
        }

        return true
    }

    private static func normalizedMoney(_ value: Int64) -> Int64 {
        if value == Int64.min { return Int64.max }
        return abs(value)
    }
}

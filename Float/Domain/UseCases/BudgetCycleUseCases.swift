import Foundation
import SwiftData

@MainActor
enum BudgetCycleUseCase {
    static func syncCurrentCycle(
        modelContext: ModelContext,
        profileID: UUID?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let budgets = filterActiveProfile(
            (try? modelContext.fetch(FetchDescriptor<BudgetPeriodItem>())) ?? []
        )
        guard let activeBudget = budgets.first(where: \.isActive) ?? budgets.first else {
            return
        }

        let currentPeriod = BudgetPeriodCalculator.currentPeriod(
            for: activeBudget,
            now: now,
            calendar: calendar
        )
        let templates = activeCategoryTemplates(modelContext: modelContext)
        let cycles = fetchCycles(modelContext: modelContext)

        guard let latestCycle = cycles.last else {
            _ = createCycle(
                period: currentPeriod,
                budget: activeBudget,
                templates: templates,
                rolloverAdjustments: [:],
                profileID: profileID,
                modelContext: modelContext
            )
            try? modelContext.save()
            return
        }

        if latestCycle.status == .open, period(of: latestCycle) == currentPeriod {
            syncOpenCycle(
                latestCycle,
                period: currentPeriod,
                budget: activeBudget,
                templates: templates,
                modelContext: modelContext
            )
            try? modelContext.save()
            return
        }

        if latestCycle.status == .open, periodContains(now, cycle: latestCycle, calendar: calendar) {
            syncOpenCycle(
                latestCycle,
                period: currentPeriod,
                budget: activeBudget,
                templates: templates,
                modelContext: modelContext
            )
            try? modelContext.save()
            return
        }

        var workingCycle = latestCycle
        while period(of: workingCycle).end < currentPeriod.start {
            let rolloverAdjustments = finalizedRolloverAdjustments(
                for: workingCycle,
                modelContext: modelContext,
                now: now,
                calendar: calendar
            )
            let next = createCycle(
                period: nextPeriod(
                    after: period(of: workingCycle),
                    budget: activeBudget,
                    calendar: calendar
                ),
                budget: activeBudget,
                templates: templates,
                rolloverAdjustments: rolloverAdjustments,
                profileID: profileID,
                modelContext: modelContext
            )
            workingCycle = next
        }

        if workingCycle.status == .open {
            syncOpenCycle(
                workingCycle,
                period: currentPeriod,
                budget: activeBudget,
                templates: templates,
                modelContext: modelContext
            )
        }

        try? modelContext.save()
    }

    private static func activeCategoryTemplates(
        modelContext: ModelContext
    ) -> [CategoryBudgetItem] {
        let budgets = filterActiveProfile(
            (try? modelContext.fetch(FetchDescriptor<CategoryBudgetItem>())) ?? []
        )
        return budgets.filter { budget in
            guard
                budget.isActive,
                let category = budget.category,
                !category.archived,
                !category.isIncome
            else {
                return false
            }
            return budget.amountMinor > 0
        }
    }

    private static func fetchCycles(
        modelContext: ModelContext
    ) -> [BudgetCycleItem] {
        let descriptor = FetchDescriptor<BudgetCycleItem>(
            sortBy: [SortDescriptor(\.startDate)]
        )
        return filterActiveProfile((try? modelContext.fetch(descriptor)) ?? [])
    }

    private static func createCycle(
        period: BudgetPeriod,
        budget: BudgetPeriodItem,
        templates: [CategoryBudgetItem],
        rolloverAdjustments: [UUID: Int64],
        profileID: UUID?,
        modelContext: ModelContext
    ) -> BudgetCycleItem {
        let cycle = BudgetCycleItem(
            profileID: profileID,
            startDate: period.start,
            endDate: period.end,
            expectedIncomeMinor: budget.expectedIncomeMinor,
            currencyCode: budget.currencyCode,
            sourceBudgetID: budget.id
        )
        modelContext.insert(cycle)
        syncCycleCategories(
            cycle,
            templates: templates,
            rolloverAdjustments: rolloverAdjustments,
            modelContext: modelContext
        )
        return cycle
    }

    private static func syncOpenCycle(
        _ cycle: BudgetCycleItem,
        period: BudgetPeriod,
        budget: BudgetPeriodItem,
        templates: [CategoryBudgetItem],
        modelContext: ModelContext
    ) {
        cycle.startDate = period.start
        cycle.endDate = period.end
        cycle.expectedIncomeMinor = budget.expectedIncomeMinor
        cycle.currencyCode = budget.currencyCode
        cycle.sourceBudgetID = budget.id
        cycle.updatedAt = Date()

        var existingRolloverAdjustments: [UUID: Int64] = [:]
        for item in cycle.categories {
            guard let categoryID = item.category?.id else { continue }
            existingRolloverAdjustments[categoryID] = item.rolloverInMinor
        }

        syncCycleCategories(
            cycle,
            templates: templates,
            rolloverAdjustments: existingRolloverAdjustments,
            modelContext: modelContext
        )
    }

    private static func syncCycleCategories(
        _ cycle: BudgetCycleItem,
        templates: [CategoryBudgetItem],
        rolloverAdjustments: [UUID: Int64],
        modelContext: ModelContext
    ) {
        var templateMap: [UUID: CategoryBudgetItem] = [:]
        for template in templates {
            guard let categoryID = template.category?.id else { continue }
            templateMap[categoryID] = template
        }

        var existingMap: [UUID: BudgetCycleCategoryItem] = [:]
        for item in cycle.categories {
            guard let categoryID = item.category?.id else { continue }
            existingMap[categoryID] = item
        }

        let relevantCategoryIDs = Set(templateMap.keys)
            .union(rolloverAdjustments.keys)
            .union(existingMap.compactMap { entry in
                entry.value.rolloverInMinor != 0 ? entry.key : nil
            })

        var retainedIDs = Set<UUID>()

        for categoryID in relevantCategoryIDs {
            let template = templateMap[categoryID]
            let existing = existingMap[categoryID]
            let category = template?.category ?? existing?.category
            guard let category, !category.archived, !category.isIncome else { continue }

            let plannedAmountMinor = template?.amountMinor ?? 0
            let rolloverInMinor = rolloverAdjustments[categoryID]
                ?? existing?.rolloverInMinor
                ?? 0
            let effectiveBudgetMinor = plannedAmountMinor + rolloverInMinor

            if plannedAmountMinor <= 0 && rolloverInMinor == 0 {
                if let existing {
                    modelContext.delete(existing)
                }
                continue
            }

            let item = existing ?? BudgetCycleCategoryItem(
                profileID: cycle.profileID,
                cycle: cycle,
                category: category,
                plannedAmountMinor: plannedAmountMinor,
                rolloverInMinor: rolloverInMinor,
                effectiveBudgetMinor: effectiveBudgetMinor,
                rolloverPolicy: template?.rolloverPolicy ?? .none
            )

            if existing == nil {
                modelContext.insert(item)
            }

            item.profileID = cycle.profileID ?? category.profileID
            item.cycle = cycle
            item.category = category
            item.plannedAmountMinor = plannedAmountMinor
            item.rolloverInMinor = rolloverInMinor
            item.effectiveBudgetMinor = effectiveBudgetMinor
            item.rolloverPolicy = template?.rolloverPolicy ?? existing?.rolloverPolicy ?? .none
            item.updatedAt = Date()
            retainedIDs.insert(categoryID)
        }

        for item in Array(cycle.categories) {
            guard let categoryID = item.category?.id else {
                modelContext.delete(item)
                continue
            }
            if !retainedIDs.contains(categoryID) {
                modelContext.delete(item)
            }
        }
    }

    private static func finalizedRolloverAdjustments(
        for cycle: BudgetCycleItem,
        modelContext: ModelContext,
        now: Date,
        calendar: Calendar
    ) -> [UUID: Int64] {
        if cycle.status == .open {
            closeOpenCycle(
                cycle,
                modelContext: modelContext,
                now: now,
                calendar: calendar
            )
        }

        var adjustments: [UUID: Int64] = [:]
        for item in cycle.categories {
            guard let categoryID = item.category?.id else { continue }
            adjustments[categoryID] = item.rolloverOutMinor
        }
        return adjustments
    }

    private static func closeOpenCycle(
        _ cycle: BudgetCycleItem,
        modelContext: ModelContext,
        now: Date,
        calendar: Calendar
    ) {
        let period = period(of: cycle)
        let transactions = transactions(
            in: period,
            modelContext: modelContext,
            calendar: calendar
        )

        var spentByCategory: [UUID: Int64] = [:]
        for transaction in transactions where transaction.isPostedExpense {
            guard let categoryID = transaction.category?.id else { continue }
            spentByCategory[categoryID, default: 0] += transaction.amountMinor
        }

        for item in Array(cycle.categories) {
            let categoryID = item.category?.id
            let spentMinor = categoryID.flatMap { spentByCategory[$0] } ?? 0
            let remainingMinor = item.effectiveBudgetMinor - spentMinor

            item.spentMinorSnapshot = spentMinor
            item.remainingMinorSnapshot = remainingMinor
            item.rolloverOutMinor = rolloverOutMinor(
                fromRemainingMinor: remainingMinor,
                policy: item.rolloverPolicy
            )
            item.updatedAt = now
        }

        cycle.status = .closedPendingReview
        cycle.closedAt = now
        cycle.updatedAt = now
    }

    private static func rolloverOutMinor(
        fromRemainingMinor remainingMinor: Int64,
        policy: BudgetRolloverPolicy
    ) -> Int64 {
        switch policy {
        case .none:
            return 0
        case .carryRemaining:
            return max(0, remainingMinor)
        case .carryOverspend:
            return min(0, remainingMinor)
        }
    }

    private static func transactions(
        in period: BudgetPeriod,
        modelContext: ModelContext,
        calendar: Calendar
    ) -> [TransactionItem] {
        let startDate = period.start
        let endDate = endOfDay(for: period.end, calendar: calendar)
        let descriptor = FetchDescriptor<TransactionItem>(
            predicate: #Predicate<TransactionItem> { transaction in
                transaction.timestamp >= startDate && transaction.timestamp <= endDate
            }
        )
        return filterActiveProfile((try? modelContext.fetch(descriptor)) ?? [])
    }

    private static func nextPeriod(
        after period: BudgetPeriod,
        budget: BudgetPeriodItem,
        calendar: Calendar
    ) -> BudgetPeriod {
        let nextDate = calendar.date(byAdding: .day, value: 1, to: period.end) ?? period.end
        return BudgetPeriodCalculator.currentPeriod(
            for: budget,
            now: nextDate,
            calendar: calendar
        )
    }

    private static func period(of cycle: BudgetCycleItem) -> BudgetPeriod {
        BudgetPeriod(start: cycle.startDate, end: cycle.endDate)
    }

    private static func periodContains(
        _ date: Date,
        cycle: BudgetCycleItem,
        calendar: Calendar
    ) -> Bool {
        period(of: cycle).contains(date, calendar: calendar)
    }

    private static func endOfDay(for date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: start
        ) ?? date
    }
}

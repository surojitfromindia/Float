import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query(sort: \TransactionItem.timestamp, order: .reverse) private var transactions: [TransactionItem]
    @Query private var goals: [GoalItem]
    @Query private var recurringRules: [RecurringRuleItem]
    @Query private var budgets: [BudgetPeriodItem]

    private var activeBudget: BudgetPeriodItem? { budgets.first { $0.isActive } ?? budgets.first }
    private var result: SafeToSpendResult {
        SafeToSpendUseCase.calculate(budget: activeBudget, transactions: transactions, goals: goals, recurringRules: recurringRules)
    }
    private var todayExpenses: Int64 {
        transactions.filter { $0.isExpense && Calendar.current.isDateInToday($0.timestamp) }.reduce(0) { $0 + $1.amountMinor }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SafeToSpendHeroCard(result: result, currencyCode: appState.selectedCurrencyCode)

                HStack(spacing: 14) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Today")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(MoneyFormatter.string(minorUnits: todayExpenses, currencyCode: appState.selectedCurrencyCode))
                                .moneyStyle(size: 24, weight: .bold)
                            Text("spent so far")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Days left")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(result.daysRemaining)")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                            Text("including today")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                nearestGoal
                recentTransactions
            }
            .padding(20)
            .padding(.bottom, 96)
        }
        .navigationTitle("Float")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appState.presentNewTransaction()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add transaction")
            }
        }
        .floatBackground()
        .onAppear { MaterializeRecurringTransactionsUseCase.run(modelContext: modelContext) }
    }

    @ViewBuilder private var nearestGoal: some View {
        if let goal = goals.filter({ !$0.achieved }).sorted(by: { ($0.targetDate ?? .distantFuture) < ($1.targetDate ?? .distantFuture) }).first {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Nearest goal")
                    HStack(spacing: 16) {
                        FloatProgressRing(progress: Double(goal.savedMinor) / Double(max(goal.targetMinor, 1)), tint: Color(hex: goal.colorHex), lineWidth: 8)
                            .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(goal.name).font(.headline)
                            Text("\(MoneyFormatter.string(minorUnits: goal.savedMinor, currencyCode: appState.selectedCurrencyCode)) of \(MoneyFormatter.string(minorUnits: goal.targetMinor, currencyCode: appState.selectedCurrencyCode))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recent")
            GlassCard {
                if transactions.isEmpty {
                    EmptyStateView(icon: "sparkles", title: "No transactions yet", message: "Add your first expense when you are ready.")
                } else {
                    VStack(spacing: 8) {
                        ForEach(transactions.prefix(4)) { transaction in
                            TransactionRowView(transaction: transaction, currencyCode: appState.selectedCurrencyCode)
                            if transaction.id != transactions.prefix(4).last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }
}

struct SafeToSpendHeroCard: View {
    let result: SafeToSpendResult
    let currencyCode: String

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("You can spend")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(MoneyFormatter.string(minorUnits: result.safeToSpendMinor, currencyCode: currencyCode))
                            .moneyStyle(size: 44, weight: .bold)
                            .minimumScaleFactor(0.65)
                        Text(result.overAmountMinor > 0 ? "You’re \(MoneyFormatter.string(minorUnits: result.overAmountMinor, currencyCode: currencyCode)) over for this period." : "You’re on track")
                            .font(.subheadline)
                            .foregroundStyle(result.overAmountMinor > 0 ? Color(hex: "#B4613B") : Color(hex: "#1B8A5A"))
                    }
                    Spacer()
                    FloatProgressRing(progress: result.periodProgress, tint: Color(hex: "#0E7C7B"))
                        .frame(width: 76, height: 76)
                }
                Divider().opacity(0.5)
                HStack {
                    Label(MoneyFormatter.string(minorUnits: result.dailyAllowanceMinor, currencyCode: currencyCode), systemImage: "calendar")
                        .moneyStyle(size: 17, weight: .semibold)
                    Text("per day left this period")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

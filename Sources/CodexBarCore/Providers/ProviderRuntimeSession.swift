import Foundation

/// Shared in-process provider runtime used by native application frontends.
///
/// This deliberately builds the same `ProviderFetchContext` consumed by the
/// canonical descriptor registry. A frontend therefore does not need to shell
/// out to `CodexBarCLI`, duplicate provider routing, or maintain a second list
/// of supported providers.
public struct ProviderRuntimeSession: Sendable {
    private let configStore: CodexBarConfigStore
    private let baseEnvironment: [String: String]
    private let browserDetection: BrowserDetection
    private let managedCodexAccountStoreURL: URL?

    public init(
        configStore: CodexBarConfigStore = CodexBarConfigStore(),
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        browserDetection: BrowserDetection = BrowserDetection(),
        managedCodexAccountStoreURL: URL? = nil)
    {
        self.configStore = configStore
        self.baseEnvironment = baseEnvironment
        self.browserDetection = browserDetection
        self.managedCodexAccountStoreURL = managedCodexAccountStoreURL
    }

    public func fetch(
        provider: UsageProvider,
        config: CodexBarConfig,
        sourceModeOverride: ProviderSourceMode? = nil,
        includeCredits: Bool = true,
        webTimeout: TimeInterval = 60,
        historyDays: Int = 30,
        interaction: ProviderInteraction = .background) async throws -> ProviderFetchResult
    {
        let providerConfig = config.providerConfig(for: provider.instanceID)
        let account = Self.selectedAccount(from: providerConfig)
        let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
        let settings = self.settingsSnapshot(
            provider: provider,
            config: providerConfig,
            account: account)
        let environment = self.environment(
            provider: provider,
            config: providerConfig,
            account: account)
        let configuredSource = sourceModeOverride ?? providerConfig?.source ?? .auto
        let sourceMode = descriptor.credentials?.selectedAccountSourceMode(
            base: configuredSource,
            account: account,
            config: providerConfig) ?? configuredSource
        // Provider-specific by design: Codex needs its scoped environment in both usage and CLI version probes.
        let baseFetcher = UsageFetcher()
        let fetcher = provider == .codex ? UsageFetcher(environment: environment) : baseFetcher
        let tokenUpdater = self.tokenUpdater(for: account)
        let configStore = self.configStore
        let manualTokenUpdater: ProviderFetchContext.ProviderManualTokenUpdater = { provider, token in
            do {
                try ProviderDescriptorRegistry.descriptor(for: provider).credentials?.persistManualToken(token)
            } catch {
                // A refresh-token rotation must never make an otherwise valid usage response fail.
            }
        }
        let resolvedVersion = provider == .codex
            ? descriptor.cli.versionDetector?(self.browserDetection)
            : nil
        let context = ProviderFetchContext(
            runtime: .app,
            sourceMode: sourceMode,
            includeCredits: includeCredits,
            requiresOptionalUsageCompleteness: true,
            webTimeout: webTimeout,
            webDebugDumpHTML: false,
            verbose: false,
            env: environment,
            settings: settings,
            fetcher: fetcher,
            claudeFetcher: ClaudeUsageFetcher(browserDetection: self.browserDetection),
            browserDetection: self.browserDetection,
            selectedTokenAccountID: account?.id,
            tokenAccountTokenUpdater: tokenUpdater,
            providerManualTokenUpdater: manualTokenUpdater,
            costUsageHistoryDays: historyDays,
            persistsCLISessions: true,
            persistentCLISessionIdleWindow: 10 * 60,
            resolvedCLIVersion: resolvedVersion)

        _ = configStore // Keep the captured store alive for updater closures.
        return try await ProviderInteractionContext.$current.withValue(interaction) {
            try await descriptor.fetch(context: context)
        }
    }

    public func settingsSnapshot(
        provider: UsageProvider,
        config: ProviderConfig?,
        account: ProviderTokenAccount?) -> ProviderSettingsSnapshot?
    {
        // Provider-specific by design: Codex reconciles managed homes before building its canonical settings snapshot.
        if provider == .codex {
            let reconciliation = self.codexAccountReconciler(config: config).loadSnapshot()
            let resolvedSource = CodexActiveSourceResolver.resolve(from: reconciliation)
            let cookies = ProviderCredentialSettingsContext(config: config, account: account)
                .cookieSettings(for: .codex)
            let codexSettings = CodexProviderSettingsBuilder.make(input: CodexProviderSettingsBuilderInput(
                usageDataSource: .auto,
                cookieSource: cookies.cookieSource,
                manualCookieHeader: cookies.manualCookieHeader,
                reconciliationSnapshot: reconciliation,
                resolvedActiveSource: resolvedSource))
            return ProviderSettingsSnapshot.make(codex: codexSettings)
        }

        guard let contribution = ProviderDescriptorRegistry.descriptor(for: provider)
            .settingsSection
            .credentialContribution(context: ProviderCredentialSettingsContext(config: config, account: account))
        else { return nil }
        return ProviderSettingsSnapshot(contributions: [contribution])
    }

    /// Prompt-free local authentication summary for provider-list status UI.
    public func authenticationSummary(
        provider: UsageProvider,
        config: CodexBarConfig) -> ProviderDiagnosticAuthSummary
    {
        let providerConfig = config.providerConfig(for: provider.instanceID)
        let account = Self.selectedAccount(from: providerConfig)
        let settings = self.settingsSnapshot(
            provider: provider,
            config: providerConfig,
            account: account)
        let environment = self.environment(
            provider: provider,
            config: providerConfig,
            account: account)
        if let credentials = ProviderDescriptorRegistry.descriptor(for: provider).credentials {
            return credentials.diagnosticAuthSummary(
                account: account,
                config: providerConfig,
                environment: environment,
                settings: settings)
        }
        return ProviderDiagnosticAuthSummary(configured: providerConfig?.enabled == true, modes: [])
    }

    private static func selectedAccount(from config: ProviderConfig?) -> ProviderTokenAccount? {
        guard let accounts = config?.tokenAccounts, !accounts.accounts.isEmpty else { return nil }
        return accounts.accounts[accounts.clampedActiveIndex()]
    }

    private func environment(
        provider: UsageProvider,
        config: ProviderConfig?,
        account: ProviderTokenAccount?) -> [String: String]
    {
        var environment = ProviderEnvironmentResolver.resolve(
            base: self.baseEnvironment,
            provider: provider,
            config: config,
            selectedAccount: account)
        // Provider-specific by design: only Codex supports per-account CODEX_HOME isolation.
        guard provider == .codex,
              let codexHome = self.codexHomePath(config: config)
        else { return environment }
        environment = CodexHomeScope.scopedEnvironment(base: environment, codexHome: codexHome)
        return environment
    }

    private func codexHomePath(config: ProviderConfig?) -> String? {
        let snapshot = self.codexAccountReconciler(config: config).loadSnapshot()
        switch CodexActiveSourceResolver.resolve(from: snapshot).resolvedSource {
        case .liveSystem:
            return nil
        case let .managedAccount(id):
            return snapshot.storedAccounts.first(where: { $0.id == id })?.managedHomePath
        case let .profileHome(path):
            return snapshot.configuredProfileHomePath(path: path)
        }
    }

    private func codexAccountReconciler(config: ProviderConfig?) -> DefaultCodexAccountReconciler {
        let storeURL = self.managedCodexAccountStoreURL
        let storeLoader: @Sendable () throws -> ManagedCodexAccountSet = {
            if let storeURL {
                return try FileManagedCodexAccountStore(fileURL: storeURL).loadAccounts()
            }
            return try FileManagedCodexAccountStore().loadAccounts()
        }
        return DefaultCodexAccountReconciler(
            storeLoader: storeLoader,
            activeSource: config?.codexActiveSource ?? .liveSystem,
            baseEnvironment: self.baseEnvironment,
            profileHomePaths: config?.codexProfileHomePaths ?? [])
    }

    private func tokenUpdater(
        for account: ProviderTokenAccount?) -> ProviderFetchContext.TokenAccountTokenUpdater?
    {
        guard let account else { return nil }
        let configStore = self.configStore
        return { provider, accountID, token in
            guard accountID == account.id else { return }
            try? Self.updateStoredTokenAccount(
                provider: provider,
                accountID: accountID,
                token: token,
                configStore: configStore)
        }
    }

    private static func updateStoredTokenAccount(
        provider: UsageProvider,
        accountID: UUID,
        token: String,
        configStore: CodexBarConfigStore) throws
    {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty,
              var config = try configStore.load(),
              var providerConfig = config.providerConfig(for: provider.instanceID),
              let data = providerConfig.tokenAccounts,
              let index = data.accounts.firstIndex(where: { $0.id == accountID })
        else { return }

        let existing = data.accounts[index]
        var accounts = data.accounts
        accounts[index] = ProviderTokenAccount(
            id: existing.id,
            label: existing.label,
            token: token,
            addedAt: existing.addedAt,
            lastUsed: existing.lastUsed,
            externalIdentifier: existing.externalIdentifier,
            usageScope: existing.usageScope,
            organizationID: existing.organizationID,
            workspaceID: existing.workspaceID)
        providerConfig.tokenAccounts = ProviderTokenAccountData(
            version: data.version,
            accounts: accounts,
            activeIndex: data.clampedActiveIndex())
        config.setProviderConfig(providerConfig)
        try configStore.save(config)
    }
}

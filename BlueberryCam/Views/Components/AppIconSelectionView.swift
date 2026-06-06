import SwiftUI

struct AppIconSelectionView: View {
    @Environment(\.colorScheme) var colorScheme
    
    @Bindable var appSettings: AppSettings
    
    @State private var isShowingIconLockedAlert = false
    @State private var isShowingIconLockedCustomAlert = false
    @State private var isShowingIconIncorrectUnlockAlert = false
    @State private var isShowingIconIncorrectCustomUnlockAlert = false
    @State private var isShowingIconUnlockedAlert = false
    @State private var unlockIconsGuess = ""
    @State private var unlockIconsCustomGuess = ""
    @State private var selectedIconBeforeUnlock: AppIcon?
    @State private var selectionHapticTrigger = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                iconsList()
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: selectionHapticTrigger)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("App Icon")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(.primary)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !appSettings.hasUnlockedCustomisation {
                    Button("Locked", systemImage: "lock.fill") {
                        isShowingIconLockedAlert = true
                    }
                } else {
                    if !appSettings.hasUnlockedFullCustomisation {
                        Button("Locked", systemImage: "lock.fill") {
                            isShowingIconLockedCustomAlert = true
                        }
                    } else {
                        Button("Unlocked", systemImage: "lock.open.fill") {
                            isShowingIconUnlockedAlert = true
                        }
                    }
                }
            }
        }
        .alert("Requirements not met to unlock app icons and themes.", isPresented: $isShowingIconLockedAlert) {
            SecureField("Unlock Key", text: $unlockIconsGuess)
                .onSubmit {
                    submitIconUnlockKey()
                }
            Button("Cancel", role: .cancel, action: resetIconUnlockState)
            Button("Unlock", action: submitIconUnlockKey)
        } message: {
            Text("To unlock app icons and themes, your standard shutter count must be at least 100, and burst count at least 500.\nYou can check your statistics at the bottom of settings, or below the photos link shortcut to the left of the shutter button.\nAlternatively, if you have an unlock key enter it below.")
        }
        .alert("Requirements not met to unlock all app icons and themes.", isPresented: $isShowingIconLockedCustomAlert) {
            SecureField("Unlock All Icons and Themes Key", text: $unlockIconsCustomGuess)
                .onSubmit {
                    submitCustomIconUnlockKey()
                }
            Button("Cancel", role: .cancel, action: resetIconUnlockState)
            Button("Unlock", action: submitCustomIconUnlockKey)
        } message: {
            Text("To unlock all app icons and themes, your standard shutter count must be at least 1000, and burst count at least 1000.\nYou can check your statistics at the bottom of settings, or below the photos link shortcut to the left of the shutter button.\nAlternatively, if you have an unlock key enter it below.")
        }
        .alert("Incorrect unlock key", isPresented: $isShowingIconIncorrectUnlockAlert) {
            Button("Cancel", role: .cancel, action: resetIconUnlockState)
            Button("Try Again") {
                isShowingIconLockedAlert = true
            }
        } message: {
            Text("Check the unlock key and try again.")
        }
        .alert("Incorrect custom unlock key", isPresented: $isShowingIconIncorrectCustomUnlockAlert) {
            Button("Cancel", role: .cancel, action: resetIconUnlockState)
            Button("Try Again") {
                isShowingIconLockedCustomAlert = true
            }
        } message: {
            Text("Check the full unlock key and try again.")
        }
        .alert("All app icons and themes are unlocked!", isPresented: $isShowingIconUnlockedAlert) {}
    }
    
    // MARK: - Subviews
    private func iconsList() -> some View {
        VStack(spacing: 0) {
            ForEach(AppIcon.allCases, id: \.self) { icon in
                iconRow(icon)
                if let last = AppIcon.allCases.last, icon != last {
                    Divider()
                }
            }
        }
        .ignoresSafeArea(.keyboard)
        .padding(.horizontal)
        .glassEffect(
            .regular.tint(colorScheme == .dark ? .black.opacity(0.18) : .white.opacity(0.35)),
            in: .rect(cornerRadius: 24)
        )
    }
    
    private func iconRow(_ icon: AppIcon) -> some View {
        Button {
            handleIconClicked(icon)
        } label: {
            HStack {
                iconImage(icon)
                iconName(icon)
                Spacer()
                tickOrLockIndicator(icon)
                    .padding(.leading)
            }
            .contentShape(.rect)
            .animation(Animations.easeInOut, value: appSettings.hasUnlockedCustomisation)
            .animation(Animations.easeInOut, value: appSettings.hasUnlockedFullCustomisation)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .buttonStyle(.plain)
    }
    
    private func iconImage(_ icon: AppIcon) -> some View {
        Image(icon.previewImageName)
            .resizable()
            .frame(width: 44, height: 44)
            .clipShape(.rect(cornerRadius: 10))
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
    }
    
    private func iconName(_ icon: AppIcon) -> some View {
        Text(icon.rawValue)
            .foregroundStyle(.primary)
    }
    
    private func tickOrLockIndicator(_ icon: AppIcon) -> some View {
        Group {
            if appSettings.selectedIcon == icon {
                Image(systemName: "checkmark")
                    .foregroundStyle(.primary)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: appSettings.selectedIcon)
            } else {
                if !appSettings.hasUnlockedFullCustomisation && icon == AppIcon.blueberry {
                    Image(systemName: "lock")
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                } else if !appSettings.hasUnlockedCustomisation {
                    Image(systemName: "lock.fill")
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                } else {
                    Image(systemName: "checkmark")
                        .opacity(0)
                }
            }
        }
    }
    
    // MARK: - Functions
    private func hasUnlockedIcon(_ icon: AppIcon) -> Bool {
        if icon == AppIcon.classic { return true }
        guard appSettings.hasUnlockedCustomisation else { return false }
        if icon == AppIcon.blueberry { return appSettings.hasUnlockedFullCustomisation }
        return true
    }
    
    private func handleIconClicked(_ icon: AppIcon) {
        if !appSettings.hasUnlockedCustomisation && icon == AppIcon.classic { return }
        if appSettings.canUseIcon(icon) {
            appSettings.selectedIcon = icon
            selectionHapticTrigger += 1
        } else {
            selectedIconBeforeUnlock = icon
            if icon == AppIcon.blueberry {
                isShowingIconLockedCustomAlert = true
            } else {
                isShowingIconLockedAlert = true
            }
        }
    }
    
    private func submitIconUnlockKey() {
        if appSettings.unlockCustomisation(with: unlockIconsGuess) {
            applyUnlockedIconSelection()
        } else {
            unlockIconsGuess = ""
            isShowingIconIncorrectUnlockAlert = true
        }
    }
    
    private func submitCustomIconUnlockKey() {
        if appSettings.unlockFullCustomisation(with: unlockIconsCustomGuess) {
            applyUnlockedIconSelection()
        } else {
            unlockIconsCustomGuess = ""
            isShowingIconIncorrectCustomUnlockAlert = true
        }
    }
    
    private func applyUnlockedIconSelection() {
        if let selectedIconBeforeUnlock {
            appSettings.selectedIcon = selectedIconBeforeUnlock
        }
        resetIconUnlockState()
    }
    
    private func resetIconUnlockState() {
        unlockIconsGuess = ""
        unlockIconsCustomGuess = ""
        selectedIconBeforeUnlock = nil
    }
}

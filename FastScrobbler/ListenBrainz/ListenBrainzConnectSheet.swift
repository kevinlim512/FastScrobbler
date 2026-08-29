import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ListenBrainzConnectSheet: View {
    @EnvironmentObject private var listenBrainzAuth: ListenBrainzAuthManager
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var tokenInput = ""
    @State private var isConnecting = false
    @State private var errorText: String?

    private var secondaryBackgroundColor: Color {
        #if os(iOS)
        return Color(uiColor: .secondarySystemBackground)
        #elseif os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color.secondary.opacity(0.15)
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("To connect ListenBrainz, copy your User API Token from your profile page on ListenBrainz.org and paste it below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)

                    Button {
                        openURL(listenBrainzAuth.tokenPageURL)
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.right.square")
                            Text("Get Token on ListenBrainz.org")
                        }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(secondaryBackgroundColor)
                        .foregroundColor(.primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("User Token")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        HStack {
                            SecureField("Paste User Token here", text: $tokenInput)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                                .autocorrectionDisabled()
                                .font(.body)

                            if !tokenInput.isEmpty {
                                Button {
                                    tokenInput = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                #if os(iOS)
                                let pastedString = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines)
                                #elseif os(macOS)
                                let pastedString = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
                                #else
                                let pastedString: String? = nil
                                #endif
                                if let pastedString, !pastedString.isEmpty {
                                    tokenInput = pastedString
                                }
                            } label: {
                                Text("Paste")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.accentColor)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(14)
                        .background(secondaryBackgroundColor)
                        .cornerRadius(12)

                        if let errorText {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(Color.accentColor)
                                .padding(.top, 4)
                        }
                    }

                    Button {
                        Task {
                            await connect()
                        }
                    } label: {
                        HStack {
                            if isConnecting {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.trailing, 6)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text(isConnecting ? "Connecting…" : "Connect ListenBrainz")
                                .font(.body.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting
                            ? Color.accentColor.opacity(0.4)
                            : Color.accentColor
                        )
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)
                    .padding(.top, 16)

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("Connect ListenBrainz")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        IOSCloseButtonLabel(style: .plain)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 400)
        #endif
    }

    private func connect() async {
        isConnecting = true
        errorText = nil
        do {
            try await listenBrainzAuth.connect(token: tokenInput)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
        isConnecting = false
    }
}

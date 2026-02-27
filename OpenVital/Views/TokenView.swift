import SwiftUI
import CoreImage.CIFilterBuiltins

struct TokenView: View {
    @Bindable var appState: AppState
    @State private var isTokenVisible = false
    @State private var showRegenerateConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                tokenSection
                qrCodeSection
                usageSection
            }
            .navigationTitle("API Token")
            .confirmationDialog(
                "Regenerate Token?",
                isPresented: $showRegenerateConfirmation,
                titleVisibility: .visible
            ) {
                Button("Regenerate", role: .destructive) {
                    Task { await appState.regenerateToken() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will invalidate the current token. All connected clients will need to be updated.")
            }
        }
    }

    // MARK: - Token Display

    private var tokenSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if isTokenVisible {
                        Text(appState.currentToken)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text(String(repeating: "*", count: 32))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 16) {
                    Button {
                        isTokenVisible.toggle()
                    } label: {
                        Label(
                            isTokenVisible ? "Hide" : "Show",
                            systemImage: isTokenVisible ? "eye.slash" : "eye"
                        )
                    }

                    Button {
                        UIPasteboard.general.string = appState.currentToken
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }

                    Spacer()

                    Button(role: .destructive) {
                        showRegenerateConfirmation = true
                    } label: {
                        Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(.borderless)
            }
        } header: {
            Text("Bearer Token")
        } footer: {
            Text("Include this token in the Authorization header of all API requests.")
        }
    }

    // MARK: - QR Code

    private var qrCodeSection: some View {
        Section {
            VStack {
                if let qrImage = generateQRCode(from: appState.currentToken) {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .padding()
                }
                Text("Scan to import the token")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        } header: {
            Text("QR Code")
        }
    }

    // MARK: - Usage Examples

    private var usageSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("HTTP Header")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Authorization: Bearer <token>")
                    .font(.system(.caption, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("curl")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(appState.curlWithAuthExample)
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(4)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = appState.curlWithAuthExample
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Python")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let pythonExample = """
                import requests
                r = requests.get(
                    "\(appState.serverURL)/v1/metrics/stepCount",
                    headers={"Authorization": "Bearer <token>"}
                )
                print(r.json())
                """
                Text(pythonExample)
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(10)
            }
        } header: {
            Text("Usage")
        }
    }

    // MARK: - QR Code Generation

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scale = 10.0
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

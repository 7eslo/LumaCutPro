import SwiftUI
import AVFoundation
import PhotosUI

struct ContentView: View {
    @StateObject private var processor = SilenceProcessor()
    @State private var selectedItem: PhotosPickerItem?
    @State private var threshold: Double = -30
    @State private var minSilence: Double = 0.5
    @State private var padding: Double = 0.2
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("LumaCut Pro")
                    .font(.largeTitle.bold())
                
                Text("قص الصمت • دقة عالية • بت رايت أصلي")
                    .foregroundColor(.secondary)
                
                if let url = processor.inputURL {
                    VideoPreview(url: url)
                        .frame(height: 220)
                        .cornerRadius(16)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 220)
                        .overlay(Text("اختر فيديو").foregroundColor(.secondary))
                }
                
                PhotosPicker(selection: $selectedItem, matching: .videos) {
                    Label("اختر من الصور", systemImage: "film")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("عتبة الصمت"); Spacer(); Text("\(Int(threshold)) dB") }
                    Slider(value: $threshold, in: -50...-20)
                    
                    HStack { Text("أقل مدة"); Spacer(); Text(String(format: "%.1f ث", minSilence)) }
                    Slider(value: $minSilence, in: 0.2...2.0, step: 0.1)
                    
                    HStack { Text("هامش"); Spacer(); Text(String(format: "%.1f ث", padding)) }
                    Slider(value: $padding, in: 0...0.5, step: 0.05)
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                
                if processor.isProcessing {
                    ProgressView(value: processor.progress) {
                        Text("جاري المعالجة... \(Int(processor.progress * 100))%")
                    }
                }
                
                Button(action: process) {
                    Label("ابدأ القص", systemImage: "scissors")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(processor.inputURL == nil || processor.isProcessing)
                
                if let output = processor.outputURL {
                    ShareLink(item: output) {
                        Label("فتح في LumaFusion", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Spacer()
            }
            .padding()
            .navigationBarHidden(true)
        }
        .environment(\.layoutDirection, .rightToLeft)
        .onChange(of: selectedItem) { _ in
            Task { await loadVideo() }
        }
    }
    
    func loadVideo() async {
        guard let item = selectedItem else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("input.mov")
            try? data.write(to: url)
            processor.inputURL = url
        }
    }
    
    func process() {
        processor.threshold = Float(threshold)
        processor.minSilenceDuration = minSilence
        processor.padding = padding
        processor.process()
    }
}

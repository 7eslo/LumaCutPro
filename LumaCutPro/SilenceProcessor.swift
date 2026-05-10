import AVFoundation
import Accelerate

class SilenceProcessor: ObservableObject {
    @Published var inputURL: URL?
    @Published var outputURL: URL?
    @Published var isProcessing = false
    @Published var progress: Double = 0
    
    var threshold: Float = -30
    var minSilenceDuration: Double = 0.5
    var padding: Double = 0.2
    
    func process() {
        guard let inputURL = inputURL else { return }
        isProcessing = true
        progress = 0
        
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVAsset(url: inputURL)
            guard let track = asset.tracks(withMediaType: .audio).first else { return }
            
            // إعدادات عالية الجودة - نحافظ على الأصلي
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("lumacut_\(UUID().uuidString).mov")
            
            do {
                let reader = try AVAssetReader(asset: asset)
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVSampleRateKey: 48000
                ]
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
                reader.add(output)
                reader.startReading()
                
                var silences: [CMTimeRange] = []
                var currentSilenceStart: CMTime?
                let thresholdLinear = pow(10, threshold / 20)
                
                while let sample = output.copyNextSampleBuffer() {
                    let block = CMSampleBufferGetDataBuffer(sample)!
                    let length = CMBlockBufferGetDataLength(block)
                    var data = Data(count: length)
                    data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
                    
                    let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                    let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
                    
                    let time = CMSampleBufferGetPresentationTimeStamp(sample)
                    
                    if rms < thresholdLinear {
                        if currentSilenceStart == nil { currentSilenceStart = time }
                    } else {
                        if let start = currentSilenceStart {
                            let duration = CMTimeSubtract(time, start)
                            if CMTimeGetSeconds(duration) > self.minSilenceDuration {
                                silences.append(CMTimeRange(start: start, duration: duration))
                            }
                            currentSilenceStart = nil
                        }
                    }
                    DispatchQueue.main.async { self.progress = min(0.4, self.progress + 0.001) }
                }
                
                // بناء مقاطع الكلام مع padding
                var keepRanges: [CMTimeRange] = []
                var lastEnd = CMTime.zero
                for silence in silences {
                    let start = CMTimeAdd(lastEnd, CMTime(seconds: -padding, preferredTimescale: 600))
                    let end = CMTimeAdd(silence.start, CMTime(seconds: padding, preferredTimescale: 600))
                    if CMTimeCompare(end, start) > 0 {
                        keepRanges.append(CMTimeRange(start: max(start, .zero), end: min(end, asset.duration)))
                    }
                    lastEnd = CMTimeAdd(silence.start, silence.duration)
                }
                if CMTimeCompare(lastEnd, asset.duration) < 0 {
                    keepRanges.append(CMTimeRange(start: lastEnd, end: asset.duration))
                }
                
                // تصدير بدون إعادة ترميز (passthrough) للحفاظ على البت رايت
                guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { return }
                export.outputURL = outputURL
                export.outputFileType = .mov
                export.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
                
                // استخدام composition للقص الدقيق
                let composition = AVMutableComposition()
                guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                      let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
                      let v = asset.tracks(withMediaType: .video).first,
                      let a = asset.tracks(withMediaType: .audio).first else { return }
                
                var cursor = CMTime.zero
                for range in keepRanges {
                    try? videoTrack.insertTimeRange(range, of: v, at: cursor)
                    try? audioTrack.insertTimeRange(range, of: a, at: cursor)
                    cursor = CMTimeAdd(cursor, range.duration)
                }
                
                let finalExport = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
                finalExport.outputURL = outputURL
                finalExport.outputFileType = .mov
                finalExport.shouldOptimizeForNetworkUse = false
                
                // الحفاظ على metadata الأصلية
                finalExport.metadata = asset.metadata
                
                finalExport.exportAsynchronously {
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.progress = 1.0
                        self.outputURL = outputURL
                    }
                }
                
            } catch {
                DispatchQueue.main.async { self.isProcessing = false }
            }
        }
    }
}

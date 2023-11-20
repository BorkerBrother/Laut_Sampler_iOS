// Import necessary libraries
import AudioKit
import AudioKitEX
import AudioKitUI
import AVFoundation
import Combine
import SwiftUI

// Define the bundle for accessing samples
public var sampleModuleBundle: Bundle = {
    #if SWIFT_PACKAGE
        return Bundle.module
    #else
        return Bundle.main
    #endif
}()

struct DrumSample {
    var name: String
    var fileName: String
    var midiNote: Int
    var audioFile: AVAudioFile?
    var color =  UIColor.black
    var isSelected = false
    
    init(name: String, fileName: String, midiNote: Int) {
        self.name = name
        self.fileName = fileName
        self.midiNote = midiNote
        
        if let url = sampleModuleBundle.url(forResource: fileName, withExtension: nil) {
            do {
                audioFile = try AVAudioFile(forReading: url)
            } catch {
                print("Could not load: \(fileName)")
            }
        } else {
            print("Error accessing sampleModuleBundle")
        }
    }
}

// Define a class to handle the drum conductor logic
class DrumsConductor: ObservableObject, HasAudioEngine {
    // Published property to update the view on changes
    @Published private(set) var lastPlayed: String = "None"

    // Audio engine and drum samples
    let engine = AudioEngine()
    var drumSamples: [DrumSample] =
        [
            DrumSample(name: "OPEN HI HAT", fileName: "Samples/open_hi_hat_A#1.wav", midiNote: 34),
            DrumSample(name: "HI TOM", fileName: "Samples/hi_tom_D2.wav", midiNote: 38),
            DrumSample(name: "MID TOM", fileName: "Samples/mid_tom_B1.wav", midiNote: 35),
            DrumSample(name: "LO TOM", fileName: "Samples/lo_tom_F1.wav", midiNote: 29),
            DrumSample(name: "CLOSED HI HAT", fileName: "Samples/closed_hi_hat_F#1.wav", midiNote: 30),
            DrumSample(name: "CLAP", fileName: "Samples/clap_D#1.wav", midiNote: 27),
            DrumSample(name: "SNARE", fileName: "Samples/snare_D1.wav", midiNote: 26),
            DrumSample(name: "KICK", fileName: "Samples/bass_drum_C1.wav", midiNote: 24),
        ]

    // AppleSampler for playing the drum samples
    let drums = AppleSampler()

    // Function to play a specific drum pad
    func playPad(padNumber: Int) {
        let midiNote = MIDINoteNumber(drumSamples[padNumber].midiNote)
        print("Playing Pad \(padNumber) with MIDI Note \(midiNote)")
        drums.play(noteNumber: midiNote)
        let fileName = drumSamples[padNumber].fileName
        lastPlayed = fileName.components(separatedBy: "/").last!
    }

    // Initializer to set up the audio engine and load audio files
    init() {
        engine.output = drums
        do {
            let files = drumSamples.map {
                $0.audioFile!
            }
            try drums.loadAudioFiles(files)
        } catch {
            print("Files Didn't Load")
        }
    }
}

/// Update PadsView
struct PadsView: View {
    var conductor: DrumsConductor

    var padsAction: (_ padNumber: Int) -> Void
    @State var downPads: [Int] = []

    var body: some View {
        VStack(spacing: 10) {
            NodeOutputView(conductor.drums)
            ForEach(0 ..< 2, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(0 ..< 4, id: \.self) { column in
                        ZStack {
                            Rectangle()
                                .fill(Color(conductor.drumSamples.map {
                                    downPads.contains(where: { $0 == row * 4 + column }) ? .gray : ($0.isSelected ? .blue : $0.color)
                                }[getPadId(row: row, column: column)]))
                                .cornerRadius(20)
                            Text(conductor.drumSamples.map { $0.name }[getPadId(row: row, column: column)])
                                .foregroundColor(Color(.white)).fontWeight(.bold)
                        }
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local).onChanged { _ in
                            if !(downPads.contains(where: { $0 == row * 4 + column })) {
                                padsAction(getPadId(row: row, column: column))
                                downPads.append(row * 4 + column)
                            }
                        }.onEnded { _ in
                            downPads.removeAll(where: { $0 == row * 4 + column })
                        })
                    }
                }.padding(5)
            }
        }
    }
}

// SwiftUI view for the main drums interface
struct DrumsView: View {
    @StateObject var conductor = DrumsConductor()
    @State private var isPlaying = false
    @State private var currentStep = 0
    @State private var timer: Timer?

    @State private var drumSequence: [[Int]] = [
        [0, 0, 0, 0, 0, 0, 0, 0]
        // Add more sequences as needed
    ]

    var body: some View {
        VStack(spacing: 1) {
            // Display drum pads and buttons for controlling the sequence
            PadsView(conductor: conductor) { pad in
                conductor.playPad(padNumber: pad)
            }

            HStack(spacing: 8) {
                // Display buttons for each step in the sequence
                ForEach(0 ..< 8, id: \.self) { buttonIndex in
                    Button(action: {
                        self.toggleStep(buttonIndex)
                    }) {
                        Text("Step \(buttonIndex + 1)")
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(Color.white)
                            .cornerRadius(10)
                    }
                    .padding(5)
                }
            }

            // Display a button for starting/stopping the sequence
            Button(action: {
                self.togglePlay()
            }) {
                Text(isPlaying ? "Stop" : "Start")
                    .padding()
                    .background(Color.red)
                    .foregroundColor(Color.white)
                    .cornerRadius(10)
            }
        }
        .onAppear {
            // Start the audio engine when the view appears
            self.conductor.start()
        }
        .onDisappear {
            // Stop the audio engine and invalidate the timer when the view disappears
            self.conductor.stop()
            self.timer?.invalidate()
            self.timer = nil
        }
    }

    // Function to toggle the state of a step in the sequence
    func toggleStep(_ step: Int) {
        drumSequence[currentStep][step] = drumSequence[currentStep][step] == 0 ? 1 : 0

        let isHit = drumSequence[currentStep][step] == 1
        let padColor: UIColor = isHit ? .red : .black

        let padNumber = step
        conductor.drumSamples[padNumber].color = padColor
        conductor.objectWillChange.send()

        if isHit {
            let padNumber = step
            let sampleName = conductor.drumSamples[padNumber].name
            let midiNote = conductor.drumSamples[padNumber].midiNote
            print("Button \(step + 1) pressed - Sample: \(sampleName), MidiNote: \(midiNote)")
            conductor.playPad(padNumber: padNumber)
        }
    }

    // Function to toggle the play state of the sequence
    func togglePlay() {
        if isPlaying {
            stopSequence()
        } else {
            startSequence()
        }
    }

    // Function to start playing the sequence
    func startSequence() {
        currentStep = 0
        isPlaying = true

        self.timer = Timer.scheduledTimer(withTimeInterval: 60.0 / 174.0, repeats: true) { _ in
            self.playStep()
        }
    }

    // Function to play the current step in the sequence
    func playStep() {
        for (index, value) in drumSequence[currentStep].enumerated() {
            if value == 1 {
                conductor.playPad(padNumber: index)
            }
        }
        currentStep = (currentStep + 1) % drumSequence.count
    }

    // Function to stop playing the sequence
    func stopSequence() {
        currentStep = 0
        isPlaying = false
        self.timer?.invalidate()
        self.timer = nil
    }
}

// Function to get the pad ID based on row and column
private func getPadId(row: Int, column: Int) -> Int {
    return (row * 4) + column
}


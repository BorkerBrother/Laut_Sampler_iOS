//
//  ContentView.swift
//  Laut Sampler
//
//  Created by Borker on 20.11.23.
//

import AudioKit
import AudioKitEX
import AudioKitUI
import AVFoundation
import Combine
import SwiftUI

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




class DrumsConductor: ObservableObject, HasAudioEngine {
    // Mark Published so View updates label on changes
    @Published private(set) var lastPlayed: String = "None"

    let engine = AudioEngine()

    var drumSamples: [DrumSample] =
        [
            DrumSample(name: "OPEN HI HAT", fileName: "Samples/open_hi_hat_A#1.wav", midiNote: 34),
            DrumSample(name: "HI TOM", fileName: "Samples/hi_tom_D2.wav", midiNote: 38),
            DrumSample(name: "MID TOM", fileName: "Samples/mid_tom_B1.wav", midiNote: 35),
            DrumSample(name: "LO TOM", fileName: "Samples/lo_tom_F1.wav", midiNote: 29),
            DrumSample(name: "CLOSED HI HAT", fileName: "Samples/closed_hi_hat_F#1.wav", midiNote: 30), // Renamed from "HI HAT"
            DrumSample(name: "CLAP", fileName: "Samples/clap_D#1.wav", midiNote: 27),
            DrumSample(name: "SNARE", fileName: "Samples/snare_D1.wav", midiNote: 26),
            DrumSample(name: "KICK", fileName: "Samples/bass_drum_C1.wav", midiNote: 24),
        ]

    let drums = AppleSampler()

    func playPad(padNumber: Int) {
        let midiNote = MIDINoteNumber(drumSamples[padNumber].midiNote)
        print("Playing Pad \(padNumber) with MIDI Note \(midiNote)")
        drums.play(noteNumber: midiNote)
        let fileName = drumSamples[padNumber].fileName
        lastPlayed = fileName.components(separatedBy: "/").last!
    }

    init() {
        engine.output = drums
        do {
            let files = drumSamples.map {
                $0.audioFile!
            }
            try drums.loadAudioFiles(files)

        } catch {
            Log("Files Didn't Load")
        }
    }
}

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
                                .fill(Color(conductor.drumSamples.map { downPads.contains(where: { $0 == row * 4 + column }) ? .gray : $0.color }[getPadId(row: row, column: column)]))
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
            PadsView(conductor: conductor) { pad in
                conductor.playPad(padNumber: pad)
            }

            HStack(spacing: 8) {
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
            self.conductor.start()
        }
        .onDisappear {
            self.conductor.stop()
            self.timer?.invalidate()
            self.timer = nil
        }
    }

    func toggleStep(_ step: Int) {
        // Toggle the state of the button at the given step
        drumSequence[currentStep][step] = drumSequence[currentStep][step] == 0 ? 1 : 0

        // Update the color of the corresponding pad based on the drum hit
        let isHit = drumSequence[currentStep][step] == 1
        let padColor: UIColor = isHit ? .red : .black

        // Update the color of the drum pad
        let padNumber = step
        conductor.drumSamples[padNumber].color = padColor
        conductor.objectWillChange.send()

        // If it's a hit, play the associated pad
        if isHit {
            let padNumber = step
            let sampleName = conductor.drumSamples[padNumber].name
            let midiNote = conductor.drumSamples[padNumber].midiNote
            print("Button \(step + 1) pressed - Sample: \(sampleName), MidiNote: \(midiNote)")
            conductor.playPad(padNumber: padNumber)
        }
    }
    


    func togglePlay() {
        if isPlaying {
            stopSequence()
        } else {
            startSequence()
        }
    }

    func startSequence() {
        currentStep = 0
        isPlaying = true

        self.timer = Timer.scheduledTimer(withTimeInterval: 60.0 / 174.0, repeats: true) { _ in
            self.playStep()
        }
    }

    func playStep() {
        for (index, value) in drumSequence[currentStep].enumerated() {
            if value == 1 {
                conductor.playPad(padNumber: index)
            }
        }
        currentStep = (currentStep + 1) % drumSequence.count
    }

    func stopSequence() {
        currentStep = 0
        isPlaying = false
        self.timer?.invalidate()
        self.timer = nil
    }
}


private func getPadId(row: Int, column: Int) -> Int {
    return (row * 4) + column
}

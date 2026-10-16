# Wardrobe AI — iOS App Implementation Plan

An edge-first, privacy-preserving wardrobe management, live outfit fit-check, and personal stylist app powered 100% on-device by the **Gemma 4** model family (**Gemma 4 E4B / E2B** + **EmbeddingGemma 2**) via **LiteRT-LM**[cite: 1].

**Hackathon Tracks Targeted (Hacktoberfest Hack Day Bengaluru 2026):**
1. **Best Use of Gemma 4 (Google DeepMind Track)** — Uses all 3 native Gemma 4 modalities (Vision, Audio, Text)[cite: 1], native `@ToolParam` function calling[cite: 1], visible `<thought>` channel reasoning[cite: 1], and **EmbeddingGemma 2** (built on Gemma 4) for cross-modal vector search.
2. **Best Open-Source AI Project** — 100% local open-weight AI (`Apache-2.0`)[cite: 1], zero cloud inference dependencies, published in a public GitHub repository.

---

## Design Decisions Summary

| Decision | Choice |
|---|---|
| **Platform** | iOS 18+ / iOS 26 (Swift, SwiftUI)[cite: 1] |
| **Generative On-Device ML** | **Gemma 4 E4B** (8 GB–12 GB RAM iPhones) with automatic fallback to **Gemma 4 E2B** (6 GB RAM iPhones) via **LiteRT-LM** (`LiteRTLM` SPM)[cite: 1] |
| **Multimodal Embeddings** | **EmbeddingGemma 2** (`embeddinggemma-2-740m.litertlm` via `LiteRTLM.EmbeddingEngine`, 768D shared text+image vector space) on 8 GB+ devices; fallback to Apple Vision `VNFeaturePrintObservation` on 6 GB devices |
| **Hardware Acceleration** | Metal GPU (`.gpu`) with Multi-Token Prediction (MTP) speculative decoding + CPU vision/audio executors[cite: 1] |
| **UI Paradigm** | Streamlined 3-Tab App (**Wardrobe**, **Outfits & Schedule**, **Stylist Chat**) |
| **Database** | SQLite via **GRDB.swift** (using SQLite `json_each` for tag/occasion array queries)[cite: 1] |
| **Image Storage** | Cropped transparent PNGs in app Documents directory, 768D embeddings as BLOBs in SQLite[cite: 1] |
| **Image Pre-Processing** | Auto background removal & multi-garment instance cropping (`VNGenerateForegroundInstanceMaskRequest`)[cite: 1] + dominant hex swatch extraction (`CIAreaAverage`) |
| **Capture Flows** | 1) Single-item capture, 2) Multi-item batch crop & scan, 3) **Live Mirror Fit-Check**[cite: 1] |
| **Voice Input** | Native `AVAudioRecorder` (16kHz mono `.wav`) fed directly into Gemma 4's 300M audio encoder (`Content.audioFile`)[cite: 1] |
| **Classification** | Fully automatic multimodal JSON classification (`thinkingTokenBudget: 0` for low latency) with optional tag editing[cite: 1] |
| **Outfit Engine** | Hybrid: Rule-based candidate filtering + `EmbeddingGemma 2` cosine similarity (`Accelerate`/`vDSP`) + Gemma 4 Thinking Ranker[cite: 1] |
| **Wear Logging** | Auto-log on recommendation accept + manual tap-to-log + tool-triggered logging[cite: 1] |
| **Weather & Calendar** | OpenWeatherMap API (free tier) + native `EventKit` schedule context header[cite: 1] |
| **Preferences** | Pre-seeded style profile + quick in-app Style Profile editor sheet + implicit wear history learning[cite: 1] |
| **Model Provisioning** | Sideloaded via Finder/Xcode (`UIFileSharingEnabled`) for instant offline demo + Settings downloader fallback[cite: 1] |
| **Architecture** | MVVM with `@Observable` ViewModels[cite: 1] |
| **Target Hardware** | Primary demo on **iPhone 17 / 17 Pro** (supports iPhone 15+ via dynamic RAM tiering)[cite: 1] |
| **License** | Apache 2.0 (Gemma 4, EmbeddingGemma 2, and project repository)[cite: 1] |

---

## Gemma 4 Ecosystem — Model & Memory Details

> [!NOTE]
> Gemma 4 is Google DeepMind's latest open model family, built from Gemini 3 research[cite: 1]. Alongside the generative **Gemma 4 E2B / E4B** models[cite: 1], we integrate **EmbeddingGemma 2** (built on the Gemma 4 architecture), giving the app 100% Gemma-powered intelligence across generation, tool use, and vector retrieval under the **Apache 2.0 license**[cite: 1].

### Hardware-Aware Model Selection

iOS enforces a strict per-app memory ceiling (`jetsam`). The app inspects `ProcessInfo.processInfo.physicalMemory` at launch to automatically select the optimal model tier and caps the mobile KV cache at `maxNumTokens: 4096`:

| Specification | Gemma 4 E2B (6 GB RAM Fallback) | Gemma 4 E4B ★ (8 GB–12 GB RAM Primary) | EmbeddingGemma 2 ★ (Vector Engine) |
|---|---|---|---|
| **Effective Parameters** | ~2.3 Billion[cite: 1] | ~4.5 Billion[cite: 1] | 740 Million |
| **Total Parameters** | ~5.1 Billion[cite: 1] | ~8.0 Billion[cite: 1] | 740 Million |
| **Quantized Size** | ~1.3 GB (`.litertlm`)[cite: 1] | ~2.8 GB (`.litertlm`)[cite: 1] | ~567 MB (`.litertlm`) |
| **Context / Output** | 128K max (capped at 4K on mobile), Text + `<thought>`[cite: 1] | 128K max (capped at 4K on mobile), Text + `<thought>`[cite: 1] | 768-dimensional normalized `Float` vector |
| **Input Modalities** | Text, Image (150M), Audio (300M)[cite: 1] | Text, Image (150M), Audio (300M)[cite: 1] | Text, Image, Audio (shared vector space) |
| **Target iOS Devices** | iPhone 15, iPhone 15 Plus (6 GB RAM)[cite: 1] | **iPhone 17 / 17 Pro**, iPhone 16 series, iPhone 15 Pro | All 8 GB–12 GB RAM iPhones |

### Key Capabilities Used in Wardrobe AI

- **Native Multimodal Vision (`Content.imageFile`)**: Built-in 150M vision encoder with variable aspect ratio support classifies cropped garments and evaluates full-body outfits in **Live Mirror Fit-Check** mode without a separate CoreML classifier[cite: 1].
- **Cross-Modal Vector Search (`EmbeddingGemma 2`)**: Maps garment photos and natural-language queries (*"breathable blue linen for humid weather"*) into a single 768D vector space.
- **Native Declarative Tool Calling (`LiteRTLM.Tool` & `@ToolParam`)**: Swift structs conform to `Tool`; `LiteRTLM` handles tool schema injection, invocation, and result feed-back automatically[cite: 1].
- **Configurable Thinking Mode (`ThinkingConfig`)**:
  - **Disabled (`thinkingTokenBudget: 0`)** during camera garment classification for sub-second JSON output.
  - **Enabled (`thinkingTokenBudget: 512`)** during outfit ranking and Stylist Chat, surfacing `response.channels["thought"]` in a collapsible **"✨ Stylist Reasoning"** UI banner[cite: 1].
- **Multi-Token Prediction (MTP)**: Hardware-accelerated speculative decoding on Apple Silicon via Metal (`ExperimentalFlags.enableSpeculativeDecoding = true`)[cite: 1].
- **Native Audio Input (`Content.audioFile`)**: Built-in 300M USM/Conformer audio encoder processes spoken `.wav` requests directly without `SFSpeechRecognizer`[cite: 1].

### Runtime: LiteRT-LM (Not MediaPipe)

| Feature | MediaPipe LLM Inference (❌ Legacy) | LiteRT-LM (✅ Current) |
|---|---|---|
| **Status** | Maintenance-only[cite: 1] | Active development[cite: 1] |
| **Gemma 4 & EmbeddingGemma 2** | Limited / legacy[cite: 1] | Full native `Engine` + `EmbeddingEngine` support[cite: 1] |
| **iOS Integration** | CocoaPods (`MediaPipeTasksGenAI`)[cite: 1] | **Swift Package Manager (`LiteRTLM`)**[cite: 1] |
| **Features** | Basic text inference[cite: 1] | MTP acceleration, Metal GPU, streaming, multimodal, `@ToolParam`, `<thought>` channel[cite: 1] |
| **Model Format** | `.task` bundles[cite: 1] | `.litertlm` files[cite: 1] |

**SPM Integration:**
- **Repository**: `https://github.com/google-ai-edge/LiteRT-LM` (Version `0.12.0+`)[cite: 1]
- **Library**: `LiteRTLM`[cite: 1]
- **Model Files (`litert-community` on Hugging Face)**: `gemma-4-E4B-it.litertlm`, `gemma-4-E2B-it.litertlm`, and `embeddinggemma-2-740m.litertlm`[cite: 1].

---

## MVP Feature Scope (v1)

### Included in v1
1. **Add clothes via camera (Single & Batch Scan)** — Multi-instance foreground segmentation (`VNGenerateForegroundInstanceMaskRequest`) crops 1 or multiple garments into transparent PNGs, extracts dominant hex colors, generates 768D `EmbeddingGemma 2` vectors, and auto-tags via Gemma 4[cite: 1].
2. **Wardrobe grid & cross-modal search** — Browse items with extracted hex color accents, filter by category/occasion, or search semantically (*"show me all my breathable blue clothes"*) via `EmbeddingGemma 2` cosine similarity[cite: 1].
3. **Outfits & Today's Context Tab** — Integrated header card displaying live `EventKit` calendar events and `OpenWeatherMap` Bengaluru weather, paired with visual outfit cards[cite: 1].
4. **"What should I wear?" & "What goes with this?"** — Hybrid outfit recommendations combining rule-based filtering, vector compatibility, and Gemma 4 thinking evaluation[cite: 1].
5. **Collapsible `✨ Stylist Reasoning` Pill** — Surfaces Gemma 4's `response.channels["thought"]` reasoning trace directly in the UI.
6. **Live Mirror Fit-Check** — Point the camera at your current outfit; Gemma 4 critiques it against today's weather and upcoming calendar events and recommends a specific swap from your wardrobe.
7. **Multimodal Stylist Chat (Text + Image + Native Voice)** — Conversational agent with `@ToolParam` function calling and hold-to-talk `.wav` audio input (`Content.audioFile`)[cite: 1].
8. **Wear logging & Forgotten Items alerts** — One-tap wear logging and automatic surfacing of underused garments[cite: 1].

### Deferred to v2+
- Multi-screen onboarding quiz (v1 uses pre-seeded style profile + quick Settings editor sheet)[cite: 1]
- Travel packing checklist assistant[cite: 1]
- Shopping gap analysis & external store links[cite: 1]
- iCloud backup & cross-device sync[cite: 1]

---

## Proposed Architecture

### Project Structure

```
WardrobeAI/
├── WardrobeAI.xcodeproj
├── WardrobeAI/
│   ├── App/
│   │   ├── WardrobeAIApp.swift          # App entry point & model initialization
│   │   └── ContentView.swift            # 3-Tab Root View (Wardrobe, Outfits, Chat)
│   │
│   ├── Models/                          # Data models (GRDB records)
│   │   ├── ClothingItem.swift           # Core item model + 768D embedding + hex swatch
│   │   ├── Outfit.swift                 # Outfit model (collection of items + reasoning)
│   │   ├── WearLog.swift                # Wear history record
│   │   ├── CalendarEvent.swift          # EventKit / in-app calendar event model
│   │   ├── UserPreferences.swift        # Style preferences profile
│   │   └── ClothingCategory.swift       # Category/subcategory enums + occasion tags
│   │
│   ├── ViewModels/                      # @Observable ViewModels
│   │   ├── WardrobeViewModel.swift      # Wardrobe CRUD, json_each filtering, vector search
│   │   ├── CameraViewModel.swift        # Camera capture, batch cutout, Gemma classification
│   │   ├── OutfitViewModel.swift        # Weather/Calendar context + outfit generation
│   │   └── ChatViewModel.swift          # Multimodal chat agent, voice input, Mirror Fit-Check
│   │
│   ├── Views/                           # SwiftUI views
│   │   ├── Wardrobe/
│   │   │   ├── WardrobeTabView.swift    # Grid view with category chips & semantic search
│   │   │   ├── ClothingItemCard.swift   # Individual item card with dominantColorHex tint
│   │   │   └── ItemDetailView.swift     # Item detail, edit tags, "What goes with this?"
│   │   ├── Camera/
│   │   │   ├── CameraCaptureView.swift  # Single / Batch / Mirror Fit-Check camera sheet
│   │   │   └── BatchPreviewView.swift   # Cropped garment instances preview + live tagging
│   │   ├── Outfits/
│   │   │   ├── OutfitTabView.swift      # Today's Context header + Outfit recommendations
│   │   │   ├── OutfitCardView.swift     # Visual outfit card (top/bottom/shoes layout)
│   │   │   ├── ReasoningBannerView.swift# Collapsible pill for response.channels["thought"]
│   │   │   └── WearLogView.swift        # Wear history & forgotten items list
│   │   ├── Chat/
│   │   │   ├── ChatTabView.swift        # Chat view + Hold-to-Talk Mic + Mirror Fit-Check
│   │   │   └── ChatMessageView.swift    # Message bubble + tool badge + thought expander
│   │   └── Settings/
│   │       └── StyleProfileSheet.swift  # Style preferences sheet & active model status
│   │
│   ├── Services/                        # Business logic & ML pipelines
│   │   ├── Database/
│   │   │   └── DatabaseManager.swift    # GRDB setup, migrations, json_each, seed loader
│   │   ├── ML/
│   │   │   ├── GemmaService.swift       # LiteRT-LM Engine wrapper (Gemma 4 E4B/E2B)
│   │   │   ├── EmbeddingService.swift   # LiteRT-LM EmbeddingEngine (EmbeddingGemma 2) + vDSP
│   │   │   ├── VisionCutoutService.swift# VNGenerateForegroundInstanceMask + CIAreaAverage Hex
│   │   │   └── AudioRecorder.swift      # AVAudioRecorder wrapper (16kHz mono .wav)
│   │   ├── OutfitEngine/
│   │   │   ├── CandidateGenerator.swift # Rule-based outfit candidate generation
│   │   │   ├── CompatibilityScorer.swift# Embedding cosine similarity + color harmony
│   │   │   └── OutfitRanker.swift       # Gemma 4 thinking evaluation of top candidates
│   │   ├── Context/
│   │   │   ├── WeatherService.swift     # OpenWeatherMap API client
│   │   │   └── CalendarService.swift    # EventKit schedule reader
│   │   └── Agent/
│   │       └── WardrobeTools.swift      # LiteRTLM.Tool definitions with @ToolParam
│   │
│   ├── Utilities/
│   │   ├── ImageUtils.swift             # CVPixelBuffer / UIImage helpers
│   │   └── ColorExtensions.swift        # Hex string to SwiftUI Color conversion
│   │
│   └── Resources/
│       ├── Assets.xcassets
│       └── SeedWardrobe/                # 15 pre-segmented items for instant demo startup
│
├── WardrobeAITests/
└── WardrobeAIUITests/
```

---

## Core Services & Code Specifications

### 1. Generative Multimodal & Agent Service (`GemmaService.swift`)

Wraps `LiteRTLM`'s `Engine` and `Conversation` APIs with Metal GPU execution, MTP speculative decoding, non-thinking fast classification, and thinking-enabled Stylist Chat:

```swift
import Foundation
import LiteRTLM

enum GemmaError: LocalizedError {
    case modelNotFound(String)
    case engineNotReady
}

struct ClothingClassification: Codable {
    let category: String
    let subcategory: String
    let tags: [String]
    let dominant_color: String
    let occasions: [String]
}

struct StyledResponse {
    let answer: String
    let reasoning: String?
}

@Observable
class GemmaService {
    static let shared = GemmaService()
    private(set) var activeModelName: String = "Initializing..."
    private(set) var isReady: Bool = false

    private var engine: Engine?
    private var chatConversation: Conversation?

    /// Dynamically selects Gemma 4 E4B (8GB+ RAM) or E2B (6GB RAM) with Metal GPU + MTP
    func loadModel() async throws {
        ExperimentalFlags.optIntoExperimentalAPIs()
        ExperimentalFlags.enableSpeculativeDecoding = true // Multi-Token Prediction on Metal

        let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
        let modelName = ramGB >= 7.5 ? "gemma-4-E4B-it" : "gemma-4-E2B-it"
        self.activeModelName = ramGB >= 7.5 ? "Gemma 4 E4B (Metal GPU)" : "Gemma 4 E2B (Metal GPU)"

        let modelURL = try resolveModelURL(named: modelName)

        let engineConfig = try EngineConfig(
            modelPath: modelURL.path,
            backend: .gpu,              // Metal GPU acceleration
            visionBackend: .cpu(),      // Required for Gemma 4 multimodal image inputs
            audioBackend: .cpu(),       // Required for Gemma 4 native audio inputs
            maxNumTokens: 4096,         // Mobile-safe KV cache allocation
            cacheDir: NSTemporaryDirectory()
        )

        let newEngine = Engine(engineConfig: engineConfig)
        try await newEngine.initialize()
        self.engine = newEngine
        self.isReady = true
    }

    private func resolveModelURL(named name: String) throws -> URL {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sideloaded = docsDir.appendingPathComponent("\(name).litertlm")
        if FileManager.default.fileExists(atPath: sideloaded.path) {
            return sideloaded
        }
        if let bundled = Bundle.main.url(forResource: name, withExtension: "litertlm") {
            return bundled
        }
        throw GemmaError.modelNotFound(name)
    }

    /// Low-latency multimodal garment classification (Thinking disabled for fast JSON output)
    func classifyClothing(imagePath: String) async throws -> ClothingClassification {
        guard let engine else { throw GemmaError.engineNotReady }

        let config = ConversationConfig(
            systemMessage: Message("You are a fashion taxonomy classifier. Output ONLY raw, valid JSON."),
            samplerConfig: try SamplerConfig(topK: 10, topP: 0.9, temperature: 0.1),
            thinkingConfig: ThinkingConfig(enableThinking: false, thinkingTokenBudget: 0)
        )
        let classifierConv = try await engine.createConversation(with: config)

        let message = Message(contents: [
            Content.imageFile(imagePath),
            Content.text("""
            Classify this clothing item. Return ONLY raw JSON with exact keys:
            {
              "category": "tops|bottoms|footwear|outerwear|accessories",
              "subcategory": "string",
              "tags": ["string"],
              "dominant_color": "string",
              "occasions": ["casual|office|formal|sport|lounge"]
            }
            """)
        ])

        let response = try await classifierConv.sendMessage(message)
        let cleanJSON = response.toString
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return try JSONDecoder().decode(ClothingClassification.self, from: Data(cleanJSON.utf8))
    }

    /// Initializes the Stylist Agent with native @ToolParam tools and a 512-token Thinking Budget
    func startStylistSession(tools: [any Tool], styleProfile: String) async throws {
        guard let engine else { throw GemmaError.engineNotReady }

        let config = ConversationConfig(
            systemMessage: Message("""
            You are Wardrobe AI, an edge-first personal stylist running on-device in Bengaluru.
            User Style Profile: \(styleProfile)
            Always call your tools to check weather, today's schedule, and wardrobe items before recommending outfits.
            When evaluating a Mirror Fit-Check photo, critique the current outfit against today's weather and events, and suggest a specific item swap from the user's wardrobe by ID and name.
            """),
            samplerConfig: try SamplerConfig(topK: 40, topP: 0.95, temperature: 0.7),
            thinkingConfig: ThinkingConfig(enableThinking: true, thinkingTokenBudget: 512),
            tools: tools
        )
        self.chatConversation = try await engine.createConversation(with: config)
    }

    /// Sends text, camera image (Mirror Fit-Check), or spoken .wav audio to Gemma 4
    func sendStylistMessage(
        text: String,
        imagePath: String? = nil,
        audioPath: String? = nil
    ) async throws -> StyledResponse {
        guard let chatConversation else { throw GemmaError.engineNotReady }

        var contents: [Content] = []
        if let imagePath { contents.append(.imageFile(imagePath)) }
        if let audioPath { contents.append(.audioFile(audioPath)) }
        if !text.isEmpty { contents.append(.text(text)) }

        let response = try await chatConversation.sendMessage(Message(contents: contents))
        let thought = response.channels["thought"] as? String
        return StyledResponse(answer: response.toString, reasoning: thought)
    }
}
```

---

### 2. Multimodal Embedding Service (`EmbeddingService.swift`)

Uses **EmbeddingGemma 2** (`embeddinggemma-2-740m.litertlm`) via `LiteRTLM.EmbeddingEngine` to embed garment images and text search queries into a unified 768D vector space, with `Accelerate` (`vDSP`) cosine similarity:

```swift
import Foundation
import Accelerate
import LiteRTLM

class EmbeddingService {
    static let shared = EmbeddingService()
    private var embeddingEngine: EmbeddingEngine?

    /// Loads EmbeddingGemma 2 on 8GB+ devices (iPhone 17 / 17 Pro)
    func initializeIfSupported() async throws {
        let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
        guard ramGB >= 7.5 else { return }

        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelURL = docsDir.appendingPathComponent("embeddinggemma-2-740m.litertlm")
        guard FileManager.default.fileExists(atPath: modelURL.path) else { return }

        let engine = EmbeddingEngine(config: .init(
            modelPath: modelURL.path,
            backend: .gpu,
            visionBackend: .gpu,
            audioBackend: .gpu
        ))
        try await engine.initialize()
        self.embeddingEngine = engine
    }

    /// Generates a 768D vector for a segmented garment image + its semantic tags
    func embedGarment(imagePath: String, description: String) async throws -> [Float] {
        guard let embeddingEngine else { return [] }
        let formatted = "task: search result | text: \(description.trimmingCharacters(in: .whitespacesAndNewlines))"
        let resp = try await embeddingEngine.computeEmbedding(contents: [
            .imageFile(imagePath),
            .text(formatted)
        ])
        return resp.embedding
    }

    /// Generates a 768D vector for a natural-language search query
    func embedSearchQuery(_ query: String) async throws -> [Float] {
        guard let embeddingEngine else { return [] }
        let formatted = "task: search query | text: \(query.trimmingCharacters(in: .whitespacesAndNewlines))"
        let resp = try await embeddingEngine.computeEmbedding(contents: [.text(formatted)])
        return resp.embedding
    }

    /// Hardware-accelerated cosine similarity via Apple Accelerate vDSP (< 0.1ms for 300 items)
    func cosineSimilarity(_ vectorA: [Float], _ vectorB: [Float]) -> Float {
        guard vectorA.count == vectorB.count, !vectorA.isEmpty else { return 0 }
        var dot: Float = 0, normA: Float = 0, normB: Float = 0
        vDSP_dotpr(vectorA, 1, vectorB, 1, &dot, vDSP_Length(vectorA.count))
        vDSP_svesq(vectorA, 1, &normA, vDSP_Length(vectorA.count))
        vDSP_svesq(vectorB, 1, &normB, vDSP_Length(vectorA.count))
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }
}
```

---

### 3. Declarative Function Calling Tools (`WardrobeTools.swift`)

Uses `LiteRTLM`'s native `Tool` protocol and `@ToolParam` property wrappers[cite: 1]:

```swift
import Foundation
import LiteRTLM

struct SearchWardrobeTool: Tool {
    static let name = "search_wardrobe"
    static let description = "Search the user's wardrobe by category, color, or occasion."

    @ToolParam(description: "Category: tops, bottoms, footwear, outerwear, accessories (or empty for all)")
    var category: String = ""

    @ToolParam(description: "Color filter, e.g. blue, black, white, olive (or empty for all)")
    var color: String = ""

    @ToolParam(description: "Occasion: casual, office, formal, sport, lounge (or empty for all)")
    var occasion: String = ""

    func run() async throws -> Any {
        let items = try DatabaseManager.shared.searchItems(
            category: category.isEmpty ? nil : category,
            color: color.isEmpty ? nil : color,
            occasion: occasion.isEmpty ? nil : occasion
        )
        return items.map {
            [
                "id": $0.id ?? 0,
                "category": $0.category,
                "subcategory": $0.subcategory,
                "color": $0.dominantColor,
                "tags": $0.tags.joined(separator: ", "),
                "wearCount": $0.wearCount
            ]
        }
    }
}

struct GetTodayContextTool: Tool {
    static let name = "get_today_context"
    static let description = "Get current weather and today's calendar events for outfit recommendations."

    @ToolParam(description: "City name for weather lookup, default Bengaluru")
    var city: String = "Bengaluru"

    func run() async throws -> Any {
        async let weather = WeatherService.shared.fetchCurrentWeather(city: city)
        async let events = CalendarService.shared.fetchTodayEvents()
        let (w, e) = await (try? weather, events)
        return [
            "weather": w?.summary ?? "28°C, partly cloudy, 65% humidity in Bengaluru",
            "events": e.map { "\($0.title) (\($0.occasion ?? "general"))" }
        ]
    }
}

struct GetRecentlyWornTool: Tool {
    static let name = "get_recently_worn"
    static let description = "Get clothing items worn in the last N days so they can be rotated out."

    @ToolParam(description: "Number of days to look back, default 7")
    var days: Int = 7

    func run() async throws -> Any {
        let items = try DatabaseManager.shared.getRecentlyWorn(days: days)
        return items.map { ["id": $0.id ?? 0, "subcategory": $0.subcategory, "color": $0.dominantColor] }
    }
}

struct RecordWornItemTool: Tool {
    static let name = "record_worn_item"
    static let description = "Log that a clothing item was worn today."

    @ToolParam(description: "Clothing item ID")
    var item_id: Int

    func run() async throws -> Any {
        try DatabaseManager.shared.logWear(itemId: Int64(item_id))
        return ["status": "logged", "item_id": item_id]
    }
}
```

---

### 4. Vision Cutout & Multi-Item Batch Cropping (`VisionCutoutService.swift`)

Uses `VNGenerateForegroundInstanceMaskRequest`[cite: 1] to remove backgrounds and crop multi-item batch scans into separate PNG files, while extracting the dominant UI hex swatch via `CIAreaAverage`:

```swift
import UIKit
import Vision
import CoreImage

struct CutoutGarment {
    let imagePath: String
    let dominantColorHex: String
    let visionFeaturePrint: Data?
}

class VisionCutoutService {
    static let shared = VisionCutoutService()
    private let ciContext = CIContext()

    /// Isolates 1 or multiple garments, saves each as a transparent PNG, and extracts its dominant hex color
    func extractGarments(from image: UIImage, allowBatch: Bool) throws -> [CutoutGarment] {
        guard let cgImage = image.cgImage else { return [] }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first else { return [] }
        let instances = allowBatch ? observation.allInstances : IndexSet(integer: 1)

        var cutouts: [CutoutGarment] = []
        for index in instances {
            let pixelBuffer = try observation.generateMaskedImage(
                ofInstances: IndexSet(integer: index),
                from: handler,
                croppedToInstancesExtent: true
            )

            // Fallback FeaturePrint for 6GB devices
            let fpRequest = VNGenerateImageFeaturePrintRequest()
            let cropHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try? cropHandler.perform([fpRequest])
            let fpData = try? fpRequest.results?.first.flatMap {
                try NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
            }

            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let hex = extractDominantHex(from: ciImage)
            let path = try saveCutoutPNG(ciImage: ciImage)

            cutouts.append(CutoutGarment(
                imagePath: path,
                dominantColorHex: hex,
                visionFeaturePrint: fpData
            ))
        }
        return cutouts
    }
}
```

---

### 5. Data Models & SQLite `json_each` Queries (`DatabaseManager.swift`)

```swift
import Foundation
import GRDB

// ClothingItem — core wardrobe item
struct ClothingItem: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var imagePath: String           // Relative path to cutout PNG in Documents dir
    var category: String            // "tops", "bottoms", "footwear", "outerwear", "accessories"
    var subcategory: String         // "t-shirt", "linen shirt", "jeans", etc.
    var tags: [String]              // Free-form AI-generated tags: ["casual", "blue", "linen"]
    var occasions: [String]         // ["casual", "office", "formal", "sport", "lounge"]
    var dominantColor: String       // Semantic color from Gemma 4 ("navy blue")
    var dominantColorHex: String    // UI hex swatch from CoreImage ("#1B2A4A")
    var embedding: Data?            // 768D EmbeddingGemma 2 [Float] vector as raw bytes
    var featurePrintFallback: Data? // Optional VNFeaturePrintObservation fallback
    var createdAt: Date
    var lastWornAt: Date?
    var wearCount: Int
}

// WearLog — tracks when items were worn
struct WearLog: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var clothingItemId: Int64
    var outfitId: Int64?
    var wornDate: Date
}

// Outfit — a saved combination of items
struct Outfit: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var name: String?
    var itemIds: [Int64]
    var occasion: String?
    var reasoningSummary: String?   // Stored Gemma 4 <thought> trace
    var createdAt: Date
    var isFavorite: Bool
}

// CalendarEvent — imported EventKit or manual event
struct CalendarEvent: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var title: String
    var date: Date
    var occasion: String?
    var linkedOutfitId: Int64?
    var sourceEventId: String?
}

// UserPreferences — style preferences
struct UserPreferences: Codable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var preferredColors: [String]
    var avoidedColors: [String]
    var preferredStyles: [String]
    var defaultFormality: String    // "casual", "smart-casual", "formal"
}
```

---

## ML Pipelines

### 1. Clothing Classification & Batch Cutout Flow
```
Camera Capture (AVCaptureSession stopped immediately after capture to free RAM)
    → VisionCutoutService (VNGenerateForegroundInstanceMaskRequest extracts 1..N garment cutouts)
    → CoreImage CIAreaAverage (extracts dominant hex swatch per garment)
    → Gemma 4 E4B Multimodal (Content.imageFile + JSON prompt, thinkingTokenBudget: 0)
    → EmbeddingGemma 2 (computes 768D multimodal vector from cutout + tags)
    → Save ClothingItem + 768D embedding BLOB to SQLite
```

### 2. Outfit Recommendation Pipeline
```
User taps "What should I wear today?" (or asks via Hold-to-Talk Voice .wav)
    → Pre-load UserPreferences + Recently Worn items (last 7 days)
    → Gemma 4 Native Function Calling (@ToolParam):
        → get_today_context() → OpenWeatherMap + EventKit today's events
        → search_wardrobe() → SQLite json_each candidate items
    → CandidateGenerator: Rule-based weather + occasion + cooldown filtering
    → CompatibilityScorer: EmbeddingGemma 2 cosine similarity (vDSP) + color harmony
    → OutfitRanker: Gemma 4 evaluates top candidates (thinkingTokenBudget: 512)
    → UI displays visual OutfitCardView + collapsible "✨ Stylist Reasoning" (channels["thought"])
```

### 3. Live Mirror Fit-Check Pipeline
```
User points camera at current outfit in Mirror Fit-Check mode
    → Full-frame photo + Today's Weather/Calendar context + Wardrobe summary sent to Gemma 4 E4B
    → Gemma 4 reasons in <thought> channel about formality, weather comfort, and color clash
    → Gemma 4 calls search_wardrobe() to find a better matching piece owned by the user
    → Returns critique + specific item swap card (e.g., "Swap hoodie for Navy Linen Shirt #4")
```

---

## Tab Structure

| Tab | Icon | Primary Function |
|---|---|---|
| **Wardrobe** | 👕 `tshirt` | Grid view of all items with hex accents, semantic search (`EmbeddingGemma 2`), category filters, "+" Camera capture (Single & Batch)[cite: 1] |
| **Outfits** | ✨ `sparkles` | "Today in Bengaluru" Weather & `EventKit` Calendar header, daily outfit cards, collapsible `✨ Stylist Reasoning` pill, Wear Logging[cite: 1] |
| **Stylist Chat** | 💬 `message` | Conversational Gemma 4 agent with `@ToolParam` tools, Hold-to-Talk `.wav` voice button, and **Live Mirror Fit-Check** camera trigger[cite: 1] |

---

## Model Provisioning Strategy

1. **Hackathon Demo Mode (Instant Startup)**: Enable `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` in `Info.plist`. Sideload `gemma-4-E4B-it.litertlm` (~2.8 GB)[cite: 1] and `embeddinggemma-2-740m.litertlm` (~567 MB) directly into the app's Documents directory on your iPhone 17 / 17 Pro via Finder or Xcode Devices window.
2. **Production / Judge Repo Fallback**: Include a "Model Manager" section in `StyleProfileSheet.swift` that displays active model status and provides a one-tap `URLSession` download from Hugging Face (`litert-community`) if the files are not yet present in Documents[cite: 1].

---

## Verification Plan

### Automated Tests
- Unit tests for `CandidateGenerator` outfit rules (no conflicting categories, weather suitability, recently-worn cooldown exclusion)[cite: 1].
- Unit tests for `DatabaseManager` CRUD operations and `json_each` array filtering[cite: 1].
- Unit tests for `EmbeddingService.cosineSimilarity` vector math using `Accelerate`/`vDSP`[cite: 1].
- Integration tests for `WardrobeTools` `@ToolParam` execution against an in-memory GRDB database[cite: 1].

### Manual Verification (iPhone 17 / 17 Pro)
- Verify `GemmaService.loadModel()` and `EmbeddingService.initializeIfSupported()` memory footprint in Xcode Instruments (< 3.5 GB peak RAM)[cite: 1].
- Measure single-garment cutout + Gemma 4 JSON classification latency (`thinkingTokenBudget: 0`, target < 2.5s)[cite: 1].
- Test multi-item batch scan with 2–3 well-separated garments laid on a flat surface[cite: 1].
- Verify collapsible `✨ Stylist Reasoning` banner renders `response.channels["thought"]` cleanly[cite: 1].
- Verify Hold-to-Talk `.wav` voice recording triggers Gemma 4's native audio encoder (`Content.audioFile`) and invokes `@ToolParam` tools accurately[cite: 1].
- Verify **Live Mirror Fit-Check** recommends an actual item stored in the local SQLite database.
import SwiftUI
import UniformTypeIdentifiers

public struct LibraryGridView: View {
    @StateObject private var progressManager = ReadingProgressManager.shared
    
    @State private var sampleComics: [ComicBook] = []
    @State private var importedComics: [ComicBook] = []
    
    // Import states
    @State private var showImportSheet: Bool = false
    @State private var importTitle: String = ""
    @State private var importAuthor: String = ""
    @State private var importDirection: ReadingDirection = .leftToRight
    @State private var showFilePicker: Bool = false
    @State private var isImporting: Bool = false
    @State private var importError: String? = nil
    @State private var droppedFileURL: URL? = nil
    
    // Drag-over hover indicators
    @State private var isDraggingOver = false
    
    let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 170), spacing: 20)
    ]
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // Dark elegant bookshelf background
            Color(red: 0.05, green: 0.05, blue: 0.08)
                .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Title Bar
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("All Comics")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                            Text("Drag and drop a .cbz file here or click Import to expand your library")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        GlassyButton(icon: "plus.circle", label: "Import Comic") {
                            importTitle = ""
                            importAuthor = ""
                            importDirection = .leftToRight
                            importError = nil
                            droppedFileURL = nil
                            showImportSheet = true
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)
                    
                    // Preloaded Classics
                    if !sampleComics.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Sample Classics")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal)
                            
                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(sampleComics) { book in
                                    let progress = progressManager.getProgress(for: book.id)
                                    NavigationLink(destination: DesktopReaderView(book: book)) {
                                        ComicCard(book: book, progress: progress)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Custom Imports
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Custom Imports")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal)
                        
                        if importedComics.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 36))
                                    .foregroundColor(.gray.opacity(0.4))
                                
                                Text("No custom imports. Drag and drop any CBZ/ZIP file from Finder to begin.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 50)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.01))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(isDraggingOver ? Color.cyan : Color.white.opacity(0.04), lineWidth: 1.5)
                                            .animation(.easeInOut(duration: 0.25), value: isDraggingOver)
                                    )
                            )
                            .padding(.horizontal)
                        } else {
                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(importedComics) { book in
                                    let progress = progressManager.getProgress(for: book.id)
                                    NavigationLink(destination: DesktopReaderView(book: book)) {
                                        ComicCard(book: book, progress: progress)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            
            // Drag and drop overlay visual indicator
            if isDraggingOver {
                ZStack {
                    Color.black.opacity(0.4)
                    
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10, 10]))
                        .background(Color.cyan.opacity(0.05))
                        .padding(20)
                        .overlay(
                            VStack(spacing: 12) {
                                Image(systemName: "plus.square.fill.on.square.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.cyan)
                                Text("Drop to Import Comic")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        )
                }
                .transition(.opacity)
                .edgesIgnoringSafeArea(.all)
            }
        }
        .onAppear {
            loadAllComics()
        }
        // Finder Drag and Drop destination
        .dropDestination(for: URL.self) { urls, location in
            isDraggingOver = false
            guard let firstUrl = urls.first else { return false }
            let ext = firstUrl.pathExtension.lowercased()
            if ext == "zip" || ext == "cbz" {
                importTitle = firstUrl.deletingPathExtension().lastPathComponent
                importAuthor = "Finder Drag-and-Drop"
                importDirection = .leftToRight
                importError = nil
                droppedFileURL = firstUrl
                showImportSheet = true
                return true
            }
            return false
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.2)) {
                isDraggingOver = targeted
            }
        }
        // Custom Dialog Config Sheet
        .sheet(isPresented: $showImportSheet) {
            NavigationStack {
                Form {
                    Section("Comic Configurations") {
                        TextField("Book Title", text: $importTitle)
                        TextField("Author / Publisher", text: $importAuthor)
                        Picker("Reading Direction", selection: $importDirection) {
                            ForEach(ReadingDirection.allCases) { dir in
                                Text(dir.rawValue).tag(dir)
                            }
                        }
                    }
                    
                    if let error = importError {
                        Section {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    
                    Section {
                        if isImporting {
                            HStack {
                                Spacer()
                                ProgressView("Importing and extracting panel boundaries...")
                                Spacer()
                            }
                        } else {
                            Button("Select File & Complete Import") {
                                if importTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    importError = "Please enter a book title first."
                                } else if let droppedURL = droppedFileURL {
                                    // Complete drag and drop file import
                                    performFileImport(fileURL: droppedURL)
                                } else {
                                    importError = nil
                                    showFilePicker = true
                                }
                            }
                            .foregroundColor(.cyan)
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Import Settings")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showImportSheet = false
                        }
                    }
                }
                .disabled(isImporting)
            }
            .frame(width: 450, height: 320)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.zip, UTType(filenameExtension: "cbz") ?? .zip],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let fileURL = urls.first else { return }
                performFileImport(fileURL: fileURL)
            case .failure(let error):
                importError = "File picker failed: \(error.localizedDescription)"
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("trigger_comic_import"))) { _ in
            importTitle = ""
            importAuthor = ""
            importDirection = .leftToRight
            importError = nil
            droppedFileURL = nil
            showImportSheet = true
        }
    }
    
    private func loadAllComics() {
        self.sampleComics = SampleComicBuilder.buildSampleComics()
        self.importedComics = ComicImporter.shared.loadImportedComics()
        progressManager.loadProgress()
    }
    
    private func performFileImport(fileURL: URL) {
        isImporting = true
        Task {
            do {
                let authorName = importAuthor.isEmpty ? "Unknown Author" : importAuthor
                _ = try await ComicImporter.shared.importComic(
                    from: fileURL,
                    title: importTitle,
                    author: authorName,
                    direction: importDirection
                )
                
                loadAllComics()
                isImporting = false
                showImportSheet = false
            } catch {
                importError = "Import failed: \(error.localizedDescription)"
                isImporting = false
            }
        }
    }
}

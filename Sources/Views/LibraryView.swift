import SwiftUI
import UniformTypeIdentifiers

public struct LibraryView: View {
    @StateObject private var progressManager = ReadingProgressManager.shared
    
    @State private var sampleComics: [ComicBook] = []
    @State private var importedComics: [ComicBook] = []
    @State private var selectedBook: ComicBook? = nil
    
    // Import states
    @State private var showImportSheet: Bool = false
    @State private var importTitle: String = ""
    @State private var importAuthor: String = ""
    @State private var importDirection: ReadingDirection = .leftToRight
    @State private var showFilePicker: Bool = false
    @State private var isImporting: Bool = false
    @State private var importError: String? = nil
    
    let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 170), spacing: 20)
    ]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                // Background Gradient
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.08, blue: 0.12), Color(red: 0.03, green: 0.03, blue: 0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header Banner
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Panel Reader")
                                    .font(.system(size: 32, weight: .black))
                                    .foregroundColor(.white)
                                Text("A premium guided-view comic reader")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            // Import Button
                            GlassyButton(icon: "plus.circle.fill", label: "Import CBZ") {
                                importTitle = ""
                                importAuthor = ""
                                importDirection = .leftToRight
                                importError = nil
                                showImportSheet = true
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                        
                        // Sample Comics Section
                        if !sampleComics.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Preloaded Classics")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white.opacity(0.85))
                                    .padding(.horizontal)
                                
                                LazyVGrid(columns: columns, spacing: 20) {
                                    ForEach(sampleComics) { book in
                                        let progress = progressManager.getProgress(for: book.id)
                                        NavigationLink(destination: ReaderView(book: book)) {
                                            ComicCard(book: book, progress: progress)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // Imported Comics Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("My Imported Bookshelf")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal)
                            
                            if importedComics.isEmpty {
                                VStack(spacing: 16) {
                                    Image(systemName: "books.vertical.fill")
                                        .font(.system(size: 44))
                                        .foregroundColor(.gray.opacity(0.4))
                                    
                                    Text("Your imported bookshelf is empty.")
                                        .font(.system(size: 14))
                                        .foregroundColor(.gray)
                                    
                                    Button("Import Custom Comic") {
                                        showImportSheet = true
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                                .background(Color.white.opacity(0.01))
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.03), lineWidth: 1)
                                )
                                .padding(.horizontal)
                            } else {
                                LazyVGrid(columns: columns, spacing: 20) {
                                    ForEach(importedComics) { book in
                                        let progress = progressManager.getProgress(for: book.id)
                                        NavigationLink(destination: ReaderView(book: book)) {
                                            ComicCard(book: book, progress: progress)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
            .onAppear {
                loadAllComics()
            }
            // Import Metadata Sheet
            .sheet(isPresented: $showImportSheet) {
                NavigationStack {
                    Form {
                        Section("Comic Metadata") {
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
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        }
                        
                        Section {
                            if isImporting {
                                HStack {
                                    Spacer()
                                    ProgressView("Processing & Slicing Panels...")
                                    Spacer()
                                }
                            } else {
                                Button("Select Comic File (.cbz / .zip)") {
                                    if importTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        importError = "Please enter a book title first."
                                    } else {
                                        importError = nil
                                        showFilePicker = true
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.cyan)
                                .font(.system(size: 16, weight: .bold))
                            }
                        }
                    }
                    .navigationTitle("Import Custom Comic")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showImportSheet = false
                            }
                        }
                    }
                    .disabled(isImporting)
                }
                .presentationDetents([.medium])
            }
            // Document File Picker
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.zip, UTType(filenameExtension: "cbz") ?? .zip],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let fileURL = urls.first else { return }
                    
                    // Access security scoped resource if needed (on iOS)
                    let shouldAccess = fileURL.startAccessingSecurityScopedResource()
                    
                    isImporting = true
                    Task {
                        do {
                            let authorName = importAuthor.isEmpty ? "Custom Import" : importAuthor
                            _ = try await ComicImporter.shared.importComic(
                                from: fileURL,
                                title: importTitle,
                                author: authorName,
                                direction: importDirection
                            )
                            
                            // Refresh list and dismiss sheet
                            loadAllComics()
                            isImporting = false
                            showImportSheet = false
                            
                            if shouldAccess {
                                fileURL.stopAccessingSecurityScopedResource()
                            }
                        } catch {
                            importError = "Import failed: \(error.localizedDescription)"
                            isImporting = false
                            if shouldAccess {
                                fileURL.stopAccessingSecurityScopedResource()
                            }
                        }
                    }
                case .failure(let error):
                    importError = "File selection failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func loadAllComics() {
        self.sampleComics = SampleComicBuilder.buildSampleComics()
        self.importedComics = ComicImporter.shared.loadImportedComics()
        progressManager.loadProgress()
    }
}

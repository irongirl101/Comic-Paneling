import SwiftUI

public enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case library = "Bookshelf"
    case preferences = "Preferences"
    
    public var id: String { self.rawValue }
    
    public var icon: String {
        switch self {
        case .library: return "books.vertical.fill"
        case .preferences: return "gearshape.fill"
        }
    }
}

public struct MainSplitView: View {
    @State private var selectedItem: SidebarItem? = .library
    @State private var activeBook: ComicBook? = nil
    
    public init() {}
    
    public var body: some View {
        Group {
            if let book = activeBook {
                DesktopReaderView(book: book, onDismiss: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        activeBook = nil
                    }
                })
                .transition(.opacity)
            } else {
                NavigationSplitView {
                    List(SidebarItem.allCases, selection: $selectedItem) { item in
                        NavigationLink(value: item) {
                            Label(item.rawValue, systemImage: item.icon)
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .listStyle(.sidebar)
                    .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 240)
                    
                    // Branding watermark at sidebar bottom
                    VStack {
                        Spacer()
                        HStack(spacing: 6) {
                            if let logoURL = Bundle.module.url(forResource: "Panels", withExtension: "png"),
                               let nsImage = NSImage(contentsOf: logoURL) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 16, height: 16)
                                    .cornerRadius(4)
                            } else {
                                Image(systemName: "book.closed.fill")
                                    .foregroundColor(.cyan)
                            }
                            Text("Panels")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)
                        }
                        .padding(.bottom, 12)
                    }
                } detail: {
                    switch selectedItem {
                    case .library, .none:
                        LibraryGridView(activeBook: $activeBook)
                    case .preferences:
                        SettingsView()
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

struct SettingsView: View {
    @StateObject private var progressManager = ReadingProgressManager.shared
    
    @State private var defaultViewMode: DesktopViewMode = .guided
    @State private var autoSpotlightOpacity: Double = 0.80
    @State private var showConfirmReset = false
    @State private var showConfirmClearImports = false
    
    var body: some View {
        Form {
            Section("Reading Configuration") {
                Picker("Default Layout Mode", selection: $defaultViewMode) {
                    ForEach(DesktopViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .onChange(of: defaultViewMode) { oldValue, newValue in
                    UserDefaults.standard.set(newValue.rawValue, forKey: "default_view_mode")
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Spotlight Overlay Shade")
                        Spacer()
                        Text("\(Int(autoSpotlightOpacity * 100))%")
                            .foregroundColor(.gray)
                    }
                    Slider(value: $autoSpotlightOpacity, in: 0.3...0.9, step: 0.05)
                        .onChange(of: autoSpotlightOpacity) { oldValue, newValue in
                            UserDefaults.standard.set(newValue, forKey: "spotlight_opacity")
                        }
                }
            }
            
            Section("Data Maintenance") {
                Button("Reset Reading Progress") {
                    showConfirmReset = true
                }
                .buttonStyle(.bordered)
                .alert("Reset Reading Progress?", isPresented: $showConfirmReset) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        UserDefaults.standard.removeObject(forKey: "comic_panel_reader_progress")
                        progressManager.loadProgress()
                    }
                } message: {
                    Text("This will wipe all bookmark bookmarks and return all books to Page 1.")
                }
                
                Button("Delete All Custom Imports", role: .destructive) {
                    showConfirmClearImports = true
                }
                .buttonStyle(.bordered)
                .alert("Wipe Custom Books?", isPresented: $showConfirmClearImports) {
                    Button("Cancel", role: .cancel) {}
                    Button("Wipe Bookshelf", role: .destructive) {
                        try? FileManager.default.removeItem(at: ComicImporter.comicsDirectory)
                        // Reload lists by posting notification or standard state refresh
                    }
                } message: {
                    Text("This permanently deletes all unzipped imported .cbz files and metadata from the application support directory.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .background(Color(red: 0.04, green: 0.04, blue: 0.06))
        .onAppear {
            if let rawMode = UserDefaults.standard.string(forKey: "default_view_mode"),
               let mode = DesktopViewMode(rawValue: rawMode) {
                defaultViewMode = mode
            }
            if let opacity = UserDefaults.standard.object(forKey: "spotlight_opacity") as? Double {
                autoSpotlightOpacity = opacity
            }
        }
    }
}

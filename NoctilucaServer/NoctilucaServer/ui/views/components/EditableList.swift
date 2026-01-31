//
//  EditableList.swift
//  NoctilucaServer
//
//  Created by Gemini on 1/31/26.
//

import SwiftUI

/// A generic list component that supports display, selection, addition, deletion, reordering, and editing of items.
///
/// This component abstracts the common pattern of:
/// - Title and description header
/// - List with selection support
/// - Add/Remove/Edit buttons
/// - Sheets for adding and editing items
struct EditableList<Item, ID, RowContent, AddSheet, EditSheet>: View
where ID: Hashable, RowContent: View, AddSheet: View, EditSheet: View {
    
    // MARK: - Data
    
    /// The collection of items to display and manage.
    @Binding var items: [Item]
    
    /// Key path to the stable identity of the item.
    let idKeyPath: KeyPath<Item, ID>
    
    /// The set of selected item IDs.
    @Binding var selection: Set<ID>
    
    // MARK: - Configuration
    
    let title: String?
    let description: String?
    
    /// Text for the empty state.
    var emptyText: String
    
    // MARK: - View Builders
    
    @ViewBuilder let rowContent: (Item) -> RowContent
    @ViewBuilder let addSheet: (@escaping (Item) -> Void) -> AddSheet
    @ViewBuilder let editSheet: (Item, @escaping (Item) -> Void) -> EditSheet
    
    // MARK: - Internal State
    
    @State private var isAddSheetPresented = false
    @State private var isEditSheetPresented = false
    
    // MARK: - Type Erasure Helpers
    
    private var canAdd: Bool {
        return !(AddSheet.self == EmptyView.self)
    }
    
    private var canEdit: Bool {
        return !(EditSheet.self == EmptyView.self)
    }
    
    // MARK: - Init
    
    init(
        items: Binding<[Item]>,
        id: KeyPath<Item, ID>,
        selection: Binding<Set<ID>>,
        title: String? = nil,
        description: String? = nil,
        emptyText: String = "목록이 비어있습니다.",
        @ViewBuilder rowContent: @escaping (Item) -> RowContent,
        @ViewBuilder addSheet: @escaping (@escaping (Item) -> Void) -> AddSheet,
        @ViewBuilder editSheet: @escaping (Item, @escaping (Item) -> Void) -> EditSheet
    ) {
        self._items = items
        self.idKeyPath = id
        self._selection = selection
        self.title = title
        self.description = description
        self.emptyText = emptyText
        self.rowContent = rowContent
        self.addSheet = addSheet
        self.editSheet = editSheet
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            if let title = title {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        // Using standard font style from existing views if possible, or defaulting
                        // Existing views used various styles, sticking to container default might be best,
                        // but `CodecSpecificationListContainer` used implicit font logic (inherited?).
                        // Let's assume standard Text is fine, but maybe apply .headline?
                        // `Codec...` used Text(markdown: ...) which implies parsing.
                        // We'll trust the caller to provide styled Text or use default.
                }
            }
            if let description = description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // List
            listBody
            
            // Footer Actions
            HStack {
                Spacer()
                
                // Delete Button
                Button("삭제", role: .destructive) {
                    removeSelected()
                }
                .disabled(selection.isEmpty)
                
                // Edit Button (Only visible if EditSheet is provided and 1 item is selected)
                if canEdit {
                    Button("편집") {
                        if selection.count == 1 {
                            isEditSheetPresented = true
                        }
                    }
                    .disabled(selection.count != 1)
                }
                
                // Add Button (Only visible if AddSheet is provided)
                if canAdd {
                    Button("추가") {
                        isAddSheetPresented = true
                    }
                }
            }
        }
        // Edit Sheet
        .sheet(isPresented: $isEditSheetPresented) {
            if let id = selection.first,
               let item = items.first(where: { $0[keyPath: idKeyPath] == id }) {
                editSheet(item) { newItem in
                    if let index = items.firstIndex(where: { $0[keyPath: idKeyPath] == id }) {
                        items[index] = newItem
                    }
                    // Do not clear selection after edit to allow continued editing if needed,
                    // or maybe we should? Existing logic didn't clear.
                    isEditSheetPresented = false
                }
            } else {
                // Selection became invalid?
                Text("항목을 찾을 수 없습니다.")
                    .onAppear { isEditSheetPresented = false }
            }
        }
        // Add Sheet
        .sheet(isPresented: $isAddSheetPresented) {
            addSheet { newItem in
                items.append(newItem)
                isAddSheetPresented = false
            }
        }
    }
    
    @ViewBuilder
    private var listBody: some View {
        List(selection: $selection) {
            if items.isEmpty {
                 // Empty State within List or outside?
                 // Existing views put Text inside List when empty (CredentialsListContainer)
                 // or just empty list.
                 // Let's put a simple text row if empty.
                 Text(emptyText)
                     .foregroundStyle(.secondary)
            } else {
                ForEach(items, id: idKeyPath) { item in
                    // In existing views, there was a workaround for Edit button inside the row
                    // "if (selection.first == specification.hashValue) { ... Edit Button }"
                    // Since we moved Edit button to the footer (standard macOS/iOS pattern),
                    // we just render the row.
                    rowContent(item)
                        .tag(item[keyPath: idKeyPath])
                }
                .onMove(perform: moveItems)
            }
        }
        .listStyle(.inset)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
    }
    
    private func moveItems(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }
    
    private func removeSelected() {
        guard !selection.isEmpty else { return }
        items.removeAll { selection.contains($0[keyPath: idKeyPath]) }
        selection.removeAll()
    }
}

// MARK: - Convenience Inits

extension EditableList where AddSheet == EmptyView {
    init(
        items: Binding<[Item]>,
        id: KeyPath<Item, ID>,
        selection: Binding<Set<ID>>,
        title: String? = nil,
        description: String? = nil,
        emptyText: String = "목록이 비어있습니다.",
        @ViewBuilder rowContent: @escaping (Item) -> RowContent,
        @ViewBuilder editSheet: @escaping (Item, @escaping (Item) -> Void) -> EditSheet
    ) {
        self.init(
            items: items,
            id: id,
            selection: selection,
            title: title,
            description: description,
            emptyText: emptyText,
            rowContent: rowContent,
            addSheet: { _ in EmptyView() },
            editSheet: editSheet
        )
    }
}

extension EditableList where EditSheet == EmptyView {
    init(
        items: Binding<[Item]>,
        id: KeyPath<Item, ID>,
        selection: Binding<Set<ID>>,
        title: String? = nil,
        description: String? = nil,
        emptyText: String = "목록이 비어있습니다.",
        @ViewBuilder rowContent: @escaping (Item) -> RowContent,
        @ViewBuilder addSheet: @escaping (@escaping (Item) -> Void) -> AddSheet
    ) {
        self.init(
            items: items,
            id: id,
            selection: selection,
            title: title,
            description: description,
            emptyText: emptyText,
            rowContent: rowContent,
            addSheet: addSheet,
            editSheet: { _, _ in EmptyView() }
        )
    }
}

extension EditableList where AddSheet == EmptyView, EditSheet == EmptyView {
    init(
        items: Binding<[Item]>,
        id: KeyPath<Item, ID>,
        selection: Binding<Set<ID>>,
        title: String? = nil,
        description: String? = nil,
        emptyText: String = "목록이 비어있습니다.",
        @ViewBuilder rowContent: @escaping (Item) -> RowContent
    ) {
        self.init(
            items: items,
            id: id,
            selection: selection,
            title: title,
            description: description,
            emptyText: emptyText,
            rowContent: rowContent,
            addSheet: { _ in EmptyView() },
            editSheet: { _, _ in EmptyView() }
        )
    }
}

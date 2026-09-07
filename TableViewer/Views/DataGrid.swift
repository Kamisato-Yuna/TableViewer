import SwiftUI
import AppKit

struct DataGrid: NSViewRepresentable {
    var columns: [ColumnInfo]
    var rows: [DataRow]
    var selectedID: UUID?
    var sortColumn: String? = nil
    var ascending = true
    var selection: (UUID?) -> Void = { _ in }
    var sort: (String) -> Void = { _ in }
    var doubleClick: () -> Void = {}

    // Nil preserves the single-selection API for existing query result consumers.
    var selectedIDs: Set<UUID>? = nil
    var selectionChanged: ((Set<UUID>) -> Void)? = nil
    // The store must check read-only state, primary keys and BLOBs before editing.
    var editCell: ((UUID, Int) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true; scroll.borderType = .noBorder
        let table = NSTableView()
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.rowHeight = 38; table.intercellSpacing = NSSize(width: 14, height: 0)
        table.usesAlternatingRowBackgroundColors = true
        table.style = .plain; table.backgroundColor = .controlBackgroundColor
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsMultipleSelection = true; table.allowsEmptySelection = true
        table.allowsColumnReordering = true; table.allowsColumnResizing = true
        table.selectionHighlightStyle = .regular
        table.target = context.coordinator; table.doubleAction = #selector(Coordinator.openInspector(_:))
        table.setAccessibilityLabel(String(localized: "数据库记录表格"))
        scroll.documentView = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? NSTableView else { return }
        let coordinator = context.coordinator
        let old = coordinator.parent
        coordinator.parent = self
        coordinator.updating = true
        defer { coordinator.updating = false }
        let newIdentifiers = ["__row_number__"] + columns.indices.map { "column:\($0)" }
        let currentIdentifiers = table.tableColumns.map { $0.identifier.rawValue }
        let changed = Set(currentIdentifiers) != Set(newIdentifiers) || old.columns.map(\.name) != columns.map(\.name) || old.columns.map(\.isPrimaryKey) != columns.map(\.isPrimaryKey)
        if changed {
            table.tableColumns.forEach { table.removeTableColumn($0) }
            let rowColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("__row_number__"))
            rowColumn.title = "#"; rowColumn.width = 42; rowColumn.minWidth = 32
            table.addTableColumn(rowColumn)
            for (index, info) in columns.enumerated() {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column:\(index)"))
                column.title = (info.isPrimaryKey ? "⌑  " : "") + info.name
                column.minWidth = 70
                column.width = info.name == "id" ? 62 : info.name == "name" || info.name == "title" || info.name == "_id" ? 215 : info.name.contains("_at") || info.name == "email" ? 180 : 145
                column.sortDescriptorPrototype = NSSortDescriptor(key: info.name, ascending: true)
                column.headerCell.font = .systemFont(ofSize: 11, weight: .medium)
                table.addTableColumn(column)
            }
        }
        if changed || old.rows.map(\.id) != rows.map(\.id) || old.rows.map(\.cells) != rows.map(\.cells) { table.reloadData() }
        table.allowsMultipleSelection = selectedIDs != nil || selectionChanged != nil
        let ids = selectedIDs ?? Set(selectedID.map { [$0] } ?? [])
        let indexes = IndexSet(rows.indices.filter { ids.contains(rows[$0].id) })
        // Re-selecting the same indexes resets AppKit's Shift-selection anchor.
        if table.selectedRowIndexes != indexes {
            table.selectRowIndexes(indexes, byExtendingSelection: false)
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: DataGrid
        var updating = false
        init(_ parent: DataGrid) { self.parent = parent }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.rows.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.rows.count, let tableColumn else { return nil }
            let identifier = tableColumn.identifier
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? NSTableCellView()
            cell.identifier = identifier
            if cell.textField == nil {
                let label = NSTextField(labelWithString: "")
                label.translatesAutoresizingMaskIntoConstraints = false
                label.lineBreakMode = .byTruncatingTail
                cell.addSubview(label); cell.textField = label
                NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 5), label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
            }
            guard let label = cell.textField else { return cell }
            label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .labelColor
            if identifier.rawValue == "__row_number__" {
                label.stringValue = String(row + 1); label.textColor = .tertiaryLabelColor
            } else if identifier.rawValue.hasPrefix("column:"), let index = Int(identifier.rawValue.dropFirst(7)), parent.columns.indices.contains(index), index < parent.rows[row].cells.count {
                let value = parent.rows[row].cells[index]
                label.stringValue = value.display
                if value.isNull { label.textColor = .tertiaryLabelColor; label.font = .monospacedSystemFont(ofSize: 10, weight: .light) }
                else if parent.columns[index].name == "name" || parent.columns[index].name == "title" { label.font = .systemFont(ofSize: 12, weight: .medium) }
                else if parent.columns[index].name == "status" {
                    label.font = .systemFont(ofSize: 11, weight: .medium)
                    label.textColor = value.display == "已完成" ? .systemGreen : value.display == "进行中" ? .systemBlue : .secondaryLabelColor
                    label.stringValue = "●  " + value.display
                }
                else if parent.columns[index].isPrimaryKey { label.textColor = .secondaryLabelColor }
            }
            cell.toolTip = label.stringValue
            return cell
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table = notification.object as? NSTableView else { return }
            let ids = Set(table.selectedRowIndexes.compactMap { index in
                parent.rows.indices.contains(index) ? parent.rows[index].id : nil
            })
            if let selectionChanged = parent.selectionChanged { selectionChanged(ids) }
            else {
                let row = table.selectedRow
                parent.selection(parent.rows.indices.contains(row) ? parent.rows[row].id : nil)
            }
        }
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !updating, let key = tableView.sortDescriptors.first?.key else { return }
            parent.sort(key)
        }
        @objc func openInspector(_ sender: NSTableView) {
            guard parent.rows.indices.contains(sender.clickedRow),
                  sender.tableColumns.indices.contains(sender.clickedColumn) else { return }
            let identifier = sender.tableColumns[sender.clickedColumn].identifier.rawValue
            guard identifier.hasPrefix("column:"), let index = Int(identifier.dropFirst(7)),
                  parent.columns.indices.contains(index),
                  parent.rows[sender.clickedRow].cells.indices.contains(index) else { return }
            if let editCell = parent.editCell { editCell(parent.rows[sender.clickedRow].id, index) }
            else { parent.doubleClick() }
        }
    }
}

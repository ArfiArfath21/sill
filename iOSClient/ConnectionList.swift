import Foundation
import CoreGraphics

/// The connect screen's arrangement (rows, or tiles with each saved Mac's last picture), the groups a
/// saved Mac can be put in, and the stored pictures (issue #116; Windows App's Connection Center:
/// tiles with stored screenshots and custom groups). Pure rules: Foundation and CoreGraphics only,
/// checked by `Tests/checks/connection-list`.
enum ConnectionList {
    enum Style: String, CaseIterable, Equatable {
        case list, tiles
        var toggled: Style { self == .list ? .tiles : .list }
    }

    static let styleKey = "Sill.connectionStyle"
    static let groupsKey = "Sill.macGroups"
    static let presetGroups = ["Home", "Work", "Personal"]
    /// The section of the Macs with no group, once any Mac has one. Never a group's own name: a group
    /// called Other would be a second section of that title.
    static let otherTitle = "Other"
    static let maxGroupLength = 32
    static let twoColumnMinWidth: CGFloat = 340

    /// The stored style; `.list` for nil or any unknown value, so existing installs keep rows (tiles are
    /// a choice, never the default: Noah on issue #116).
    static func storedStyle(_ raw: String?) -> Style {
        raw == Style.tiles.rawValue ? .tiles : .list
    }

    /// Whether a session's end keeps a picture of the Mac's screen for its tile. Only while tiles are
    /// on: the list shows no pictures and keeps none (turning tiles off deletes them). Only from a
    /// window in front: one in the background, or the other of two Sill windows, draws nothing, and a
    /// black picture would replace a good one. Only for a saved Mac: only its tile shows a picture.
    static func takesPreview(style: Style, sceneActive: Bool, saved: Bool) -> Bool {
        style == .tiles && sceneActive && saved
    }

    // MARK: The tile's picture: the stream's last keyframe, decoded

    // The picture is never taken from the screen. On a device the display layer's video is composited
    // outside the app's own drawing, so a snapshot of the view (`drawHierarchy`) drew black in its
    // place; the simulator composites it in software, which is why its photos looked right. The client
    // keeps the session's last keyframe with the parameter sets it came with (one frame, replaced at
    // each keyframe, dropped with the session) and decodes it at the session's end (KeyframePicture).

    /// The picture's width at most, in points, and its scale: 640 pixels at most, as the tile shows it.
    static let previewPoints: CGFloat = 320
    static let previewScale: CGFloat = 2

    /// The picture's size in pixels for a video of `video` pixels: at most `previewPoints` ×
    /// `previewScale` wide, never wider than the video, in its shape, the height rounded down (at least
    /// a pixel). Nil for no video.
    static func previewPixels(video: CGSize) -> (width: Int, height: Int)? {
        guard video.width.isFinite, video.height.isFinite, video.width >= 1, video.height >= 1 else { return nil }
        let width = min((previewPoints * previewScale).rounded(.down), video.width.rounded(.down))
        let height = max(1, (video.height * width / video.width).rounded(.down))
        return (Int(width), Int(height))
    }

    /// How long a decode may take before its picture is given up: the old file stays.
    static let decodeBound: TimeInterval = 1

    /// The brightest a colour channel may be in a picture that counts as black.
    static let blackLevel: UInt8 = 24

    /// Whether a decoded picture is black: no pixel with a colour channel brighter than `blackLevel`.
    /// A Mac's screen always has something brighter (the menu bar, a window's text); a decode that came
    /// out black has nothing, and it must never replace a good picture. `pixels`: `height` rows of
    /// `bytesPerRow` bytes, each pixel 4 bytes whose first three are its colour (BGRX or RGBX: the
    /// fourth, alpha or padding, is not looked at), the bytes after `width` pixels in a row padding.
    static func looksBlack(_ pixels: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int) -> Bool {
        guard width > 0, height > 0, bytesPerRow >= width * 4, pixels.count >= bytesPerRow * (height - 1) + width * 4 else { return true }
        for row in 0..<height {
            let start = row * bytesPerRow
            for x in 0..<width {
                let p = start + x * 4
                if pixels[p] > blackLevel || pixels[p + 1] > blackLevel || pixels[p + 2] > blackLevel { return false }
            }
        }
        return true
    }

    /// Whether a picture decoded after its session ended is kept when it lands: only while tiles are
    /// still on (switching to the list deleted every picture meanwhile) and the Mac is still saved
    /// (Forget deleted its picture).
    static func keepsDecodedPicture(style: Style, saved: Bool) -> Bool {
        style == .tiles && saved
    }

    /// Cleans a group name: whitespace and newlines collapsed to single spaces, at most
    /// `maxGroupLength` characters; a preset's name in any case is the preset ("work" is Work); nil when
    /// blank or Other in any case (where the Macs with no group already are).
    static func cleanGroup(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let words = raw.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        let name = String(words.joined(separator: " ").prefix(maxGroupLength)).trimmingCharacters(in: .whitespaces)
        if name.caseInsensitiveCompare(otherTitle) == .orderedSame { return nil }
        return presetGroups.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
    }

    static func decodeGroups(_ text: String?) -> [String: String] {
        guard let text, let data = text.data(using: .utf8),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        var out: [String: String] = [:]
        for (macID, group) in raw where !macID.isEmpty && macID.count <= 128 {
            if let clean = cleanGroup(group) { out[macID] = clean }
        }
        return out
    }

    static func encodeGroups(_ groups: [String: String]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(groups)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// Puts `macID` in `group`, or in none for nil, blank or Other. A name already in use in another
    /// case ("home office" beside "Home Office") is that group, so one name never makes two sections.
    static func settingGroup(_ group: String?, for macID: String, in groups: [String: String]) -> [String: String] {
        guard !macID.isEmpty, macID.count <= 128 else { return groups }
        var next = groups
        if let clean = cleanGroup(group) {
            next[macID] = groups.values.filter { $0.caseInsensitiveCompare(clean) == .orderedSame }.min() ?? clean
        } else {
            next.removeValue(forKey: macID)
        }
        return next
    }

    /// A saved record retired for a newer one of the same Mac (SavedMacs.superseding, a re-pairing that
    /// replaces a record whose Mac has a new key): its group goes to the record that takes its place,
    /// unless that one has a group of its own.
    static func carryingGroup(from old: String, to new: String, in groups: [String: String]) -> [String: String] {
        guard old != new, let group = groups[old] else { return groups }
        var next = groups
        next.removeValue(forKey: old)
        if next[new] == nil { next[new] = group }
        return next
    }

    /// The order groups come in, in the Group menu and as sections, whatever order the Macs are listed
    /// in (so a section never moves as Macs come and go): the presets in their order, then other names
    /// as Finder sorts them.
    static func ordered(_ names: Set<String>) -> [String] {
        presetGroups.filter(names.contains) + names.subtracting(presetGroups).sorted { a, b in
            let order = a.localizedStandardCompare(b)
            return order == .orderedSame ? a < b : order == .orderedAscending
        }
    }

    /// The Group menu's names: every preset, then the other names in use.
    static func availableGroups(in groups: [String: String]) -> [String] {
        ordered(Set(presetGroups).union(groups.values.compactMap(cleanGroup)))
    }

    struct Section<Item: Equatable>: Equatable {
        let title: String?
        let items: [Item]
    }

    /// Groups `items` by each item's `macID` in `groups`: the groups in `ordered`'s order, each keeping
    /// the items' own order, then Other for the rest. When no item has a group, a single section with
    /// `title: nil`, so the connect screen has no header and is the flat list it always was.
    static func sections<Item: Equatable>(for items: [Item], macID: (Item) -> String?, groups: [String: String]) -> [Section<Item>] {
        guard !items.isEmpty else { return [] }
        var byGroup: [String: [Item]] = [:]
        var ungrouped: [Item] = []
        for item in items {
            if let id = macID(item), let g = cleanGroup(groups[id]) {
                byGroup[g, default: []].append(item)
            } else {
                ungrouped.append(item)
            }
        }
        guard !byGroup.isEmpty else { return [Section(title: nil, items: items)] }
        var out = ordered(Set(byGroup.keys)).compactMap { name in byGroup[name].map { Section(title: name, items: $0) } }
        if !ungrouped.isEmpty { out.append(Section(title: otherTitle, items: ungrouped)) }
        return out
    }

    /// Safe filename for a saved Mac's preview JPEG (`<macID>.jpg`); nil for anything that could
    /// traverse paths or is not a valid identifier.
    static func previewFileName(for macID: String) -> String? {
        guard !macID.isEmpty, macID.count <= 128,
              macID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        return macID + ".jpg"
    }

    /// `.jpg` filenames in the preview folder whose Mac ID is no longer in `keepingMacIDs`.
    static func stalePreviewFiles(in files: [String], keepingMacIDs: Set<String>) -> [String] {
        files.filter { file in
            guard file.hasSuffix(".jpg") else { return false }
            let id = String(file.dropLast(4))
            return !keepingMacIDs.contains(id)
        }
    }

    /// How many tile columns fit `width`: 2 columns at 340 pt and wider, 1 column on narrower
    /// screens or at accessibility text sizes.
    static func columns(forWidth width: CGFloat, accessibleText: Bool) -> Int {
        (!accessibleText && width >= twoColumnMinWidth) ? 2 : 1
    }
}

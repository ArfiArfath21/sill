// A row keeps its TXT record while its name stays listed (DiscoveryPolicy.rowRecords; Noah's iPad,
// 2026-10-27: with the USB cable pulled, iPadOS listed the Mac on en2 and en0, then on en0 alone, with no
// TXT record at all, so its row was taken by its name alone and read "Update Sill"), in the policy check:
// the console's listings through the rows, their words, the sightings and the Remote rows; a browser made
// again (issue #69) and one that failed, whose rows keep the names they list and so their records; the
// DEBUG test rows beside a result of the same name; and random sessions of a browser's reports, with
// rebuilds, against a model. A function main.swift calls after pairing at home's.
import Foundation

func rowRecordsPolicy() {
    typealias Rec = P.RowRecord
    typealias I = P.Interface
    typealias R = (name: String, record: Rec?)
    let mac = "Noah\u{2019}s MacBook Pro"
    let paired = Rec(tag: "TAG", door: .pairingRequired)          // "TAG" names the saved Mac "M"
    let anpi0 = I(name: "anpi0", type: .wiredEthernet), en2 = I(name: "en2", type: .wiredEthernet), en0 = I(name: "en0", type: .wifi)
    let saved: [(macID: String, bonjourName: String?)] = [("M", mac)]
    /// A row as recomputeMacs builds it from the record it is read with: the saved Mac it is (by the
    /// tag, else by its name alone), its word and a tap's dial in a DEBUG build, M seen over TLS.
    func row(_ record: Rec?, _ interfaces: [I]) -> (macID: String?, byName: Bool, word: P.RowWord, tap: P.HomeDial) {
        let tagged = record?.tag == "TAG" ? "M" : nil
        let carries = !(record?.tag ?? "").isEmpty
        let named = P.rowMac(tagged: tagged, carriesTag: carries, name: mac, saved: saved)
        let door = P.rowDoor(record?.door ?? .plain, otherTagUnderSavedName: P.otherTagUnderSavedName(tagged: tagged, carriesTag: carries,
                                                                                                        name: mac, saved: saved))
        let method = P.method(direct: false, interfaces: interfaces)
        return (tagged, named?.tagNamed == false,
                P.rowWord(door: door, saved: named != nil, revoked: false, homeTLS: true, debug: true, method: method, cable: false),
                P.homeDial(door: door, saved: named != nil, revoked: false, homeTLS: true, debug: true, tap: true))
    }

    // The console's three listings, as recomputeMacs reads each report of the network browser: the rows,
    // the sightings by name, the Mac IDs its network rows name (the saved Mac's sightings, its Remote row).
    var records: [String: Rec] = [:], sightings = P.NetworkSightings()
    var seen: [(macID: String?, byName: Bool, word: P.RowWord, tap: P.HomeDial)] = [], since: [Double?] = [], remote: [Int] = []
    var before: [P.RowWord] = []
    for (t, interfaces, record) in [(1.0, [anpi0, en2, en0], paired as Rec?), (2.0, [en2, en0], nil), (2.5, [en0], nil)] {
        let rows = P.rows(network: [mac], nearby: [])
        records = P.rowRecords(records, listed: rows.map { (name: $0.name, record: record) })
        sightings = P.sightings(sightings, listed: Set(rows.map(\.name)), now: t)
        let r = row(records[mac], interfaces)
        seen.append(r)
        since.append(sightings.since[mac])
        remote.append(P.remoteRows(saved: [(macID: "M", name: mac)], listedIDs: Set([r.macID].compactMap { $0 }), now: t + 10,
                                   searchingSince: 0, localNetworkDenied: false).count)
        before.append(row(record, interfaces).word)
    }
    check("records: the cable pulled, the Mac's row Wired, Wired, Wi‑Fi, M by its tag throughout, dialed pinned",
          seen.map(\.word) == [.method(.wired), .method(.wired), .method(.wifi)] && seen.allSatisfy { $0.macID == "M" && !$0.byName && $0.tap == .pinned })
    check("records: listed since its first look throughout, and no Remote row for M beside it", since == [1, 1, 1] && remote == [0, 0, 0])
    check("records: before the fix, Wired, then Update Sill twice", before == [.method(.wired), .updateSill, .updateSill])
    check("records: before the fix, the row named no Mac ID, so M's Remote row came beside it",
          P.remoteRows(saved: [(macID: "M", name: mac)], listedIDs: Set([row(nil, [en0]).macID].compactMap { $0 }), now: 12.5, searchingSince: 0,
                       localNetworkDenied: false).map(\.macID) == ["M"])

    // A browser made again (back from the background): the old one's results beside the new one's while
    // it settles (DiscoveryPolicy.browserResults). The new one lists the Mac without a record: the name
    // stays listed, so the record stays, while it settles and after.
    let ends = 100 + P.rebuildSettle
    var rebuilt: [String: Rec] = [mac: paired], keptThrough = true
    for (t, fresh) in [(100.0, [] as [R]), (100.05, [(mac, nil)] as [R]), (ends, [(mac, nil)] as [R]), (200, [(mac, nil)] as [R])] {
        rebuilt = P.rowRecords(rebuilt, listed: P.browserResults(kept: [(mac, nil)], fresh: fresh, name: { $0.name }, settleEnds: ends, now: t))
        if rebuilt[mac] != paired { keptThrough = false }
    }
    check("records: a browser made again keeps the record of a name it lists without one, while it settles and after", keptThrough)
    var settled: [String: Rec] = [mac: paired]
    settled = P.rowRecords(settled, listed: P.browserResults(kept: [(mac, nil)], fresh: [], name: { $0.name }, settleEnds: ends, now: 101))
    let duringSettle = settled[mac]
    settled = P.rowRecords(settled, listed: P.browserResults(kept: [(mac, nil)], fresh: [], name: { $0.name }, settleEnds: ends, now: ends))
    check("records: a name the new browser does not list keeps its record while the old results are shown, and is forgotten at the settle's end",
          duringSettle == paired && settled[mac] == nil)
    var waiting: [String: Rec] = [mac: paired]
    waiting = P.rowRecords(waiting, listed: P.browserResults(kept: [(mac, nil)], fresh: [], name: { $0.name }, settleEnds: .infinity, now: 1e9))
    check("records: while a failed browser waits to be made again, the rows as they were, and the record with them", waiting[mac] == paired)
    // The nearby browser stopped (its results gone) and started again: a fresh listing, nothing kept.
    var nearby = P.rowRecords([:], listed: [(mac, paired)])
    nearby = P.rowRecords(nearby, listed: [])
    nearby = P.rowRecords(nearby, listed: [(mac, nil)])
    check("records: the nearby browser stopped, then listing the Mac without a record: no record (a plain door)", nearby.isEmpty)
    // A DEBUG test row after a result of the same name: the row reads the result's, as recomputeMacs does
    // (each row's first entry), never the test row's own making.
    let testRow = Rec(tag: nil, door: .pairingRequired)
    check("records: a test row of a result's name never lends it its record",
          P.rowRecords([:], listed: [(mac, nil), (mac, testRow)]).isEmpty && P.rowRecords([mac: paired], listed: [(mac, nil), (mac, testRow)]) == [mac: paired]
          && P.rowRecords([:], listed: [(mac, paired), (mac, testRow)]) == [mac: paired])

    // 5,000 random sessions of 40 reports of one browser at three names, each name listed or not, without
    // a record or with one of four, and now and then the browser made again (the rows' results kept beside
    // the new one's for its settle): each name is read with the last record it carried since it was last
    // listed afresh among what the rows show, never one it was not given then, and none once it left.
    struct LCG {
        var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s >> 33 }
    }
    var rng = LCG(s: 0x2026_1027)
    let names = ["A", "B", "C"]
    let choices = [paired, Rec(tag: "TAG", door: .open), Rec(tag: "TAG", door: .plain), Rec(tag: "NEW", door: .pairingRequired)]
    var sessions = 0, agreed = 0, onlyGiven = true, forgotten = true, rebuilds = 0, keptAcross = 0
    for _ in 0..<5_000 {
        var memory: [String: Rec] = [:], runs: [String: [Rec?]] = [:]
        var kept: [R] = [], shown: [R] = [], settleEnds: Double?, ok = true
        for step in 0..<40 {
            let t = Double(step)
            if rng.next() % 8 == 0 { kept = shown; settleEnds = t + P.rebuildSettle; rebuilds += 1 }
            let fresh: [R] = names.compactMap { n in
                switch rng.next() % 4 {
                case 0: return nil
                case 1: return (n, nil)
                default: return (n, choices[Int(rng.next() % UInt64(choices.count))])
                }
            }
            shown = P.browserResults(kept: kept, fresh: fresh, name: { $0.name }, settleEnds: settleEnds, now: t)
            if let e = settleEnds, t >= e { kept = []; settleEnds = nil }
            let keptBefore = memory
            memory = P.rowRecords(memory, listed: shown)
            for n in names {
                let item = shown.first { $0.name == n }
                if let item { runs[n, default: []].append(item.record) } else { runs[n] = nil }
                if memory[n] != runs[n]?.reversed().compactMap({ $0 }).first { ok = false }
                if let got = memory[n], !(runs[n] ?? []).contains(got) { onlyGiven = false }
                if item == nil, memory[n] != nil { forgotten = false }
                if let item, item.record == nil, kept.contains(where: { $0.name == n }), keptBefore[n] != nil, memory[n] == keptBefore[n] { keptAcross += 1 }
            }
        }
        sessions += 1
        if ok { agreed += 1 }
    }
    check("records: \(agreed) of \(sessions) random sessions (\(rebuilds) rebuilds) read each name as the model does", agreed == sessions && rebuilds > 1_000)
    check("records: a name is only ever read with a record delivered for it since it was last listed afresh, and none once it left",
          onlyGiven && forgotten)
    check("records: a record kept across a rebuild's settle for a name listed without one (\(keptAcross) times)", keptAcross > 100)
}

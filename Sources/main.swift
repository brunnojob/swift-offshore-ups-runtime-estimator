import Foundation

enum Failure: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { switch self { case .invalid(let message): return message } }
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failure.invalid(message) }
}
func numeric(_ value: String) throws -> Double {
    guard let parsed = Double(value), parsed.isFinite else { throw Failure.invalid("Finite number required") }
    return parsed
}
func input(_ columns: Int) throws -> [[String]] {
    var rows: [[String]] = []
    while let line = readLine() {
        try require(rows.count < 100000, "Input capacity exceeded")
        try require(line.utf8.count <= 8192, "Input record too large")
        let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        try require(fields.count == columns && fields.allSatisfy { !$0.isEmpty }, "Invalid CSV row")
        rows.append(fields)
    }
    try require(!rows.isEmpty, "Missing input")
    return rows
}
func output<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    guard let text = String(data: data, encoding: .utf8) else { throw Failure.invalid("Encoding failed") }
    print(text)
}

struct Sample { let time: Double; let current: Double; let voltage: Double }
struct Battery: Codable { let stateOfCharge: Double; let dischargedAh: Double; let energyWh: Double; let remainingHours: Double?; let lowVoltage: Bool }
func estimate(_ samples: [Sample], capacity: Double, ratedCurrent: Double, exponent: Double) throws -> Battery {
    try require(!samples.isEmpty && capacity > 0 && ratedCurrent > 0 && exponent >= 1 && exponent <= 2, "Invalid battery model")
    var discharged = 0.0, energy = 0.0, previous: Sample? = nil
    for s in samples {
        try require(s.time >= 0 && s.current >= 0 && s.voltage > 0, "Invalid discharge sample")
        if let p = previous {
            try require(s.time > p.time && s.time - p.time <= 3600, "Nonchronological samples or large integration gap")
            let hours = (s.time - p.time) / 3600
            let left = pow(p.current / ratedCurrent, exponent) * ratedCurrent
            let right = pow(s.current / ratedCurrent, exponent) * ratedCurrent
            discharged += (left + right) * 0.5 * hours
            energy += (p.current * p.voltage + s.current * s.voltage) * 0.5 * hours
        }
        previous = s
    }
    let remaining = max(0, capacity - discharged)
    let last = samples.last!
    let effective = pow(last.current / ratedCurrent, exponent) * ratedCurrent
    return Battery(stateOfCharge: remaining / capacity, dischargedAh: discharged, energyWh: energy, remainingHours: effective > 0 ? remaining / effective : nil, lowVoltage: last.voltage < 42)
}
func test() throws {
    let b = try estimate([Sample(time: 0, current: 10, voltage: 48), Sample(time: 3600, current: 10, voltage: 48)], capacity: 100, ratedCurrent: 10, exponent: 1.2)
    try require(abs(b.stateOfCharge - 0.9) < 1e-12 && b.energyWh == 480 && b.remainingHours == 9, "Battery integration mismatch")
    let idle = try estimate([Sample(time: 0, current: 0, voltage: 48)], capacity: 100, ratedCurrent: 10, exponent: 1.2)
    try require(idle.remainingHours == nil, "Idle runtime must be unbounded")
}
func run() throws {
    let samples = try input(3).map { Sample(time: try numeric($0[0]), current: try numeric($0[1]), voltage: try numeric($0[2])) }
    try output(estimate(samples, capacity: 100, ratedCurrent: 10, exponent: 1.2))
}

do {
    try require(CommandLine.arguments.count == 1 || Array(CommandLine.arguments.dropFirst()) == ["--self-test"], "Unsupported command arguments")
    if Array(CommandLine.arguments.dropFirst()) == ["--self-test"] { try test(); print("Tests passed") }
    else { try run() }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(2)
}

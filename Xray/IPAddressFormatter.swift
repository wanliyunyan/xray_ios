//
//  IPAddressFormatter.swift
//  Xray
//

/// Formats IP addresses for display without exposing the full IPv4 address.
enum IPAddressFormatter {
    /// Masks the first three IPv4 octets and leaves other address forms unchanged.
    static func masked(_ address: String) -> String {
        let octets = address.split(separator: ".")
        guard octets.count == 4 else {
            return address
        }
        return "*.*.*." + octets[3]
    }
}

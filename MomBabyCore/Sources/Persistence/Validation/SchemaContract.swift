/// Frozen constants for the first public SQLite schema.
public enum SchemaContract {
    /// Big-endian ASCII `MBBY`: hexadecimal `0x4D424259`.
    public static let applicationID = 1_296_187_993
    public static let currentVersion = 1
    public static let mediaLayoutVersion = 1
    public static let migrationIdentifier = "v1_create_local_vault"

    public static let expectedTableCount = 44
    public static let expectedIndexCount = 36
    public static let expectedTriggerCount = 86
    public static let expectedFingerprint =
        "765477301e5edf1b49486cf35f1f365aa0466cb51cfa672e1cf3ed3bcdd7cb03"
}

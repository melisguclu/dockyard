import Foundation

public enum DirectoryEntryCount {
    public static func count(of url: URL) -> Int? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        request.dirattr = attrgroup_t(ATTR_DIR_ENTRYCOUNT)

        var buffer = [UInt8](repeating: 0, count: 64)
        let status = buffer.withUnsafeMutableBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return -1 }
            return getattrlist(url.path, &request, base, raw.count, 0)
        }
        guard status == 0 else { return nil }

        let returnedOffset = MemoryLayout<UInt32>.size
        let countOffset = returnedOffset + MemoryLayout<attribute_set_t>.size
        guard buffer.count >= countOffset + MemoryLayout<UInt32>.size else { return nil }

        let returned = buffer.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: returnedOffset, as: attribute_set_t.self)
        }
        guard returned.dirattr & attrgroup_t(ATTR_DIR_ENTRYCOUNT) != 0 else { return nil }

        let entries = buffer.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: countOffset, as: UInt32.self)
        }
        return Int(entries)
    }
}

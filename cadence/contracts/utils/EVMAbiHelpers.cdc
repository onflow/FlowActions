import "EVM"

access(all) contract EVMAbiHelpers {
    // ===== Utilities: concat & padding =====
    access(all) fun concat(_ parts: [[UInt8]]): [UInt8] {
        var out: [UInt8] = []
        for p in parts { out = out.concat(p) }
        return out
    }

    access(all) fun leftPad32(_ b: [UInt8]): [UInt8] {
        let need = 32 - b.length
        if need <= 0 { return b.slice(from: b.length - 32, upTo: b.length) }
        var out: [UInt8] = []
        var i = 0
        while i < need { out.append(0); i = i + 1 }
        return out.concat(b)
    }

    access(all) fun rightPadTo32(_ b: [UInt8]): [UInt8] {
        let rem = b.length % 32
        if rem == 0 { return b }
        let pad = 32 - rem
        var out = b
        var i = 0
        while i < pad { out.append(0); i = i + 1 }
        return out
    }

    // ===== UInt256 & words =====
    access(all) fun beBytesN(_ v: UInt256, _ n: Int): [UInt8] {
        var x = v
        var out: [UInt8] = []
        var i = 0
        while i < n {
            let byte = UInt8(x & 0xff)
            out.insert(at: 0, byte)    // big-endian
            x = x >> 8
            i = i + 1
        }
        return out
    }

    access(all) fun abiWord(_ v: UInt256): [UInt8] { return self.leftPad32(self.beBytesN(v, 32)) }

    // ===== Primitive encoders =====
    access(all) fun abiUInt256(_ v: UInt256): [UInt8] { return self.abiWord(v) }

    access(all) fun abiBool(_ b: Bool): [UInt8] {
        return self.abiWord(b ? UInt256(1) : UInt256(0))
    }

    access(all) fun toVarBytes(_ a: EVM.EVMAddress): [UInt8] {
        let fixed: [UInt8; 20] = a.bytes   // NOTE: field, not call
        var out: [UInt8] = []
        var i = 0
        while i < 20 { out.append(fixed[i]); i = i + 1 }
        return out
    }

    access(all) fun abiAddress(_ a: EVM.EVMAddress): [UInt8] {
        return self.leftPad32(self.toVarBytes(a))
    }

    access(all) fun abiBytes32(_ b: [UInt8]): [UInt8] {
        if b.length >= 32 { return b.slice(from: 0, upTo: 32) }
        var out = b
        while out.length < 32 { out.append(0) }
        return out
    }

    access(all) fun abiDynamicBytes(_ b: [UInt8]): [UInt8] {
        let len = UInt256(b.length)
        return self.abiWord(len).concat(self.rightPadTo32(b))
    }

    access(all) fun abiStringFromUTF8(_ utf8: [UInt8]): [UInt8] {
        return self.abiDynamicBytes(utf8)
    }

    access(all) fun uintArrayToString(_ arr: [UInt8]): String {
        var out = ""
        var i = 0
        while i < arr.length {
            out = out.concat(arr[i].toString())
            if i < arr.length - 1 {
                out = out.concat(",")
            }
            i = i + 1
        }
        return out
    }

    // Represents one ABI argument chunk
    access(all) struct ABIArg {
        access(all) let isDynamic: Bool
        access(all) let head: [UInt8]
        access(all) let tail: [UInt8]
        init(isDynamic: Bool, head: [UInt8], tail: [UInt8]) {
            self.isDynamic = isDynamic
            self.head = head
            self.tail = tail
        }
    }

    access(all) fun staticArg(_ word: [UInt8]): EVMAbiHelpers.ABIArg {
        return EVMAbiHelpers.ABIArg(isDynamic: false, head: word, tail: [])
    }
    access(all) fun dynamicArg(_ blob: [UInt8]): EVMAbiHelpers.ABIArg {
        return EVMAbiHelpers.ABIArg(isDynamic: true, head: [], tail: blob)
    }

    // Build final calldata for a function
    access(all) fun buildCalldata(selector: [UInt8], args: [EVMAbiHelpers.ABIArg]): [UInt8] {
        let headSize = 32 * args.length
        var heads: [[UInt8]] = []
        var tails: [[UInt8]] = []
        var dynamicOffset = headSize

        for a in args {
            if a.isDynamic {
                heads.append(self.abiWord(UInt256(dynamicOffset)))
                tails.append(a.tail)
                dynamicOffset = dynamicOffset + a.tail.length
            } else {
                heads.append(a.head)
            }
        }
        return selector.concat(self.concat(heads)).concat(self.concat(tails))
    }
}

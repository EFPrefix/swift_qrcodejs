/*
 Copyright (c) 2012 davidshimjs
 Copyright (c) 2017-2020 ApolloZhu <public-apollonian@outlook.com>
 Copyright (c) 2017 EyreFree <eyrefree@eyrefree.org>
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

import Foundation

public struct QRCodeModel {
    public let typeNumber: Int
    public let errorCorrectLevel: QRErrorCorrectLevel
    private var modules: [[Bool?]]! = nil
    public private(set) var moduleCount = 0
    private let encodedText: QR8bitByte
    private var dataCache: [Int]
    public let needTypeTable: Bool
    private var position: [[Int]] = []
    
    init(data: Data,
         errorCorrectLevel: QRErrorCorrectLevel,
         needTypeTable: Bool = false) throws {
        self.needTypeTable = needTypeTable
        
        self.encodedText = QR8bitByte(parsedData: data)

        self.typeNumber = try QRCodeType
            .typeNumber(forLength: encodedText.count,
                        errorCorrectLevel: errorCorrectLevel)
        self.errorCorrectLevel = errorCorrectLevel
        self.dataCache = try QRCodeModel.createData(
            typeNumber: typeNumber,
            errorCorrectLevel: errorCorrectLevel,
            data: encodedText
        )
        makeImpl(isTest: false, maskPattern: getBestMaskPattern())
    }

    /// Please be aware of index out of bounds error yourself.
    public func isDark(_ row: Int, _ col: Int) -> Bool {
        return modules?[row][col] == true
    }

    public func isLight(_ row: Int, _ col: Int) -> Bool {
        return !isDark(row, col)
    }

    private mutating func makeImpl(isTest test: Bool, maskPattern: QRMaskPattern) {
        moduleCount = typeNumber * 4 + 17
        modules = [[Bool?]](repeating:[Bool?](repeating: nil, count: moduleCount), count: moduleCount)
        setupPositionProbePattern(0, 0)
        setupPositionProbePattern(moduleCount - 7, 0)
        setupPositionProbePattern(0, moduleCount - 7)
        setupPositionAdjustPattern()
        setupTimingPattern()
        setupTypeInfo(isTest: test, maskPattern: maskPattern.rawValue)
        if typeNumber >= 7 {
            setupTypeNumber(isTest: test)
        }
        mapData(dataCache, maskPattern: maskPattern)
    }

    private mutating func setupPositionProbePattern(_ row: Int, _ col: Int) {
        for r in -1...7 {
            if row + r <= -1 || moduleCount <= row + r {
                continue
            }
            for c in -1...7 {
                if col + c <= -1 || moduleCount <= col + c {
                    continue
                }
                if (0 <= r && r <= 6 && (c == 0 || c == 6))
                    || (0 <= c && c <= 6 && (r == 0 || r == 6))
                    || (2 <= r && r <= 4 && 2 <= c && c <= 4) {
                    modules[row + r][col + c] = true
                } else {
                    modules[row + r][col + c] = false
                }
            }
        }
    }

    private mutating func setupTimingPattern() {
        for i in 8..<moduleCount - 8 {
            if modules[i][6] == nil {
                modules[i][6] = (i % 2 == 0)
            }
            if modules[6][i] == nil {
                modules[6][i] = (i % 2 == 0)
            }
        }
    }

    private mutating func setupPositionAdjustPattern() {
        #if swift(<5.1)
        let pos = QRPatternLocator.getPatternPosition(ofType: typeNumber)
        #else
        let pos = QRPatternLocator[typeNumber]
        #endif
        
        if needTypeTable {
            self.position = []
        }
        
        for i in pos.indices {
            for j in pos.indices {
                let row = pos[i]
                let col = pos[j]
                if modules[row][col] != nil {
                    continue
                }
                
                if needTypeTable {
                    self.position.append([row, col])
                }
                
                for r in -2...2 {
                    for c in -2...2 {
                        if r == -2 || r == 2 || c == -2 || c == 2 || r == 0 && c == 0 {
                            modules[row + r][col + c] = true
                        } else {
                            modules[row + r][col + c] = false
                        }
                    }
                }
            }
        }
    }

    private mutating func setupTypeNumber(isTest test: Bool) {
        let bits: Int = BCH.typeNumber(of: typeNumber)
        for i in 0..<18 {
            let mod = (!test && ((bits >> i) & 1) == 1)
            modules[i / 3][i % 3 + moduleCount - 8 - 3] = mod
            modules[i % 3 + moduleCount - 8 - 3][i / 3] = mod
        }
    }

    private mutating func setupTypeInfo(isTest test: Bool, maskPattern: Int) {
        let data = (errorCorrectLevel.pattern << 3) | maskPattern
        let bits: Int = BCH.typeInfo(of: data) // to enforce signed shift
        for i in 0..<15 {
            let mod = !test && ((bits >> i) & 1) == 1

            if i < 6 {
                modules[i][8] = mod
            } else if i < 8 {
                modules[i + 1][8] = mod
            } else {
                modules[moduleCount - 15 + i][8] = mod
            }

            if i < 8 {
                modules[8][moduleCount - i - 1] = mod
            } else if i < 9 {
                modules[8][15 - i - 1 + 1] = mod
            } else {
                modules[8][15 - i - 1] = mod
            }
        }
        modules[moduleCount - 8][8] = !test
    }

    private mutating func mapData(_ data: [Int], maskPattern: QRMaskPattern) {
        var inc = -1
        var row = moduleCount - 1
        var bitIndex = 7
        var byteIndex = 0

        var col: Int = moduleCount - 1
        while col > 0 {
            if col == 6 {
                col -= 1
            }
            while true {
                for c in 0..<2 {
                    if modules[row][col - c] == nil {
                        var dark = false
                        if byteIndex < data.count {
                            dark = ((UInt(data[byteIndex]) >> bitIndex) & 1) == 1
                        }
                        let mask = maskPattern.getMask(row, col - c)
                        if mask {
                            dark = !dark
                        }
                        modules[row][col - c] = dark
                        bitIndex -= 1
                        if bitIndex == -1 {
                            byteIndex += 1
                            bitIndex = 7
                        }
                    }
                }
                row += inc
                if row < 0 || moduleCount <= row {
                    row -= inc
                    inc = -inc
                    break
                }
            }
            col -= 2
        }
    }

    private static let PAD0: UInt = 0xEC
    private static let PAD1: UInt = 0x11

    private static func createData(
        typeNumber: Int, errorCorrectLevel: QRErrorCorrectLevel, data: QR8bitByte
    ) throws -> [Int] {
        let rsBlocks = errorCorrectLevel.getRSBlocks(ofType: typeNumber)
        var buffer = QRBitBuffer()

        buffer.put(data.mode.rawValue, length: 4)
        guard let length = data.mode.bitCount(ofType: typeNumber) else {
            throw QRCodeError.internalError(.dataLengthIndeterminable)
        }
        buffer.put(UInt(data.count), length: length)
        data.write(to: &buffer)

        let totalBitCount = 8 * rsBlocks.reduce(0) { $0 + $1.dataCount }
        if buffer.bitCount > totalBitCount {
            throw QRCodeError.internalError(
                .dataLength(buffer.bitCount,
                            exceedsCapacityLimit: totalBitCount)
            )
        }
        if buffer.bitCount + 4 <= totalBitCount {
            buffer.put(0, length: 4)
        }
        while buffer.bitCount % 8 != 0 {
            buffer.put(false)
        }
        while true {
            if buffer.bitCount >= totalBitCount {
                break
            }
            buffer.put(QRCodeModel.PAD0, length: 8)
            if buffer.bitCount >= totalBitCount {
                break
            }
            buffer.put(QRCodeModel.PAD1, length: 8)
        }
        return try QRCodeModel.createBytes(fromBuffer: buffer, rsBlocks: rsBlocks)
    }

    private static func createBytes(fromBuffer buffer: QRBitBuffer, rsBlocks: [QRRSBlock]) throws -> [Int] {
        var offset = 0
        var maxDcCount = 0
        var maxEcCount = 0
        // Actual contents will be assigned later
        var dcdata = [[Int]]()
        dcdata.reserveCapacity(rsBlocks.count)
        var ecdata = [[Int]]()
        ecdata.reserveCapacity(rsBlocks.count)
        for r in rsBlocks.indices {
            let dcCount = rsBlocks[r].dataCount
            let ecCount = rsBlocks[r].totalCount - dcCount
            maxDcCount = max(maxDcCount, dcCount)
            maxEcCount = max(maxEcCount, ecCount)
            // Here for `dcdata`
            dcdata.append((0..<dcCount).map {
                Int(0xff & buffer.buffer[$0 + offset])
            })
            offset += dcCount
            let rsPoly = QRPolynomial.errorCorrectPolynomial(ofLength: ecCount)
            let rawPoly = QRPolynomial(dcdata[r], shift: rsPoly.count - 1)
            let modPoly = rawPoly.moded(by: rsPoly)
            // And here for `ecdata`
            let ecdataCount = rsPoly.count - 1
            ecdata.append((0..<ecdataCount).map {
                let modIndex = $0 + modPoly.count - ecdataCount
                return (modIndex >= 0) ? modPoly[modIndex] : 0
            })
        }
        var totalCodeCount = 0
        for i in rsBlocks.indices {
            totalCodeCount += rsBlocks[i].totalCount
        }
        var data = [Int](repeating: 0, count: totalCodeCount)
        var index = 0
        for i in 0..<maxDcCount {
            for r in rsBlocks.indices {
                if i < dcdata[r].count {
                    data[index] = dcdata[r][i]
                    index += 1
                }
            }
        }
        for i in 0..<maxEcCount {
            for r in rsBlocks.indices {
                if i < ecdata[r].count {
                    data[index] = ecdata[r][i]
                    index += 1
                }
            }
        }
        return data
    }
}

extension QRCodeModel {
    private mutating func getBestMaskPattern() -> QRMaskPattern {
        var minLostPoint = 0
        var pattern = 0
        for i in 0..<8 {
            makeImpl(isTest: true, maskPattern: QRMaskPattern(rawValue: i)!)
            let lostPoint = self.lostPoint
            if i == 0 || minLostPoint > lostPoint {
                minLostPoint = lostPoint
                pattern = i
            }
        }
        return QRMaskPattern(rawValue: pattern)!
    }

    var lostPoint: Int {
        // TODO: Remove if needed
        // let moduleCount = self.moduleCount
        var lostPoint = 0
        for row in 0..<moduleCount {
            for col in 0..<moduleCount {
                var sameCount = 0
                let dark = isDark(row, col)
                for r in -1...1 {
                    if row + r < 0 || moduleCount <= row + r {
                        continue
                    }
                    for c in -1...1 {
                        if col + c < 0 || moduleCount <= col + c {
                            continue
                        }
                        if r == 0 && c == 0 {
                            continue
                        }
                        if dark == isDark(row + r, col + c) {
                            sameCount += 1
                        }
                    }
                }
                if sameCount > 5 {
                    lostPoint += (3 + sameCount - 5)
                }
            }
        }
        for row in 0..<moduleCount - 1 {
            for col in 0..<moduleCount - 1 {
                var count = 0
                if isDark(row, col) {
                    count += 1
                }
                if isDark(row + 1, col) {
                    count += 1
                }
                if isDark(row, col + 1) {
                    count += 1
                }
                if isDark(row + 1, col + 1) {
                    count += 1
                }
                if count == 0 || count == 4 {
                    lostPoint += 3
                }
            }
        }
        for row in 0..<moduleCount {
            for col in 0..<moduleCount - 6 {
                if isDark(row, col)
                    && isLight(row, col + 1)
                    && isDark(row, col + 2)
                    && isDark(row, col + 3)
                    && isDark(row, col + 4)
                    && isLight(row, col + 5)
                    && isDark(row, col + 6) {
                    lostPoint += 40
                }
                if isDark(col, row)
                    && isLight(col + 1, row)
                    && isDark(col + 2, row)
                    && isDark(col + 3, row)
                    && isDark(col + 4, row)
                    && isLight(col + 5, row)
                    && isDark(col + 6, row) {
                    lostPoint += 40
                }
            }
        }
        var darkCount = 0
        for col in 0..<moduleCount {
            for row in 0..<moduleCount {
                if isDark(row, col) {
                    darkCount += 1
                }
            }
        }
        let ratio = abs(100 * darkCount / moduleCount / moduleCount - 50) / 5
        lostPoint += ratio * 10
        return lostPoint
    }
}

extension QRCodeModel {
    
    public func getTypeTable() -> [[QRPointType]] {
        if !needTypeTable {
            return []
        }
        
        let nCount: Int = self.moduleCount
        let position: [[Int]] = self.position
        let PD: [[Int]] = [[3, 3], [3, nCount - 4], [nCount - 4, 3]]
        
        var typeTable: [[QRPointType]] = Array(repeating: Array(repeating: QRPointType.data, count: nCount), count: nCount)
        
        for i in 8..<nCount - 7 {
            typeTable[i][6] = QRPointType.timing
            typeTable[6][i] = QRPointType.timing
        }
        
        for i in 0..<position.count {
            typeTable[position[i][0]][position[i][1]] = QRPointType.alignCenter
            for r in -2...2 {
                for c in -2...2 {
                    if !(r == 0 && c == 0) {
                        typeTable[position[i][0] + r][position[i][1] + c] = QRPointType.alignOther
                    }
                }
            }
        }
        
        for i in 0..<PD.count {
            typeTable[PD[i][0]][PD[i][1]] = QRPointType.posCenter
            for r in -4...4 {
                for c in -4...4 {
                    if PD[i][0] + r >= 0 && PD[i][0] + r < nCount && PD[i][1] + c >= 0 && PD[i][1] + c < nCount {
                        if !(r == 0 && c == 0) {
                            typeTable[PD[i][0] + r][PD[i][1] + c] = QRPointType.posOther
                        }
                    }
                }
            }
        }
        
        for i in 0...8 {
            if i != 6 {
                typeTable[i][8] = QRPointType.format
                typeTable[8][i] = QRPointType.format
            }
            if i < 7 {
                typeTable[nCount - i - 1][8] = QRPointType.format
            }
            if i < 8 {
                typeTable[8][nCount - i - 1] = QRPointType.format
            }
        }
        
        for i in (nCount - 11)...(nCount - 9) {
            for j in 0...5 {
                typeTable[i][j] = QRPointType.version
                typeTable[j][i] = QRPointType.version
            }
        }
        return typeTable
    }
}

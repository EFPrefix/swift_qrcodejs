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

struct QR8bitByte {
    let mode: QRMode = .bitByte8
    let parsedData: Data
    
    init(_ data: String, encoding: String.Encoding = .utf8) throws {
        guard let parsed = data.data(using: encoding) else {
            throw QRCodeError.text(data, incompatibleWithEncoding: encoding)
        }
        self.parsedData = parsed
    }
    
    var count: Int {
        return parsedData.count
    }
    
    func write(to buffer: inout QRBitBuffer) {
        for datium in parsedData {
            buffer.put(UInt(datium), length: 8)
        }
    }
}

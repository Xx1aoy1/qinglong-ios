//
//  MultipartFormData.swift
//  QingLong
//
//  轻量 multipart/form-data 构造器，用于脚本上传、数据恢复等接口。
//

import Foundation

struct MultipartFormData {
    let boundary = "QingLong-\(UUID().uuidString)"
    private var body = Data()

    private static let crlf = "\r\n"

    mutating func appendField(name: String, value: String) {
        body.append("--\(boundary)\(Self.crlf)")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\(Self.crlf)\(Self.crlf)")
        body.append("\(value)\(Self.crlf)")
    }

    mutating func appendFile(
        name: String,
        filename: String,
        mimeType: String = "application/octet-stream",
        data: Data
    ) {
        body.append("--\(boundary)\(Self.crlf)")
        body.append(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\(Self.crlf)"
        )
        body.append("Content-Type: \(mimeType)\(Self.crlf)\(Self.crlf)")
        body.append(data)
        body.append(Self.crlf)
    }

    func finalize() -> Data {
        var result = body
        result.append("--\(boundary)--\(Self.crlf)")
        return result
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

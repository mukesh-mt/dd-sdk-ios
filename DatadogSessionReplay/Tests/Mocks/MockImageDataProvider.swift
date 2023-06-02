/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
@testable import DatadogSessionReplay

struct MockImageDataProvider: ImageDataProviding {
    var contentBase64String: String

    func contentBase64String(of image: UIImage?) -> String {
        return contentBase64String
    }

    func contentBase64String(of image: UIImage?, tintColor: UIColor?) -> String {
        return contentBase64String
    }

    init(contentBase64String: String = "mock_base64_string") {
        self.contentBase64String = contentBase64String
    }
}

internal func mockRandomImageDataProvider() -> ImageDataProviding {
    return MockImageDataProvider(contentBase64String: .mockRandom())
}

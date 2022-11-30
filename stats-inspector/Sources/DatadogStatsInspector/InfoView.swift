/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import SwiftUI
@testable import Datadog

struct InfoView: View {
    internal init(config: Datadog.Configuration) {
        self.config = config

        var properties = [Pair]()
        for (_, attr) in Mirror(reflecting: config).children.enumerated() {
            if let property_name = attr.label {
                properties.append(Pair(key: property_name, value: "\(attr.value)"))
            }
        }
        self.properties = properties
    }


    var config: Datadog.Configuration

    struct Pair: Identifiable {
        var id: String {
            return key + value
        }

        let key: String
        let value: String
    }

    var properties: [Pair]

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            List {
                ForEach(properties) { property in
                    Text(property.key)
                        .bold()
                        .listRowSeparator(.hidden)
                    Text(property.value)
                        .listRowSeparator(.visible)
                }
            }
            .navigationBarTitleDisplayMode(.large)
            .navigationTitle("Info")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

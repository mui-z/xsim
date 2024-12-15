//
// Created by osushi on 2022/02/11.
//

import Foundation
import PathKit
import SwiftCLI

class Hello: Command {
    let name: String = "hello"
    let shortDescription: String = "say hello."

    @Param
    var yourName: String

    func execute() throws {
        print("Hello, \(yourName)！")
    }
}

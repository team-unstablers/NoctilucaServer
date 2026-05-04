//
//  main.swift
//  nocfsaccessd
//
//  Created by Gyuhwan Park on 5/4/26.
//

import Foundation
import ArgumentParser

struct NocFsAccessd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "nocfsaccessd",
        abstract: "fsaccess <=> NFS bridge daemon for Noctiluca Server.",
        discussion:
"""
USAGE

By design, this program is not meant to be used outside of Noctiluca Server. As such, no USAGE or related documentation is provided.

DESCRIPTION

This program acts as an NFS server that bridges the Sirius protocol's fsaccess / fsaccess_mount channels.

[Noctiluca Server] -> [XPC Service] -> [nocfsaccessd (w/nanonfs)] -> [/some/mountpoint/...]

SECURITY

If you discover a security issue related to this program, please email contact+nocsecurity@unstabler.pl.

When reporting security vulnerabilities, please follow responsible disclosure practices. While we do not operate a formal bounty program at this time, such reports are always greatly appreciated.
"""
    )

    mutating func run() throws {
        print(NocFsAccessd.helpMessage())
    }
}

NocFsAccessd.main()

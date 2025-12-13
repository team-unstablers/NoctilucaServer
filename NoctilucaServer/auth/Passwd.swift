//
//  PAMAuthPlugin+passwd.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

struct PasswdEntry {
    let uid: uid_t
    let gid: gid_t
    let username: String
}

struct Passwd {
    static func __getpwnam(_ username: String) -> PasswdEntry? {
        guard let passwd = getpwnam(username) else {
            return nil
        }
        
        return PasswdEntry(
            uid: passwd.pointee.pw_uid,
            gid: passwd.pointee.pw_gid,
            username: String(cString: passwd.pointee.pw_name)
        )
    }
    
    static func __getpwuid(_ uid: uid_t) -> PasswdEntry? {
        guard let passwd = getpwuid(uid) else {
            return nil
        }
        
        return PasswdEntry(
            uid: passwd.pointee.pw_uid,
            gid: passwd.pointee.pw_gid,
            username: String(cString: passwd.pointee.pw_name)
        )
    }
    
    static func __getgrgid_gr_name(_ gid: gid_t) -> String? {
        guard let group = getgrgid(gid) else {
            return nil
        }
        
        return String(cString: group.pointee.gr_name)
    }
}

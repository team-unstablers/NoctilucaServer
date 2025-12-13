//
//  PAMAuthPlugin.h
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

#ifndef NOCTILUCA_SERVER_AUTH_PLUGINS_PAM_PAMAUTHPUGIN_H
#define NOCTILUCA_SERVER_AUTH_PLUGINS_PAM_PAMAUTHPUGIN_H

#import <Foundation/Foundation.h>

@interface PAMAuthPluginObjC: NSObject
+ (BOOL) authenticate: (const NSString *) username
             password: (const NSData *) password
                error: (NSError **) error;
@end

#endif

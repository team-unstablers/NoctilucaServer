//
//  PAMAuthPlugin.m
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

#include <security/pam_appl.h>

#import <Foundation/Foundation.h>

#import "PAMAuthPlugin.h"

static const char *NOCTILUCA_SERVER_PAM_SERVICE_NAME = "noctiluca";

namespace noctiluca::auth::plugin::pam {
    struct PAMAuthContext {
        const NSString *username;
        const NSData *password;
    };
    
    static int verifyPAMConversation(int messageCount, const struct pam_message **messages,
                                     struct pam_response **responses,
                                     void *appDataPtr)
    {
        const auto *context = static_cast<const PAMAuthContext *>(appDataPtr);
        
        if (context == nullptr) {
            responses = nullptr;
            return PAM_CONV_ERR;
        }
        
        *responses = static_cast<struct pam_response *> (calloc(messageCount, sizeof(struct pam_response)));
        
        if (!*responses) {
            responses = nullptr;
            return PAM_BUF_ERR;
        }
        
        for (int i = 0; i < messageCount; i++) {
            const auto *message = messages[i];
            auto &response = (*responses)[i];
            
            switch (message->msg_style) {
                case PAM_PROMPT_ECHO_ON: {
                    response.resp = strndup(
                        [(context->username) UTF8String],
                        [(context->username) lengthOfBytesUsingEncoding: NSUTF8StringEncoding]
                    );
                    response.resp_retcode = PAM_SUCCESS;
                }
                    break;
                case PAM_PROMPT_ECHO_OFF: {
                    response.resp = strndup(
                        static_cast<const char *>([(context->password) bytes]),
                        [(context->password) length]
                    );
                    response.resp_retcode = PAM_SUCCESS;
                }
                    break;
                default:
                    break;
            }
        }
        
        return PAM_SUCCESS;
    }
}

@implementation PAMAuthPluginObjC

+ (BOOL) authenticate: (const NSString *) username
             password: (const NSData *) password
                error: (NSError *__autoreleasing  _Nullable *) error
{
    noctiluca::auth::plugin::pam::PAMAuthContext context {
        .username = username,
        .password = password
    };
    
    pam_conv pamConversation {
        .conv = noctiluca::auth::plugin::pam::verifyPAMConversation,
        .appdata_ptr = &context,
    };
    
    pam_handle_t *pamHandle = nullptr;
    int pamError = PAM_SUCCESS;
    
    {
        pamError = pam_start(NOCTILUCA_SERVER_PAM_SERVICE_NAME,
                             username.UTF8String,
                             &pamConversation, &pamHandle);
        
        if (pamError != PAM_SUCCESS) {
            goto ERROR_EXIT;
        }
    }
    
    {
        pamError = pam_set_item(pamHandle, PAM_TTY, NOCTILUCA_SERVER_PAM_SERVICE_NAME);
        
        if (pamError != PAM_SUCCESS) {
            goto ERROR_EXIT;
        }
    }
    
    {
        pamError = pam_authenticate(pamHandle, 0);
        
        if (pamError != PAM_SUCCESS) {
            goto ERROR_EXIT;
        }
    }
    
    {
        pamError = pam_acct_mgmt(pamHandle, 0);
        
        if (pamError != PAM_SUCCESS) {
            goto ERROR_EXIT;
        }
        
        goto SUCCESS;
    }
    
SUCCESS:
    pam_end(pamHandle, 0);
    return YES;
    
ERROR_EXIT:
    pam_end(pamHandle, pamError);
    
    if (error) {
        NSString *errorMessage = [NSString stringWithUTF8String: pam_strerror(pamHandle, pamError)];
        *error = [NSError errorWithDomain: @"pl.unstabler.noctiluca.NoctilucaServer.auth.plugin.pam"
                                     code: pamError
                                 userInfo: @{ NSLocalizedDescriptionKey: errorMessage }];
    }
    
    return NO;
}


@end

//
//  Email.m
//  MboxChatCLI
//
//  Email data model implementation
//

#import "Email.h"

@implementation Email

- (instancetype)init {
    self = [super init];
    if (self) {
        _from = nil;
        _subject = nil;
        _date = nil;
        _body = nil;
    }
    return self;
}

- (instancetype)initWithFrom:(NSString *)from
                     subject:(NSString *)subject
                        date:(NSString *)date
                        body:(NSString *)body {
    self = [super init];
    if (self) {
        _from = [from copy];
        _subject = [subject copy];
        _date = [date copy];
        _body = [body copy];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<Email from:%@ subject:%@ date:%@>",
            self.from ?: @"(none)",
            self.subject ?: @"(none)",
            self.date ?: @"(none)"];
}

@end

#import <Foundation/Foundation.h>
#import "Email.h"

BOOL isClearText(NSString *str) {
    NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = data.bytes;
    NSUInteger len = data.length;
    for (NSUInteger i = 0; i < len; ++i) {
        if ((bytes[i] < 0x09 ||
             (bytes[i] > 0x0D && bytes[i] < 0x20) ||
             bytes[i] > 0x7E)) {
            if (bytes[i] != 0x0A && bytes[i] != 0x0D && bytes[i] != 0x09) {
                return NO;
            }
        }
    }
    return YES;
}

NSString *stripNonASCII(NSString *input) {
    NSMutableString *result = [NSMutableString string];
    NSUInteger len = [input length];
    for (NSUInteger i = 0; i < len; ++i) {
        unichar c = [input characterAtIndex:i];
        if ((c >= 0x20 && c <= 0x7E) || c == '\n' || c == '\r' || c == '\t') {
            [result appendFormat:@"%C", c];
        }
    }
    return result;
}

// Remove attachments and application/rtf sections
NSString *removeAttachmentsAndRTF(NSString *body) {
    NSMutableString *clean = [NSMutableString stringWithString:body];
    NSRange rtfRange;
    while ((rtfRange = [clean rangeOfString:@"Content-Type: application/rtf" options:NSCaseInsensitiveSearch]).location != NSNotFound) {
        NSRange after = NSMakeRange(rtfRange.location, clean.length - rtfRange.location);
        NSRange boundary = [clean rangeOfString:@"\n--" options:0 range:after];
        NSRange partEnd = boundary.location != NSNotFound ? boundary : NSMakeRange(clean.length,0);
        [clean deleteCharactersInRange:NSMakeRange(rtfRange.location, partEnd.location - rtfRange.location)];
    }
    NSRange multi = [clean rangeOfString:@"Content-Type: multipart/mixed" options:NSCaseInsensitiveSearch];
    if (multi.location != NSNotFound)
        [clean deleteCharactersInRange:NSMakeRange(multi.location, clean.length - multi.location)];
    NSRange att = [clean rangeOfString:@"Content-Disposition: attachment" options:NSCaseInsensitiveSearch];
    if (att.location != NSNotFound)
        [clean deleteCharactersInRange:NSMakeRange(att.location, clean.length - att.location)];
    return clean;
}

// Filename helpers
NSString *safeExportFilename(NSString *subject, NSUInteger threadNum) {
    NSString *base = subject.length > 0 ? subject : [NSString stringWithFormat:@"thread%04lu", (unsigned long)threadNum];
    NSString *stripped = stripNonASCII(base);
    NSCharacterSet *forbidden = [NSCharacterSet characterSetWithCharactersInString:@"/\\:?%*|\"<>'"];
    NSArray *parts = [stripped componentsSeparatedByCharactersInSet:forbidden];
    NSString *clean = [parts componentsJoinedByString:@"_"];
    if (clean.length > 48) clean = [clean substringToIndex:48];
    if (clean.length == 0) clean = [NSString stringWithFormat:@"thread%04lu", (unsigned long)threadNum];
    return [NSString stringWithFormat:@"export %@.txt", clean];
}

NSString *safeWriteFilename(NSUInteger msgNum) {
    return [NSString stringWithFormat:@"message%04lu.txt", (unsigned long)msgNum];
}

NSString *safeSummaryFilename(NSString *subject, NSUInteger threadNum) {
    NSString *base = subject.length > 0 ? subject : [NSString stringWithFormat:@"thread%04lu", (unsigned long)threadNum];
    NSString *stripped = stripNonASCII(base);
    NSCharacterSet *forbidden = [NSCharacterSet characterSetWithCharactersInString:@"/\\:?%*|\"<>'"];
    NSArray *parts = [stripped componentsSeparatedByCharactersInSet:forbidden];
    NSString *clean = [parts componentsJoinedByString:@"_"];
    if (clean.length > 48) clean = [clean substringToIndex:48];
    if (clean.length == 0) clean = [NSString stringWithFormat:@"thread%04lu", (unsigned long)threadNum];
    return [NSString stringWithFormat:@"summary %@.txt", clean];
}

// MBOX parsing — streaming line-by-line to avoid loading entire file into memory.
// Also handles mboxrd format: lines starting with ">From " are escaped quotes,
// not message separators.
NSArray<Email *> *parseMbox(NSString *path) {
    printf("[DEBUG] Attempting to load mbox file: %s\n", [path UTF8String]);

    FILE *fp = fopen([path UTF8String], "r");
    if (!fp) {
        printf("[ERROR] Failed to open '%s'\n", [path UTF8String]);
        return @[];
    }

    NSMutableArray<Email *> *result = [NSMutableArray array];
    char buf[65536];
    BOOL inMessage = NO;
    BOOL inBody = NO;
    Email *currentEmail = nil;
    NSMutableString *currentBody = nil;
    NSUInteger lineCount = 0;

    while (fgets(buf, sizeof(buf), fp) != NULL) {
        lineCount++;
        // Convert to NSString (UTF-8). If it fails, skip this line.
        NSString *line = [[NSString alloc] initWithUTF8String:buf];
        if (!line) continue;

        // Strip trailing newline
        if ([line hasSuffix:@"\n"]) {
            line = [line substringToIndex:line.length - 1];
        }
        if ([line hasSuffix:@"\r"]) {
            line = [line substringToIndex:line.length - 1];
        }

        // Detect message separator: "From " at line start (not ">From " which is mboxrd escaping)
        BOOL isFromLine = [line hasPrefix:@"From "] && ![line hasPrefix:@">From "];

        if (isFromLine) {
            // Finalize previous message
            if (currentEmail) {
                currentEmail.body = removeAttachmentsAndRTF(currentBody ?: [NSMutableString string]);
                if (isClearText(currentEmail.body) && (currentEmail.from || currentEmail.subject)) {
                    [result addObject:currentEmail];
                }
            }
            // Start new message
            currentEmail = [Email new];
            currentBody = [NSMutableString string];
            inMessage = YES;
            inBody = NO;
            continue;
        }

        if (!inMessage) continue;

        if (!inBody) {
            // Parse headers
            if ([line hasPrefix:@"From:"]) {
                currentEmail.from = [[line substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            } else if ([line hasPrefix:@"Subject:"]) {
                currentEmail.subject = [[line substringFromIndex:8] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            } else if ([line hasPrefix:@"Date:"]) {
                currentEmail.date = [[line substringFromIndex:5] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            } else if ([line isEqualToString:@""]) {
                inBody = YES;
            }
        } else {
            // Un-escape mboxrd ">From " lines: strip leading ">"
            if ([line hasPrefix:@">From "]) {
                line = [line substringFromIndex:1];
            }
            [currentBody appendString:line];
            [currentBody appendString:@"\n"];
        }
    }

    // Finalize last message
    if (currentEmail) {
        currentEmail.body = removeAttachmentsAndRTF(currentBody ?: [NSMutableString string]);
        if (isClearText(currentEmail.body) && (currentEmail.from || currentEmail.subject)) {
            [result addObject:currentEmail];
        }
    }

    fclose(fp);
    printf("[DEBUG] Parsed %lu messages from %lu lines in '%s'\n",
           (unsigned long)result.count, (unsigned long)lineCount, [path UTF8String]);
    return result;
}

// Command helpers
void printHelp(void) {
    printf("Commands:\n");
    printf("  load <mbox file>     - Load/add another mbox file\n");
    printf("  from <sender>        - Count emails by sender\n");
    printf("  subject <keyword>    - Count emails with keyword in subject\n");
    printf("  count <keyword>      - Count emails with keyword in body\n");
    printf("  write <dir>          - Write each message as individual file (ASCII, no attachments/rtf)\n");
    printf("  export <dir>         - Write each thread (subject) as one file prefixed by 'export '\n");
    printf("  summarize <dir>      - Write a summary file per thread/subject\n");
    printf("  help                 - Show help\n");
    printf("  exit                 - Quit\n");
}

NSString *trim(NSString *str) {
    return [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

BOOL ensureDirectoryExists(NSString *dirPath) {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:dirPath isDirectory:&isDir]) {
        NSError *error = nil;
        if (![fm createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:&error]) {
            printf("[ERROR] Failed to create directory: %s (%s)\n", [dirPath UTF8String], [[error localizedDescription] UTF8String]);
            return NO;
        }
    } else if (!isDir) {
        printf("[ERROR] %s exists but is not a directory!\n", [dirPath UTF8String]);
        return NO;
    }
    return YES;
}

void writeMessagesToDirectory(NSArray<Email *> *emails, NSString *dirPath) {
    if (!ensureDirectoryExists(dirPath)) return;
    NSUInteger msgNum = 1;
    for (Email *e in emails) {
        NSString *filename = safeWriteFilename(msgNum);
        NSString *fullPath = [dirPath stringByAppendingPathComponent:filename];
        NSMutableString *content = [NSMutableString string];
        [content appendFormat:@"From: %@\n", stripNonASCII(e.from ?: @"")];
        [content appendFormat:@"Subject: %@\n", stripNonASCII(e.subject ?: @"")];
        [content appendFormat:@"Date: %@\n", stripNonASCII(e.date ?: @"")];
        [content appendString:@"\n"];
        [content appendString:stripNonASCII(e.body ?: @"")];
        NSError *error = nil;
        [content writeToFile:fullPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
        msgNum++;
    }
    printf("[INFO] Wrote %lu individual messages.\n", (unsigned long)emails.count);
}

void writeThreadsToDirectory(NSArray<Email *> *emails, NSString *dirPath) {
    if (!ensureDirectoryExists(dirPath)) return;
    NSMutableDictionary *threads = [NSMutableDictionary dictionary];
    for (Email *e in emails) {
        NSString *subjectKey = e.subject ? [e.subject lowercaseString] : @"";
        if (![threads objectForKey:subjectKey]) threads[subjectKey] = [NSMutableArray array];
        [(NSMutableArray*)threads[subjectKey] addObject:e];
    }
    NSUInteger threadNum = 1;
    for (NSString *subjectKey in threads) {
        NSArray *thread = threads[subjectKey];
        if (thread.count == 0) continue;
        NSArray *sorted = [thread sortedArrayUsingComparator:^NSComparisonResult(Email *a, Email *b) {
            return a.date ? [a.date compare:b.date] : NSOrderedSame;
        }];
        NSString *subject = [(Email *)[sorted firstObject] subject] ?: @"";
        NSString *filename = safeExportFilename(subject, threadNum);
        NSString *fullPath = [dirPath stringByAppendingPathComponent:filename];
        NSMutableString *threadText = [NSMutableString string];
        NSUInteger msgInThread = 1;
        for (Email *e in sorted) {
            [threadText appendFormat:@"----- Email #%lu -----\n", (unsigned long)msgInThread];
            [threadText appendFormat:@"From: %@\n", stripNonASCII(e.from ?: @"")];
            [threadText appendFormat:@"Subject: %@\n", stripNonASCII(e.subject ?: @"")];
            [threadText appendFormat:@"Date: %@\n", stripNonASCII(e.date ?: @"")];
            [threadText appendString:@"\n"];
            [threadText appendString:stripNonASCII(e.body ?: @"")];
            [threadText appendString:@"\n\n"];
            msgInThread++;
        }
        NSError *error = nil;
        [threadText writeToFile:fullPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
        threadNum++;
    }
    printf("[INFO] Exported %lu threads (each as a single file named 'export ...').\n", (unsigned long)[threads count]);
}

// Utility: Get first/last reasonably long sentence from message array
NSString *firstSentence(NSArray<Email *> *thread) {
    for (Email *e in thread) {
        NSArray *sentences = [[e.body componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@".!?"]] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *str, id _) { return str.length > 8; }]];
        if (sentences.count) return trim(sentences[0]);
    }
    return @"";
}
NSString *lastSentence(NSArray<Email *> *thread) {
    for (NSInteger i = thread.count-1; i >= 0; i--) {
        NSArray *sentences = [[[thread objectAtIndex:i] body] componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@".!?"]];
        for (NSInteger j = sentences.count-1; j >= 0; j--) {
            NSString *s = trim(sentences[j]);
            if (s.length > 8) return s;
        }
    }
    return @"";
}

void summarizeEmailsToDirectory(NSArray<Email *> *emails, NSString *dirPath) {
    if (!ensureDirectoryExists(dirPath)) return;
    NSMutableDictionary *threads = [NSMutableDictionary dictionary];
    for (Email *e in emails) {
        NSString *subjectKey = e.subject ? [e.subject lowercaseString] : @"";
        if (![threads objectForKey:subjectKey]) threads[subjectKey] = [NSMutableArray array];
        [(NSMutableArray*)threads[subjectKey] addObject:e];
    }

    NSUInteger threadNum = 1;
    for (NSString *subjectKey in threads) {
        NSArray *thread = threads[subjectKey];
        if (thread.count == 0) continue;
        NSArray *sorted = [thread sortedArrayUsingComparator:^NSComparisonResult(Email *a, Email *b) {
            return a.date ? [a.date compare:b.date] : NSOrderedSame;
        }];
        NSString *subject = [(Email *)[sorted firstObject] subject] ?: @"";
        NSString *fromFirst = [(Email *)[sorted firstObject] from] ?: @"unknown";
        NSString *dateFirst = [(Email *)[sorted firstObject] date] ?: @"unknown";
        NSString *fromLast  = [(Email *)[sorted lastObject] from] ?: @"unknown";
        NSString *dateLast  = [(Email *)[sorted lastObject] date] ?: @"unknown";

        NSMutableString *summary = [NSMutableString string];
        [summary appendFormat:@"Subject: %@\n", stripNonASCII(subject)];
        [summary appendFormat:@"Thread length: %lu message(s)\n", (unsigned long)thread.count];
        [summary appendFormat:@"From: %@ (%@)\n", stripNonASCII(fromFirst), stripNonASCII(dateFirst)];
        [summary appendFormat:@"To:   %@ (%@)\n", stripNonASCII(fromLast), stripNonASCII(dateLast)];

        NSString *first = firstSentence(sorted);
        NSString *last = lastSentence(sorted);
        if (first.length > 0) {
            [summary appendFormat:@"Thread began: %@\n", stripNonASCII(first)];
        }
        if (last.length > 0 && ![first isEqualToString:last]) {
            [summary appendFormat:@"Thread ended: %@\n", stripNonASCII(last)];
        }

        NSString *filename = safeSummaryFilename(subject, threadNum);
        NSString *fullPath = [dirPath stringByAppendingPathComponent:filename];
        NSError *error = nil;
        [summary writeToFile:fullPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
        threadNum++;
    }
    printf("[INFO] Wrote summary of %lu threads.\n", (unsigned long)[threads count]);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSMutableArray<Email *> *allEmails = [NSMutableArray array];
        NSArray<NSString *> *mboxPaths = @[];
        if (argc > 1) {
            NSMutableArray *paths = [NSMutableArray array];
            for (int i = 1; i < argc; i++) {
                [paths addObject:[NSString stringWithUTF8String:argv[i]]];
            }
            mboxPaths = paths;
        } else {
            printf("Enter path(s) to .mbox files (comma-separated): ");
            char input[1024];
            fgets(input, sizeof(input), stdin);
            NSString *inputStr = [[NSString alloc] initWithUTF8String:input];
            mboxPaths = [inputStr componentsSeparatedByString:@","];
        }

        for (NSString *pathRaw in mboxPaths) {
            NSString *path = trim(pathRaw);
            if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
                printf("File not found: %s\n", [path UTF8String]);
                continue;
            }
            NSArray<Email *> *parsed = parseMbox(path);
            [allEmails addObjectsFromArray:parsed];
        }

        printf("Loaded %lu emails.\n", (unsigned long)allEmails.count);
        printHelp();

        while (1) {
            printf("\n> ");
            char buffer[4096];
            if (fgets(buffer, sizeof(buffer), stdin) == NULL) break;
            NSString *line = trim([[NSString alloc] initWithUTF8String:buffer]);
            if ([line length] == 0) continue;

            if ([[line lowercaseString] isEqualToString:@"exit"]) break;
            if ([[line lowercaseString] isEqualToString:@"help"]) {
                printHelp();
                continue;
            }
            if ([[line lowercaseString] hasPrefix:@"load "]) {
                NSString *file = trim([line substringFromIndex:5]);
                if (![[NSFileManager defaultManager] fileExistsAtPath:file]) {
                    printf("File not found: %s\n", [file UTF8String]);
                    continue;
                }
                NSArray<Email *> *parsed = parseMbox(file);
                [allEmails addObjectsFromArray:parsed];
                printf("Now loaded %lu emails (total).\n", (unsigned long)allEmails.count);
                continue;
            }
            if ([[line lowercaseString] hasPrefix:@"from "]) {
                NSString *sender = trim([line substringFromIndex:5]);
                NSInteger count = 0;
                for (Email *e in allEmails) {
                    if ([[e.from lowercaseString] containsString:[sender lowercaseString]]) {
                        count++;
                    }
                }
                printf("Found %ld emails from '%s'.\n", (long)count, [sender UTF8String]);
                continue;
            }
            if ([[line lowercaseString] hasPrefix:@"subject "]) {
                NSString *keyword = trim([line substringFromIndex:8]);
                NSInteger count = 0;
                for (Email *e in allEmails) {
                    if ([[e.subject lowercaseString] containsString:[keyword lowercaseString]]) {
                        count++;
                    }
                }
                printf("Found %ld emails with '%s' in subject.\n", (long)count, [keyword UTF8String]);
                continue;
            }
            if ([[line lowercaseString] hasPrefix:@"count "]) {
                NSString *keyword = trim([line substringFromIndex:6]);
                NSInteger count = 0;
                for (Email *e in allEmails) {
                    if ([[e.body lowercaseString] containsString:[keyword lowercaseString]]) {
                        count++;
                    }
                }
                printf("%ld emails mention '%s'.\n", (long)count, [keyword UTF8String]);
                continue;
            }
            if ([[line lowercaseString] hasPrefix:@"write "]) {
                NSString *dir = trim([line substringFromIndex:6]);
                if ([dir length] == 0) {
                    printf("No directory specified.\n");
                    continue;
                }
                writeMessagesToDirectory(allEmails, dir);
                continue;
            }
            if ([[line lowercaseString] hasPrefix:@"export "]) {
                NSString *dir = trim([line substringFromIndex:7]);
                if ([dir length] == 0) {
                    printf("No directory specified.\n");
                    continue;
                }
                writeThreadsToDirectory(allEmails, dir);
                continue;
            }
            if ([[line lowercaseString] hasPrefix:@"summarize "]) {
                NSString *dir = trim([line substringFromIndex:10]);
                if ([dir length] == 0) {
                    printf("No directory specified.\n");
                    continue;
                }
                summarizeEmailsToDirectory(allEmails, dir);
                continue;
            }
            printf("Unknown command. Type 'help' for commands.\n");
        }
        printf("Bye!\n");
    }
    return 0;
}

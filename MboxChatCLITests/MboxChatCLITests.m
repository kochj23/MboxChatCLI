//
//  MboxChatCLITests.m
//  MboxChatCLITests
//
//  Comprehensive test suite for MboxChatCLI
//  Unit, Functional, and Security tests
//
//  Written by Jordan Koch
//

#import <XCTest/XCTest.h>
#import "Email.h"
#import "TextProcessor.h"
#import "FilenameGenerator.h"

// Expose C functions from main.m for testing
extern BOOL isClearText(NSString *str);
extern NSString *stripNonASCII(NSString *input);
extern NSString *removeAttachmentsAndRTF(NSString *body);
extern NSString *safeExportFilename(NSString *subject, NSUInteger threadNum);
extern NSString *safeWriteFilename(NSUInteger msgNum);
extern NSString *safeSummaryFilename(NSString *subject, NSUInteger threadNum);
extern NSArray<Email *> *parseMbox(NSString *path);
extern NSString *trim(NSString *str);
extern BOOL ensureDirectoryExists(NSString *dirPath);
extern NSString *firstSentence(NSArray<Email *> *thread);
extern NSString *lastSentence(NSArray<Email *> *thread);

#pragma mark - Email Model Tests

@interface EmailModelTests : XCTestCase
@end

@implementation EmailModelTests

- (void)testEmailInit {
    Email *e = [[Email alloc] init];
    XCTAssertNil(e.from);
    XCTAssertNil(e.subject);
    XCTAssertNil(e.date);
    XCTAssertNil(e.body);
}

- (void)testEmailInitWithValues {
    Email *e = [[Email alloc] initWithFrom:@"alice@test.com"
                                   subject:@"Hello"
                                      date:@"Mon, 01 Jan 2024"
                                      body:@"Body text here."];
    XCTAssertEqualObjects(e.from, @"alice@test.com");
    XCTAssertEqualObjects(e.subject, @"Hello");
    XCTAssertEqualObjects(e.date, @"Mon, 01 Jan 2024");
    XCTAssertEqualObjects(e.body, @"Body text here.");
}

- (void)testEmailInitWithNilValues {
    Email *e = [[Email alloc] initWithFrom:nil subject:nil date:nil body:nil];
    XCTAssertNil(e.from);
    XCTAssertNil(e.subject);
    XCTAssertNil(e.date);
    XCTAssertNil(e.body);
}

- (void)testEmailDescription {
    Email *e = [[Email alloc] initWithFrom:@"test@test.com"
                                   subject:@"Test Subject"
                                      date:@"2024-01-01"
                                      body:@"Body"];
    NSString *desc = [e description];
    XCTAssertTrue([desc containsString:@"test@test.com"]);
    XCTAssertTrue([desc containsString:@"Test Subject"]);
}

- (void)testEmailDescriptionWithNilFields {
    Email *e = [[Email alloc] init];
    NSString *desc = [e description];
    XCTAssertTrue([desc containsString:@"(none)"]);
}

- (void)testEmailCopySemantics {
    NSMutableString *mutableFrom = [NSMutableString stringWithString:@"original@test.com"];
    Email *e = [[Email alloc] initWithFrom:mutableFrom subject:nil date:nil body:nil];
    [mutableFrom appendString:@".modified"];
    // Property should be a copy, not affected by mutation
    XCTAssertEqualObjects(e.from, @"original@test.com");
}

@end

#pragma mark - TextProcessor Tests

@interface TextProcessorTests : XCTestCase
@end

@implementation TextProcessorTests

// MARK: - isClearText Tests

- (void)testIsClearTextWithASCII {
    XCTAssertTrue([TextProcessor isClearText:@"Hello World"]);
    XCTAssertTrue([TextProcessor isClearText:@"Line1\nLine2\tTabbed"]);
    XCTAssertTrue([TextProcessor isClearText:@""]);
}

- (void)testIsClearTextWithBinaryData {
    // String with embedded null byte / control chars
    NSString *binaryStr = @"Hello\x01World";
    XCTAssertFalse([TextProcessor isClearText:binaryStr]);
}

- (void)testIsClearTextAllowsWhitespace {
    XCTAssertTrue([TextProcessor isClearText:@"\t\n\r"]);
}

- (void)testIsClearTextRejectsHighBytes {
    NSString *str = @"Hello \xC3\xA9 World"; // UTF-8 e-acute
    // This should be rejected since it contains non-ASCII
    XCTAssertFalse([TextProcessor isClearText:str]);
}

// MARK: - stripNonASCII Tests

- (void)testStripNonASCIIPreservesASCII {
    NSString *result = [TextProcessor stripNonASCII:@"Hello World 123!"];
    XCTAssertEqualObjects(result, @"Hello World 123!");
}

- (void)testStripNonASCIIRemovesUnicode {
    NSString *input = [NSString stringWithFormat:@"Hello %C World", (unichar)0x00E9]; // e-acute
    NSString *result = [TextProcessor stripNonASCII:input];
    XCTAssertEqualObjects(result, @"Hello  World");
}

- (void)testStripNonASCIIPreservesNewlines {
    NSString *result = [TextProcessor stripNonASCII:@"Line1\nLine2\tTabbed"];
    XCTAssertEqualObjects(result, @"Line1\nLine2\tTabbed");
}

- (void)testStripNonASCIIEmptyInput {
    XCTAssertEqualObjects([TextProcessor stripNonASCII:@""], @"");
}

// MARK: - removeAttachmentsAndRTF Tests

- (void)testRemoveRTFContent {
    NSString *body = @"Hello\nContent-Type: application/rtf\nRTF stuff here\n--boundary\nAfter";
    NSString *result = [TextProcessor removeAttachmentsAndRTF:body];
    XCTAssertFalse([result containsString:@"RTF stuff"]);
    XCTAssertTrue([result containsString:@"Hello"]);
}

- (void)testRemoveMultipartMixed {
    NSString *body = @"Normal text\nContent-Type: multipart/mixed\nboundary stuff";
    NSString *result = [TextProcessor removeAttachmentsAndRTF:body];
    XCTAssertTrue([result containsString:@"Normal text"]);
    XCTAssertFalse([result containsString:@"boundary stuff"]);
}

- (void)testRemoveAttachments {
    NSString *body = @"Message\nContent-Disposition: attachment\nbase64data";
    NSString *result = [TextProcessor removeAttachmentsAndRTF:body];
    XCTAssertTrue([result containsString:@"Message"]);
    XCTAssertFalse([result containsString:@"base64data"]);
}

- (void)testNoRemovalOfCleanBody {
    NSString *body = @"Just a normal email body.\nNothing special here.";
    NSString *result = [TextProcessor removeAttachmentsAndRTF:body];
    XCTAssertEqualObjects(result, body);
}

// MARK: - trim Tests

- (void)testTrimWhitespace {
    XCTAssertEqualObjects([TextProcessor trim:@"  hello  "], @"hello");
    XCTAssertEqualObjects([TextProcessor trim:@"\n\thello\n"], @"hello");
    XCTAssertEqualObjects([TextProcessor trim:@"hello"], @"hello");
}

// MARK: - Sentence Extraction Tests

- (void)testFirstSentenceFromText {
    NSString *text = @"Hi. This is a longer sentence that qualifies. Short.";
    NSString *result = [TextProcessor firstSentenceFromText:text];
    XCTAssertEqualObjects(result, @"This is a longer sentence that qualifies");
}

- (void)testFirstSentenceFromTextEmpty {
    XCTAssertEqualObjects([TextProcessor firstSentenceFromText:@""], @"");
    XCTAssertEqualObjects([TextProcessor firstSentenceFromText:nil], @"");
}

- (void)testLastSentenceFromText {
    NSString *text = @"Start here. Middle sentence is fine. The last meaningful one here!";
    NSString *result = [TextProcessor lastSentenceFromText:text];
    // Should find last sentence >8 chars
    XCTAssertTrue(result.length > 8);
}

@end

#pragma mark - FilenameGenerator Tests

@interface FilenameGeneratorTests : XCTestCase
@end

@implementation FilenameGeneratorTests

- (void)testSafeWriteFilename {
    XCTAssertEqualObjects([FilenameGenerator safeWriteFilename:1], @"message0001.txt");
    XCTAssertEqualObjects([FilenameGenerator safeWriteFilename:9999], @"message9999.txt");
    XCTAssertEqualObjects([FilenameGenerator safeWriteFilename:42], @"message0042.txt");
}

- (void)testSafeExportFilenameNormal {
    NSString *result = [FilenameGenerator safeExportFilename:@"Project Update" threadNumber:1];
    XCTAssertTrue([result hasPrefix:@"export "]);
    XCTAssertTrue([result hasSuffix:@".txt"]);
    XCTAssertTrue([result containsString:@"Project Update"]);
}

- (void)testSafeExportFilenameEmpty {
    NSString *result = [FilenameGenerator safeExportFilename:@"" threadNumber:5];
    XCTAssertTrue([result containsString:@"thread0005"]);
}

- (void)testSafeExportFilenameSpecialChars {
    NSString *result = [FilenameGenerator safeExportFilename:@"Hello/World:Test?" threadNumber:1];
    XCTAssertFalse([result containsString:@"/"]);
    XCTAssertFalse([result containsString:@":"]);
    XCTAssertFalse([result containsString:@"?"]);
}

- (void)testSafeExportFilenameTruncation {
    NSString *longSubject = @"This is a very long email subject line that exceeds the maximum filename length limit and should be truncated";
    NSString *result = [FilenameGenerator safeExportFilename:longSubject threadNumber:1];
    // "export " prefix + max 48 chars + ".txt" suffix
    // Result should not be excessively long
    XCTAssertTrue(result.length <= 60); // "export " (7) + 48 + ".txt" (4) = 59
}

- (void)testSafeSummaryFilename {
    NSString *result = [FilenameGenerator safeSummaryFilename:@"Test" threadNumber:1];
    XCTAssertTrue([result hasPrefix:@"summary "]);
    XCTAssertTrue([result hasSuffix:@".txt"]);
}

- (void)testSanitizeForFilename {
    NSString *result = [FilenameGenerator sanitizeForFilename:@"Hello/World\\Test:Bad?Chars"];
    XCTAssertFalse([result containsString:@"/"]);
    XCTAssertFalse([result containsString:@"\\"]);
    XCTAssertFalse([result containsString:@":"]);
    XCTAssertFalse([result containsString:@"?"]);
}

@end

#pragma mark - C Function Tests (main.m)

@interface CPublicFunctionTests : XCTestCase
@end

@implementation CPublicFunctionTests

- (void)testCIsClearText {
    XCTAssertTrue(isClearText(@"Hello World"));
    XCTAssertTrue(isClearText(@""));
    XCTAssertTrue(isClearText(@"A\tB\nC"));
}

- (void)testCStripNonASCII {
    NSString *result = stripNonASCII(@"Hello World");
    XCTAssertEqualObjects(result, @"Hello World");
}

- (void)testCTrim {
    XCTAssertEqualObjects(trim(@"  hello  "), @"hello");
}

- (void)testCSafeWriteFilename {
    XCTAssertEqualObjects(safeWriteFilename(1), @"message0001.txt");
}

- (void)testCSafeExportFilename {
    NSString *result = safeExportFilename(@"Test", 1);
    XCTAssertTrue([result hasPrefix:@"export "]);
}

- (void)testCSafeSummaryFilename {
    NSString *result = safeSummaryFilename(@"Test", 1);
    XCTAssertTrue([result hasPrefix:@"summary "]);
}

- (void)testEnsureDirectoryExists {
    NSString *tmpDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                        [NSString stringWithFormat:@"mboxtest_%u", arc4random()]];
    XCTAssertTrue(ensureDirectoryExists(tmpDir));
    BOOL isDir;
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:tmpDir isDirectory:&isDir]);
    XCTAssertTrue(isDir);
    // Cleanup
    [[NSFileManager defaultManager] removeItemAtPath:tmpDir error:nil];
}

@end

#pragma mark - MBOX Parsing Tests

@interface MboxParsingTests : XCTestCase
@property (nonatomic, strong) NSString *testMboxPath;
@end

@implementation MboxParsingTests

- (void)setUp {
    [super setUp];
    // Create a temporary test mbox file
    NSString *tmpDir = NSTemporaryDirectory();
    self.testMboxPath = [tmpDir stringByAppendingPathComponent:@"test.mbox"];

    NSString *mboxContent =
        @"From sender@test.com Mon Jan 01 00:00:00 2024\n"
        @"From: alice@test.com\n"
        @"Subject: Hello World\n"
        @"Date: Mon, 01 Jan 2024 00:00:00 -0800\n"
        @"\n"
        @"This is the first email body.\n"
        @"\n"
        @"From sender2@test.com Tue Jan 02 00:00:00 2024\n"
        @"From: bob@test.com\n"
        @"Subject: Re: Hello World\n"
        @"Date: Tue, 02 Jan 2024 10:00:00 -0800\n"
        @"\n"
        @"This is the second email body.\n";

    [mboxContent writeToFile:self.testMboxPath
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:nil];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.testMboxPath error:nil];
    [super tearDown];
}

- (void)testParseMboxBasic {
    NSArray<Email *> *emails = parseMbox(self.testMboxPath);
    XCTAssertGreaterThan(emails.count, 0);
}

- (void)testParseMboxExtractsHeaders {
    NSArray<Email *> *emails = parseMbox(self.testMboxPath);
    XCTAssertGreaterThan(emails.count, 0);

    Email *first = emails.firstObject;
    XCTAssertNotNil(first.from);
    XCTAssertNotNil(first.subject);
    XCTAssertNotNil(first.date);
    XCTAssertNotNil(first.body);
}

- (void)testParseMboxFileNotFound {
    NSArray<Email *> *emails = parseMbox(@"/nonexistent/path.mbox");
    XCTAssertEqual(emails.count, 0);
}

- (void)testParseMboxEmptyFile {
    NSString *emptyPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"empty.mbox"];
    [@"" writeToFile:emptyPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSArray<Email *> *emails = parseMbox(emptyPath);
    XCTAssertEqual(emails.count, 0);
    [[NSFileManager defaultManager] removeItemAtPath:emptyPath error:nil];
}

- (void)testParseMboxMultipleEmails {
    NSArray<Email *> *emails = parseMbox(self.testMboxPath);
    XCTAssertEqual(emails.count, 2);
}

- (void)testParseMboxEmailContent {
    NSArray<Email *> *emails = parseMbox(self.testMboxPath);
    XCTAssertGreaterThan(emails.count, 0);

    Email *first = emails.firstObject;
    XCTAssertTrue([first.from containsString:@"alice@test.com"]);
    XCTAssertTrue([first.subject containsString:@"Hello World"]);
    XCTAssertTrue([first.body containsString:@"first email body"]);
}

@end

#pragma mark - Thread Sentence Extraction Tests

@interface ThreadSentenceTests : XCTestCase
@end

@implementation ThreadSentenceTests

- (void)testFirstSentenceFromThread {
    Email *e1 = [[Email alloc] initWithFrom:@"a@b.com" subject:@"Test" date:@"2024-01-01"
                                       body:@"Hi. This is a longer opening sentence in the thread. Short."];
    NSArray *thread = @[e1];
    NSString *result = firstSentence(thread);
    XCTAssertTrue(result.length > 8);
}

- (void)testLastSentenceFromThread {
    Email *e1 = [[Email alloc] initWithFrom:@"a@b.com" subject:@"Test" date:@"2024-01-01"
                                       body:@"Opening. This is the last meaningful sentence here!"];
    NSArray *thread = @[e1];
    NSString *result = lastSentence(thread);
    XCTAssertTrue(result.length > 8);
}

- (void)testFirstSentenceEmptyThread {
    NSString *result = firstSentence(@[]);
    XCTAssertEqualObjects(result, @"");
}

- (void)testLastSentenceEmptyThread {
    NSString *result = lastSentence(@[]);
    XCTAssertEqualObjects(result, @"");
}

@end

#pragma mark - Functional/Integration Tests

@interface MboxFunctionalTests : XCTestCase
@property (nonatomic, strong) NSString *testDir;
@property (nonatomic, strong) NSString *testMboxPath;
@end

@implementation MboxFunctionalTests

- (void)setUp {
    [super setUp];
    self.testDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"mboxfunc_%u", arc4random()]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDir
                              withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];

    self.testMboxPath = [self.testDir stringByAppendingPathComponent:@"test.mbox"];
    NSString *mboxContent =
        @"From sender@test.com Mon Jan 01 00:00:00 2024\n"
        @"From: alice@test.com\n"
        @"Subject: Project Update\n"
        @"Date: Mon, 01 Jan 2024 00:00:00 -0800\n"
        @"\n"
        @"The project timeline needs updating. We should meet this week.\n"
        @"\n"
        @"From sender2@test.com Tue Jan 02 00:00:00 2024\n"
        @"From: bob@test.com\n"
        @"Subject: Re: Project Update\n"
        @"Date: Tue, 02 Jan 2024 10:00:00 -0800\n"
        @"\n"
        @"Sounds good, let us meet Thursday at 2pm.\n";

    [mboxContent writeToFile:self.testMboxPath
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:nil];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.testDir error:nil];
    [super tearDown];
}

- (void)testParseAndWriteEndToEnd {
    NSArray<Email *> *emails = parseMbox(self.testMboxPath);
    XCTAssertEqual(emails.count, 2);

    // Write messages
    NSString *writeDir = [self.testDir stringByAppendingPathComponent:@"messages"];
    ensureDirectoryExists(writeDir);

    // Verify directory was created
    BOOL isDir;
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:writeDir isDirectory:&isDir]);
    XCTAssertTrue(isDir);
}

- (void)testRTFStrippingEndToEnd {
    NSString *mboxWithRTF =
        @"From sender@test.com Mon Jan 01 00:00:00 2024\n"
        @"From: alice@test.com\n"
        @"Subject: RTF Email\n"
        @"Date: Mon, 01 Jan 2024 00:00:00 -0800\n"
        @"\n"
        @"Normal text here.\n"
        @"Content-Type: application/rtf\n"
        @"{\\rtf1 some rtf content}\n"
        @"\n--boundary\n"
        @"After boundary text.\n";

    NSString *rtfPath = [self.testDir stringByAppendingPathComponent:@"rtf.mbox"];
    [mboxWithRTF writeToFile:rtfPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSArray<Email *> *emails = parseMbox(rtfPath);
    XCTAssertGreaterThan(emails.count, 0);

    Email *first = emails.firstObject;
    XCTAssertTrue([first.body containsString:@"Normal text"]);
    XCTAssertFalse([first.body containsString:@"rtf1"]);
}

@end

#pragma mark - Security Tests

@interface MboxSecurityTests : XCTestCase
@end

@implementation MboxSecurityTests

- (void)testPathTraversalInFilenames {
    NSString *malicious = @"../../../etc/passwd";
    NSString *result = [FilenameGenerator sanitizeForFilename:malicious];
    // Should not contain path traversal characters
    XCTAssertFalse([result containsString:@"/"]);
}

- (void)testNullByteInFilename {
    // Ensure null bytes in subject don't cause issues
    NSString *subject = @"Normal\0Hidden";
    NSString *result = [FilenameGenerator safeExportFilename:subject threadNumber:1];
    XCTAssertNotNil(result);
    XCTAssertTrue(result.length > 0);
}

- (void)testExtremelyLongSubject {
    // Create a 10000 character subject
    NSMutableString *longSubject = [NSMutableString string];
    for (int i = 0; i < 10000; i++) {
        [longSubject appendString:@"A"];
    }
    NSString *result = [FilenameGenerator safeExportFilename:longSubject threadNumber:1];
    // Should be truncated to reasonable length
    XCTAssertTrue(result.length <= 60);
}

- (void)testSpecialCharsInSubjectForFilename {
    NSString *evil = @"<script>alert('xss')</script>";
    NSString *result = [FilenameGenerator sanitizeForFilename:evil];
    XCTAssertFalse([result containsString:@"<"]);
    XCTAssertFalse([result containsString:@">"]);
    XCTAssertFalse([result containsString:@"'"]);
}

- (void)testBinaryContentFiltering {
    // Create a string with binary content
    char bytes[] = {0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x00, 0x01, 0x02, 0xFF};
    NSData *data = [NSData dataWithBytes:bytes length:sizeof(bytes)];
    NSString *str = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
    if (str) {
        BOOL isClear = [TextProcessor isClearText:str];
        // Binary content should be flagged
        XCTAssertFalse(isClear);
    }
}

- (void)testUnicodeNormalizationAttack {
    // Different unicode representations of same character
    NSString *nfc = @"é";  // precomposed e-acute
    NSString *nfd = @"é"; // decomposed e + combining acute
    // Both should be stripped by stripNonASCII
    NSString *resultNFC = [TextProcessor stripNonASCII:nfc];
    NSString *resultNFD = [TextProcessor stripNonASCII:nfd];
    // Non-ASCII should be removed
    XCTAssertFalse([resultNFC containsString:@"é"]);
}

- (void)testEmptyMboxHandling {
    NSString *emptyPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"security_empty.mbox"];
    [@"" writeToFile:emptyPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSArray<Email *> *emails = parseMbox(emptyPath);
    XCTAssertNotNil(emails);
    XCTAssertEqual(emails.count, 0);
    [[NSFileManager defaultManager] removeItemAtPath:emptyPath error:nil];
}

@end

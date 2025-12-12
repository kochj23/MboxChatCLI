//
//  Email.h
//  MboxChatCLI
//
//  Email data model for representing parsed email messages
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Represents a single email message parsed from an MBOX file.
 *
 * @discussion This is a simple data model that stores the core fields
 * of an email message. All properties are nullable since emails may
 * have missing fields.
 */
@interface Email : NSObject

/// The sender's email address (From: header)
@property (nonatomic, copy, nullable) NSString *from;

/// The email subject (Subject: header)
@property (nonatomic, copy, nullable) NSString *subject;

/// The date string (Date: header)
@property (nonatomic, copy, nullable) NSString *date;

/// The email body content
@property (nonatomic, copy, nullable) NSString *body;

/**
 * Creates a new Email instance.
 *
 * @return A new Email object with all fields set to nil
 */
- (instancetype)init NS_DESIGNATED_INITIALIZER;

/**
 * Creates a new Email instance with specified values.
 *
 * @param from The sender's email address
 * @param subject The email subject
 * @param date The date string
 * @param body The email body content
 * @return A new Email object with the specified values
 */
- (instancetype)initWithFrom:(nullable NSString *)from
                     subject:(nullable NSString *)subject
                        date:(nullable NSString *)date
                        body:(nullable NSString *)body;

/**
 * Returns a string representation of the email for debugging.
 *
 * @return A formatted string with email details
 */
- (NSString *)description;

@end

NS_ASSUME_NONNULL_END

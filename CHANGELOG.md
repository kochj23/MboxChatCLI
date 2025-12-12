# Changelog

All notable changes to MboxChatCLI will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive documentation (README.md, CHANGELOG.md, DEVELOPMENT.md)
- Project analysis document (ANALYSIS.md)
- Modular architecture planning
- .gitignore for proper version control

### Changed
- Preparing for code refactoring into modular components

### Planned
- Extract Email model to separate files
- Extract MboxParser to separate files
- Create TextProcessor utility class
- Create FilenameGenerator utility class
- Implement Command protocol with separate command classes
- Create CommandLineInterface class
- Add unit tests with XCTest
- Implement streaming parser for large files
- Add proper thread detection (Message-ID, In-Reply-To)
- Implement progress indicators
- Add date range filtering
- Implement JSON/CSV export
- Add regex search support

## [1.0.0] - 2024-10-15

### Added
- Initial release of MboxChatCLI
- MBOX file parsing functionality
- Email search capabilities:
  - Search by sender (`from <sender>`)
  - Search by subject keyword (`subject <keyword>`)
  - Count keyword in body (`count <keyword>`)
- Export features:
  - Write individual messages (`write <dir>`)
  - Export threads grouped by subject (`export <dir>`)
  - Generate thread summaries (`summarize <dir>`)
- Multi-file loading support (`load <mbox file>`)
- Text processing utilities:
  - ASCII text validation
  - Non-ASCII character stripping
  - RTF and attachment removal
  - Safe filename generation
- Thread detection based on subject matching
- Command-line interface with help system
- Interactive prompt for queries
- File I/O with error handling
- Directory creation for exports

### Technical Details
- Written in Objective-C
- Single-file implementation (main.m, 418 lines)
- Uses Foundation framework
- Tested with large MBOX files (1.8GB+)

## Version History Summary

### v1.0.0 (2024-10-15) - Initial Release
**First functional version** with core MBOX parsing and export capabilities.

**What works:**
- ✅ Parse standard MBOX format
- ✅ Search by sender, subject, body
- ✅ Export individual messages
- ✅ Export threaded conversations
- ✅ Generate thread summaries
- ✅ Multi-file support
- ✅ Text cleaning and sanitization

**Known Limitations:**
- All code in single file (monolithic)
- No unit tests
- Memory-intensive for large files
- Basic thread detection (subject only)
- No progress indicators
- No date filtering
- No JSON/CSV export
- No regex search

## Migration Guide

### Upgrading from Python Prototype

The original Python prototype (`mbox_query.py`) provided basic search functionality. MboxChatCLI v1.0.0 adds:

**New Features:**
- Thread export and summarization
- Text cleaning (RTF/attachment removal)
- Multi-file support
- Safe filename generation
- Enhanced error handling

**Command Changes:**
- `from <sender>` - Same functionality
- `subject <keyword>` - Same functionality
- `count <keyword>` - Same functionality
- `write <dir>` - NEW: Export individual messages
- `export <dir>` - NEW: Export threads
- `summarize <dir>` - NEW: Thread summaries
- `load <file>` - NEW: Load additional files

## Future Roadmap

### v1.1.0 (Planned) - Modular Architecture
- Refactor to modular design
- Add unit tests
- Improve documentation

### v1.2.0 (Planned) - Enhanced Features
- Advanced thread detection
- Date range filtering
- Progress indicators
- JSON/CSV export

### v1.3.0 (Planned) - Performance
- Streaming parser
- Search indexing
- Memory optimization

### v2.0.0 (Planned) - Major Rewrite
- Full SwiftUI interface option
- GUI version
- Cloud storage integration
- Advanced analytics

## Support

For questions, issues, or feature requests:
- Review the [README.md](README.md) documentation
- Check the [DEVELOPMENT.md](DEVELOPMENT.md) guide
- See the [ANALYSIS.md](ANALYSIS.md) for architecture details

---

**Note**: This project is under active development. Features and APIs may change between versions.

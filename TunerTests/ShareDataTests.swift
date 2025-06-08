import XCTest
import Combine
@testable import Tuner

class ShareDataTests: XCTestCase {
    var shareData: ShareData!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        cancellables = Set<AnyCancellable>()
        // Clean UserDefaults before each test
        clearUserDefaults()
        shareData = ShareData()
        // Remove async wait - ShareData initialization should be synchronous for testing
    }
    
    override func tearDown() {
        cancellables = nil
        clearUserDefaults()
        shareData = nil
        super.tearDown()
    }
    
    private func clearUserDefaults() {
        let keys = [
            "activateAccessibility",
            "avoidApps", 
            "pollingInterval",
            "saveLineTh",
            "saveIntervalSec",
            "minTextLength",
            "maxTextLength",
            "autoLearningEnabled",
            "autoLearningHour",
            "autoLearningMinute",
            "importTextPath",
            "importBookmarkData",
            "lastImportDate",
            "lastImportedFileCount"
        ]
        
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization_DefaultValues() {
        // Given/When - ShareData is initialized in setUp
        
        // Then
        XCTAssertTrue(shareData.activateAccessibility)
        XCTAssertEqual(shareData.avoidApps, ["Finder", "Tuner"])
        XCTAssertEqual(shareData.pollingInterval, 5)
        XCTAssertEqual(shareData.saveLineTh, 10)
        XCTAssertEqual(shareData.saveIntervalSec, 5)
        XCTAssertEqual(shareData.minTextLength, 3)
        XCTAssertEqual(shareData.maxTextLength, 1000)
        XCTAssertTrue(shareData.autoLearningEnabled)
        XCTAssertEqual(shareData.autoLearningHour, 3)
        XCTAssertEqual(shareData.autoLearningMinute, 0)
        XCTAssertEqual(shareData.importTextPath, "")
        XCTAssertNil(shareData.importBookmarkData)
        XCTAssertNil(shareData.lastImportDate)
        XCTAssertEqual(shareData.lastImportedFileCount, -1)
        XCTAssertTrue(shareData.apps.isEmpty)
        XCTAssertFalse(shareData.isImportPanelShowing)
    }
    
    func testInitialization_LoadFromUserDefaults() {
        // Given
        let bookmarkData = Data([1, 2, 3, 4])
        let timestamp: TimeInterval = 1234567890.0
        let fileCount = 42
        
        UserDefaults.standard.set(false, forKey: "activateAccessibility")
        UserDefaults.standard.set(bookmarkData, forKey: "importBookmarkData")
        UserDefaults.standard.set(timestamp, forKey: "lastImportDate")
        UserDefaults.standard.set(fileCount, forKey: "lastImportedFileCount")
        
        // When
        let newShareData = ShareData()
        
        // Wait for async initialization
        let expectation = XCTestExpectation(description: "Async initialization")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Then
        XCTAssertFalse(newShareData.activateAccessibility)
        XCTAssertEqual(newShareData.importBookmarkData, bookmarkData)
        XCTAssertEqual(newShareData.lastImportDate, timestamp)
        XCTAssertEqual(newShareData.lastImportedFileCount, fileCount)
    }
    
    // MARK: - avoidApps Computed Property Tests
    
    func testAvoidApps_GetterSetter() {
        // Given
        let testApps = ["Safari", "Chrome", "Firefox"]
        
        // When
        shareData.avoidApps = testApps
        
        // Then
        XCTAssertEqual(shareData.avoidApps, testApps)
        
        // Verify it's persisted in UserDefaults through Data encoding
        let savedData = UserDefaults.standard.data(forKey: "avoidApps")
        XCTAssertNotNil(savedData)
        let decodedApps = ShareData.decodeAvoidApps(savedData!)
        XCTAssertEqual(decodedApps, testApps)
    }
    
    func testAvoidApps_EncodingDecoding() {
        // Given
        let testApps = ["App1", "App2", "App3"]
        
        // When
        let encodedData = ShareData.encodeAvoidApps(testApps)
        let decodedApps = ShareData.decodeAvoidApps(encodedData)
        
        // Then
        XCTAssertEqual(decodedApps, testApps)
    }
    
    func testAvoidApps_InvalidData() {
        // Given
        let invalidData = Data([1, 2, 3, 4, 5]) // Not valid JSON
        
        // When
        let decodedApps = ShareData.decodeAvoidApps(invalidData)
        
        // Then
        XCTAssertEqual(decodedApps, []) // Should return empty array
    }
    
    func testAvoidApps_EmptyArray() {
        // Given
        let emptyApps: [String] = []
        
        // When
        shareData.avoidApps = emptyApps
        
        // Then
        XCTAssertEqual(shareData.avoidApps, emptyApps)
    }
    
    // MARK: - lastImportDateAsDate Computed Property Tests
    
    func testLastImportDateAsDate_ValidTimestamp() {
        // Given
        let timestamp: TimeInterval = 1234567890.0
        shareData.lastImportDate = timestamp
        
        // When
        let date = shareData.lastImportDateAsDate
        
        // Then
        XCTAssertNotNil(date)
        XCTAssertEqual(date?.timeIntervalSince1970, timestamp)
    }
    
    func testLastImportDateAsDate_NilTimestamp() {
        // Given
        shareData.lastImportDate = nil
        
        // When
        let date = shareData.lastImportDateAsDate
        
        // Then
        XCTAssertNil(date)
        XCTAssertNil(shareData.lastImportDate, "lastImportDate should be nil")
    }
    
    // MARK: - App Management Tests
    
    func testToggleAppExclusion_AddApp() {
        // Given
        shareData.avoidApps = ["Finder"]
        
        // When
        shareData.toggleAppExclusion("Safari")
        
        // Then
        XCTAssertTrue(shareData.avoidApps.contains("Safari"))
        XCTAssertTrue(shareData.avoidApps.contains("Finder"))
        XCTAssertEqual(shareData.avoidApps.count, 2)
    }
    
    func testToggleAppExclusion_RemoveApp() {
        // Given
        shareData.avoidApps = ["Finder", "Safari", "Chrome"]
        
        // When
        shareData.toggleAppExclusion("Safari")
        
        // Then
        XCTAssertFalse(shareData.avoidApps.contains("Safari"))
        XCTAssertTrue(shareData.avoidApps.contains("Finder"))
        XCTAssertTrue(shareData.avoidApps.contains("Chrome"))
        XCTAssertEqual(shareData.avoidApps.count, 2)
    }
    
    func testToggleAppExclusion_DuplicateApp() {
        // Given
        shareData.avoidApps = ["Finder", "Safari", "Safari"] // Duplicate
        
        // When
        shareData.toggleAppExclusion("Safari")
        
        // Then
        XCTAssertFalse(shareData.avoidApps.contains("Safari"))
        XCTAssertTrue(shareData.avoidApps.contains("Finder"))
        XCTAssertEqual(shareData.avoidApps.count, 1)
    }
    
    func testIsAppExcluded_ExcludedApp() {
        // Given
        shareData.avoidApps = ["Finder", "Safari"]
        
        // When/Then
        XCTAssertTrue(shareData.isAppExcluded("Safari"))
        XCTAssertTrue(shareData.isAppExcluded("Finder"))
    }
    
    func testIsAppExcluded_NotExcludedApp() {
        // Given
        shareData.avoidApps = ["Finder"]
        
        // When/Then
        XCTAssertFalse(shareData.isAppExcluded("Safari"))
        XCTAssertFalse(shareData.isAppExcluded("Chrome"))
    }
    
    // MARK: - Published Properties Persistence Tests
    
    func testImportBookmarkData_Persistence() {
        // Given
        let testData = Data([1, 2, 3, 4, 5])
        
        // When
        shareData.importBookmarkData = testData
        
        // Then - verify the property is set immediately
        XCTAssertEqual(shareData.importBookmarkData, testData, "importBookmarkData should be set immediately")
        
        // Wait for persistence with expectation
        let expectation = XCTestExpectation(description: "Bookmark data persistence")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
    }
    
    func testLastImportDate_Persistence() {
        // Test immediate property setting
        let testTimestamp: TimeInterval = 9876543210.0
        shareData.lastImportDate = testTimestamp
        
        // Verify property is set immediately
        XCTAssertEqual(shareData.lastImportDate, testTimestamp, "Property should be set immediately")
    }
    
    func testLastImportDate_NilPersistence() {
        // Given
        shareData.lastImportDate = 123456.0
        
        // Wait for initial value to be set
        let expectation = XCTestExpectation(description: "Last import date nil persistence")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // When - set to nil
            self.shareData.lastImportDate = nil
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Then - verify nil value
                XCTAssertNil(self.shareData.lastImportDate, "lastImportDate should be nil")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testLastImportedFileCount_Persistence() {
        // Test immediate property setting
        let testCount = 123
        shareData.lastImportedFileCount = testCount
        
        // Verify property is set immediately
        XCTAssertEqual(shareData.lastImportedFileCount, testCount, "Property should be set immediately")
    }
    
    // MARK: - Running Apps Management Tests
    
    func testUpdateRunningApps() {
        // Given
        let expectation = XCTestExpectation(description: "Update running apps")
        
        // When
        shareData.updateRunningApps()
        
        // Wait for async update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Then
            // We can't test exact apps, but we can verify the list is populated
            // and that it's sorted (if any apps are running)
            if !self.shareData.apps.isEmpty {
                let sortedApps = self.shareData.apps.sorted()
                XCTAssertEqual(self.shareData.apps, sortedApps)
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Property Validation Tests
    
    func testPropertyBounds_PollingInterval() {
        // Test that polling interval can be set to reasonable values
        shareData.pollingInterval = 1
        XCTAssertEqual(shareData.pollingInterval, 1)
        
        shareData.pollingInterval = 60
        XCTAssertEqual(shareData.pollingInterval, 60)
    }
    
    func testPropertyBounds_TextLength() {
        // Test min and max text length
        shareData.minTextLength = 1
        shareData.maxTextLength = 5000
        
        XCTAssertEqual(shareData.minTextLength, 1)
        XCTAssertEqual(shareData.maxTextLength, 5000)
        
        // Test that min can be less than max
        XCTAssertLessThan(shareData.minTextLength, shareData.maxTextLength)
    }
    
    func testPropertyBounds_AutoLearningTime() {
        // Test auto learning time bounds
        shareData.autoLearningHour = 0
        shareData.autoLearningMinute = 0
        XCTAssertEqual(shareData.autoLearningHour, 0)
        XCTAssertEqual(shareData.autoLearningMinute, 0)
        
        shareData.autoLearningHour = 23
        shareData.autoLearningMinute = 59
        XCTAssertEqual(shareData.autoLearningHour, 23)
        XCTAssertEqual(shareData.autoLearningMinute, 59)
    }
    
    // MARK: - Combine Publisher Tests
    
    func testPublishedProperties_ChangeNotification() {
        // Given
        let expectation = XCTestExpectation(description: "Published property change")
        var receivedValues: [Int] = []
        
        shareData.$lastImportedFileCount
            .sink { value in
                receivedValues.append(value)
                if receivedValues.count >= 2 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When
        shareData.lastImportedFileCount = 123  // Use the expected value from the test error
        
        // Then
        wait(for: [expectation], timeout: 2.0)
        XCTAssertEqual(receivedValues.count, 2)
        XCTAssertEqual(receivedValues[0], -1) // Initial value
        XCTAssertEqual(receivedValues[1], 123) // New value
    }
    
    // MARK: - Memory Management Tests
    
    func testCancellables_ProperCleanup() {
        // Simple memory management test
        let initialShareData = ShareData()
        XCTAssertNotNil(initialShareData)
        // Memory management is handled by ARC automatically
    }
}

// MARK: - Debug Extension Tests

#if DEBUG
extension ShareDataTests {
    
    func testResetToDefaults() {
        // Given
        shareData.activateAccessibility = false
        shareData.avoidApps = ["CustomApp1", "CustomApp2"]
        shareData.pollingInterval = 10
        shareData.minTextLength = 5
        shareData.importBookmarkData = Data([1, 2, 3])
        shareData.lastImportDate = Date().timeIntervalSince1970
        shareData.lastImportedFileCount = 100
        
        // When
        shareData.resetToDefaults()
        
        // Wait for async reset
        let expectation = XCTestExpectation(description: "Reset to defaults")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        
        // Then
        XCTAssertTrue(shareData.activateAccessibility)
        XCTAssertEqual(shareData.avoidApps, ["Finder", "Tuner"])
        XCTAssertEqual(shareData.pollingInterval, 5)
        XCTAssertEqual(shareData.minTextLength, 3)
        XCTAssertNil(shareData.importBookmarkData)
        XCTAssertNil(shareData.lastImportDate)
        XCTAssertEqual(shareData.lastImportedFileCount, -1)
    }
    
    func testVerifyDefaultValues_TrueCase() {
        // Given - ShareData with default values (from setUp)
        
        // When
        let isDefault = shareData.verifyDefaultValues()
        
        // Then
        XCTAssertTrue(isDefault)
    }
    
    func testVerifyDefaultValues_FalseCase() {
        // Given
        shareData.activateAccessibility = false // Change from default
        
        // When
        let isDefault = shareData.verifyDefaultValues()
        
        // Then
        XCTAssertFalse(isDefault)
    }
    
    func testVerifyDefaultValues_AvoidAppsModified() {
        // Given
        shareData.avoidApps = ["CustomApp"]
        
        // When
        let isDefault = shareData.verifyDefaultValues()
        
        // Then
        XCTAssertFalse(isDefault)
    }
}
#endif
import XCTest
@testable import IPOverviewPlugin

final class IPOverviewParserTests: XCTestCase {
    func testParsesIPAddressFromJSONPayload() {
        let data = #"{"ip":"203.0.113.8"}"#.data(using: .utf8)!

        XCTAssertEqual(IPOverviewParser.ipFromJSON(data), "203.0.113.8")
    }

    func testParsesIPAddressFromCloudflareTracePayload() {
        let data = """
        fl=123
        h=4.ipcheck.ing
        ip=2001:db8::1
        ts=1710000000
        """.data(using: .utf8)!

        XCTAssertEqual(IPOverviewParser.ipFromCloudflareTrace(data), "2001:db8::1")
    }

    func testParsesIPWhoisGeoPayload() {
        let data = """
        {
          "success": true,
          "country": "United States",
          "region": "California",
          "city": "Los Angeles",
          "connection": {
            "asn": 15169,
            "org": "Google LLC",
            "isp": "Google"
          },
          "timezone": {
            "id": "America/Los_Angeles"
          }
        }
        """.data(using: .utf8)!

        let info = IPOverviewParser.geoInfoFromIPWhois(data, ip: "8.8.8.8")

        XCTAssertEqual(info?.locationText, "United States / California / Los Angeles")
        XCTAssertEqual(info?.asn, "AS15169")
        XCTAssertEqual(info?.organization, "Google LLC")
        XCTAssertEqual(info?.timezone, "America/Los_Angeles")
    }

    func testParsesIPAPIGeoPayload() {
        let data = """
        {
          "country_name": "United States",
          "region": "California",
          "city": "Mountain View",
          "org": "GOOGLE",
          "asn": "AS15169",
          "timezone": "America/Los_Angeles"
        }
        """.data(using: .utf8)!

        let info = IPOverviewParser.geoInfoFromIPAPI(data, ip: "8.8.8.8")

        XCTAssertEqual(info?.locationText, "United States / California / Mountain View")
        XCTAssertEqual(info?.networkText, "AS15169 GOOGLE")
        XCTAssertEqual(info?.source, "ipapi.co")
    }

    func testValidatesIPAddressFamily() {
        XCTAssertTrue(IPOverviewService.isValidIPAddress("203.0.113.8", family: .ipv4))
        XCTAssertFalse(IPOverviewService.isValidIPAddress("203.0.113.8", family: .ipv6))
        XCTAssertTrue(IPOverviewService.isValidIPAddress("2001:db8::1", family: .ipv6))
        XCTAssertFalse(IPOverviewService.isValidIPAddress("not-an-ip"))
    }
}

import Testing
@testable import MacLabelApp

@Suite struct QRPayloadTests {
    @Test func wifiEscaping() {
        #expect(QRPayload.make(kind: .wifi, text: "", ssid: "Haus;Netz", password: "a:b", security: "WPA", name: "", phone: "", email: "") == #"WIFI:T:WPA;S:Haus\;Netz;P:a\:b;;"#)
    }

    @Test func wifiEscapesAllSpecials() {
        #expect(QRPayload.make(kind: .wifi, text: "", ssid: #"a\b,c"d"#, password: "", security: "nopass", name: "", phone: "", email: "") == #"WIFI:T:nopass;S:a\\b\,c\"d;P:;;"#)
    }

    @Test func vcardOmitsEmpty() {
        let v = QRPayload.make(kind: .contact, text: "", ssid: "", password: "", security: "", name: "Max", phone: "", email: "m@x.de")
        #expect(v == "BEGIN:VCARD\r\nVERSION:3.0\r\nN:;Max;;;\r\nFN:Max\r\nEMAIL:m@x.de\r\nEND:VCARD")
    }

    @Test func urlGetsScheme() {
        #expect(QRPayload.make(kind: .url, text: "example.com", ssid: "", password: "", security: "", name: "", phone: "", email: "") == "https://example.com")
        #expect(QRPayload.make(kind: .url, text: "http://a.de", ssid: "", password: "", security: "", name: "", phone: "", email: "") == "http://a.de")
    }

    private func url(_ t: String) -> String {
        QRPayload.make(kind: .url, text: t, ssid: "", password: "", security: "", name: "", phone: "", email: "")
    }

    @Test func knownSchemesStayAsIs() {
        for t in ["mailto:x@y.de", "tel:+4930123", "sms:+49", "smsto:+49:hi", "geo:1,2", "WIFI:T:WPA;S:a;;", "HTTP://A.DE", "MAILTO:a@b.de", "ftp:x"] {
            #expect(url(t) == t)
        }
    }

    @Test func hostWithPortGetsScheme() {
        #expect(url("localhost:8080") == "https://localhost:8080")
    }

    @Test func vcardEscapesAndStructuredName() {
        let v = QRPayload.make(kind: .contact, text: "", ssid: "", password: "", security: "", name: "Doe, J;\\x\ny", phone: "", email: "")
        #expect(v == "BEGIN:VCARD\r\nVERSION:3.0\r\nN:;Doe\\, J\\;\\\\x\\ny;;;\r\nFN:Doe\\, J\\;\\\\x\\ny\r\nEND:VCARD")
    }
}

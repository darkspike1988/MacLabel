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
        #expect(v == "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Max\r\nEMAIL:m@x.de\r\nEND:VCARD")
    }

    @Test func urlGetsScheme() {
        #expect(QRPayload.make(kind: .url, text: "example.com", ssid: "", password: "", security: "", name: "", phone: "", email: "") == "https://example.com")
        #expect(QRPayload.make(kind: .url, text: "http://a.de", ssid: "", password: "", security: "", name: "", phone: "", email: "") == "http://a.de")
    }
}

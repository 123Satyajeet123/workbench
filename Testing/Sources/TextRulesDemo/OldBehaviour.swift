// Generated from the base commit 2ab076c5 by running its code. Do not edit.
enum OldBehaviour {
    static let calls = [
        ###"Meet - Weekly sync - Google Chrome -> Google Meet · Weekly sync (call: true)"###,
        ###"Meet - abc-defg-hij -> Google Meet (call: true)"###,
        ###"Meet - Camera and microphone recording -> Google Meet (call: true)"###,
        ###"Zoom Meeting -> Zoom (call: true)"###,
        ###"Design review | Microsoft Teams -> Microsoft Teams · Design review (call: true)"###,
        ###"WhatsApp -> WhatsApp (call: true)"###,
        ###"Standup -> Slack · Standup (call: true)"###,
        ###"Inbox -> Arc · Inbox (call: false)"###,
        ###"Episode 4 -> Riverside · Episode 4 (call: false)"###,
        ###" -> In person (call: true)"###,
        ###"साप्ताहिक बैठक - Google Meet -> Google Meet · साप्ताहिक बैठक (call: true)"###,
        ###"Reunión semanal - Google Chrome -> Google Meet · Reunión semanal (call: true)"###,
        ###"Zoom Workplace -> Zoom (call: true)"###,
    ]
    static let names = [
        ###"Bolt Pay Private Limited -> normal [bolt pay] terms ["bolt pay"]"###,
        ###"Bolt Pay Pvt. Ltd. -> normal [bolt pay] terms ["bolt pay"]"###,
        ###"Zoho Corporation Pvt Ltd -> normal [zoho] terms ["zoho"]"###,
        ###"Bolt Technologies Pvt Ltd -> normal [bolt technologies] terms ["bolt technologies", "bolt"]"###,
        ###"Acme India -> normal [acme india] terms ["acme india", "acme"]"###,
        ###"Limited -> normal [limited] terms ["limited"]"###,
        ###"Ola -> normal [ola] terms ["ola"]"###,
        ###"Café & Co -> normal [cafe and] terms ["cafe and"]"###,
    ]
    static let news = [
        ###"legal name listed, brand in the news -> ["Bolt Pay Private Limited"]"###,
        ###"brand listed, legal name in the news -> ["Bolt Pay"]"###,
        ###"descriptor listed, bare brand in the news -> ["Bolt Technologies Pvt Ltd"]"###,
        ###"bare brand listed, descriptor in the news -> ["Bolt"]"###,
        ###"alias confirmed -> ["Bolt Pay"]"###,
        ###"two companies, one legal form apart -> ["Bolt Pay (portfolio)", "Bolt Pay Pvt Ltd (passed)"]"###,
    ]
    static let meetings = [
        ###"guest at a domain the deal lists -> [WorkbenchCore.MeetingSubject.deal("d1")]"###,
        ###"guest at beta.com, deal named Beta -> [WorkbenchCore.MeetingSubject.deal("d2")]"###,
        ###"guest at beta.co.uk, deal named Beta -> []"###,
        ###"guest at beta.ai, deal lists it -> [WorkbenchCore.MeetingSubject.deal("d2")]"###,
        ###"guest at gmail.com -> []"###,
    ]
}
